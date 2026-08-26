import AppIntents
import Foundation
import HomeAutomationCore
import HomeAutomationOrchestrator

/// Runs a natural-language home request through the on-device agent pipeline.
///
/// This is a `LongRunningIntent` (iOS 27) rather than a plain `AppIntent`
/// because the pipeline genuinely exceeds the 30-second intent budget: most
/// graph agents carry 60s timeouts, the verifier loop can run three iterations
/// with up to three repair calls each, and `FoundationModelGate` throttles
/// Foundation Models to two concurrent calls. `performBackgroundTask` extends
/// the runtime and hands the system a `Progress` it renders as a Live Activity
/// with a stop button.
///
/// `CancellableIntent` is what unlocks the `onCancel:` overload of
/// `performBackgroundTask` — the two-closure form is only available
/// `where Self: CancellableIntent`.
///
/// Resolution always runs on the Adaptive Static portfolio arm with the graph
/// compiler off (`HomeAutomationRuntime.intentChoice` / `.intentCompiler`),
/// independent of whatever the app's pickers are set to.
struct ResolveHomeCommandIntent: AppIntent, LongRunningIntent, CancellableIntent {
    static let title: LocalizedStringResource = "Run Home Command"

    static let description = IntentDescription(
        """
        Resolves a natural-language home request through the on-device multi-agent \
        pipeline and shows the resulting device command or automation.
        """,
        categoryName: "Home Automation",
        searchKeywords: ["home", "smart home", "light", "automation", "device"]
    )

    /// Runs without foregrounding the app.
    static var supportedModes: IntentModes { .background }

    /// Pinned to the host app process. The device registry is an in-memory
    /// actor and the RAG index is a dense vector store over a 10k-example
    /// dataset — running in an extension would mean a separate device world and
    /// a second index build.
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$command) at home")
    }

    @Parameter(
        title: "Command",
        description: "What you want to happen, in plain language.",
        requestValueDialog: "What should I do at home?"
    )
    var command: String

    init() {}

    init(command: String) {
        self.command = command
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String>
                                      & ProvidesDialog & ShowsSnippetIntent {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppIntentError.Unrecoverable.entityNotFound
        }

        let runID = UUID()
        let tracker = await StageProgressTracker()

        await publish(.running(stage: "Starting", fraction: 0), for: runID)

        // A single agent can hold for 60 seconds without emitting anything.
        // `performBackgroundTask`'s contract is explicit that a task which stops
        // updating `progress` can have its runtime extension cancelled, so
        // event-driven updates alone are not enough to stay alive.
        let heartbeat = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { break }
                report(await tracker.heartbeat())
            }
        }
        defer { heartbeat.cancel() }

        do {
            let result = try await performBackgroundTask {
                let orchestrator = await HomeAutomationRuntime.shared.intentOrchestrator()
                var finalResult: HomeAutomationResolverResult?

                let stream = orchestrator.resolveStream(
                    trimmed,
                    executeLowRiskCommands: true
                )

                for try await update in stream {
                    try Task.checkCancellation()

                    switch update {
                    case .event(let event):
                        // Advance the tracker and refresh the snippet's phase in
                        // one hop, so the two can never disagree, then write the
                        // result into `progress`.
                        let update = await MainActor.run { () -> ProgressReport in
                            let report = tracker.observe(event)
                            HomeCommandRunStore.shared.set(
                                .running(stage: report.title, fraction: report.fraction),
                                for: runID
                            )
                            return report
                        }
                        report(update)
                        HomeCommandSnippetIntent.reload()
                    case .result(let resolved):
                        finalResult = resolved
                    }
                }

                guard let finalResult else {
                    throw FoundationLabCoreError.invalidRequest(
                        "Orchestrator stream ended without a result"
                    )
                }
                return finalResult
            } onCancel: { reason in
                Task { @MainActor in
                    HomeCommandRunStore.shared.set(.cancelled(reason), for: runID)
                    HomeCommandSnippetIntent.reload()
                }
            }

            heartbeat.cancel()
            report(await tracker.finish())
            await publish(.finished(result), for: runID)

            let summary = result.resolution.displaySummary
            return .result(
                value: summary,
                dialog: IntentDialog(stringLiteral: summary),
                snippetIntent: HomeCommandSnippetIntent(runID: runID.uuidString)
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await publish(.failed(error.localizedDescription), for: runID)
            throw error
        }
    }

    /// Publishes one update to the user through `ProgressReportingIntent.progress`.
    ///
    /// This is the whole propagation channel. The system passes an `NSProgress`
    /// into the intent's perform call and watches it; Live Activities renders
    /// `localizedDescription` as the task's title, `localizedAdditionalDescription`
    /// as its subtitle, and `completedUnitCount` / `totalUnitCount` as the bar.
    ///
    /// `progress` is read fresh on every line rather than captured. It is a
    /// getter-only computed property on a protocol extension — there is no
    /// storage on the intent — so a captured reference would depend on
    /// undocumented behaviour. Apple's own sample re-reads it the same way.
    private func report(_ update: ProgressReport) {
        progress.totalUnitCount = update.totalUnitCount
        progress.completedUnitCount = update.completedUnitCount
        progress.localizedDescription = update.title
        progress.localizedAdditionalDescription = update.subtitle
    }

    /// Writes a phase to the shared store and re-renders the snippet.
    private func publish(_ phase: HomeCommandRunStore.Phase, for runID: UUID) async {
        await Self.publish(phase, for: runID)
    }

    private static func publish(_ phase: HomeCommandRunStore.Phase, for runID: UUID) async {
        await MainActor.run {
            HomeCommandRunStore.shared.set(phase, for: runID)
        }
        HomeCommandSnippetIntent.reload()
    }
}
