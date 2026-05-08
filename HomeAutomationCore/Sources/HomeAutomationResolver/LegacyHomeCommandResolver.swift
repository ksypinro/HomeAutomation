import Foundation
import FoundationModels
import HomeAutomationCore

private typealias LegacyEventSink = @Sendable (LegacyPipelineEvent) -> Void

/// Deprecated legacy entry point retained for downstream compatibility.
/// New app code should use `HomeCommandOrchestrator` from `HomeAutomationOrchestrator`.
public final class LegacyHomeCommandResolver: HomeCommandResolving {
    private let registry: MockHomeDeviceRegistry
    private let workerLayer: any HomeWorkerSessionAnalyzing
    private let candidateStore: LegacyCandidateContextStore
    private let candidateResolver: any HomeCandidateResolving
    private let instructionFactory: LegacyInstructionSetFactory
    private let draftResolver: any HomeCommandDraftResolving
    private let validator: LegacyCommandValidator
    private let executor: LegacyPlanExecutor
    private let ruleBasedResolver: LegacyRuleBasedResolver
    private let foundationModelAvailability: @Sendable () -> Bool
    private let pipelineTimeoutNanoseconds: UInt64
    private let metricsCollector: LegacyMetricsCollector
    private let candidateMetrics: LegacyCandidateResolverMetrics
    private let draftMetrics: LegacyDraftResolverMetrics
    private let adapterDiagnosticsStore: HomeAdapterModelDiagnosticsStore

    public init(
        registry: MockHomeDeviceRegistry = MockHomeDeviceRegistry(),
        workerLayer: (any HomeWorkerSessionAnalyzing)? = nil,
        candidateStore: LegacyCandidateContextStore = LegacyCandidateContextStore(),
        candidateResolver: (any HomeCandidateResolving)? = nil,
        instructionFactory: LegacyInstructionSetFactory? = nil,
        draftResolver: (any HomeCommandDraftResolving)? = nil,
        validator: LegacyCommandValidator = LegacyCommandValidator(),
        metricsCollector: LegacyMetricsCollector = LegacyMetricsCollector(),
        pipelineTimeoutNanoseconds: UInt64 = 30_000_000_000,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        }
    ) {
        self.registry = registry
        self.foundationModelAvailability = foundationModelAvailability
        let candidateMetrics = LegacyCandidateResolverMetrics()
        let draftMetrics = LegacyDraftResolverMetrics()
        let adapterDiagnosticsStore = HomeAdapterModelDiagnosticsStore()
        self.candidateMetrics = candidateMetrics
        self.draftMetrics = draftMetrics
        self.adapterDiagnosticsStore = adapterDiagnosticsStore
        self.workerLayer = workerLayer ?? LegacyPartialSafeWorkerSessionLayer(
            foundationModelAvailability: foundationModelAvailability
        )
        self.candidateStore = candidateStore
        self.candidateResolver = candidateResolver ?? LegacyCandidateResolver(metrics: candidateMetrics)
        self.instructionFactory = instructionFactory ?? LegacyInstructionSetFactory(
            toolProvider: LegacyToolProvider(registry: registry)
        )
        self.draftResolver = draftResolver ?? LegacyDraftResolver(
            adapterProvider: HomeAdapterModelProvider(diagnosticsStore: adapterDiagnosticsStore),
            metrics: draftMetrics
        )
        self.validator = validator
        self.executor = LegacyPlanExecutor(registry: registry)
        self.pipelineTimeoutNanoseconds = pipelineTimeoutNanoseconds
        self.metricsCollector = metricsCollector
        self.ruleBasedResolver = LegacyRuleBasedResolver(registry: registry, validator: validator)
    }

    public func resolve(
        _ text: String,
        executeLowRiskCommands: Bool = true
    ) async throws -> HomeAutomationResolverResult {
        var finalResult: HomeAutomationResolverResult?
        for try await update in resolveStream(text, executeLowRiskCommands: executeLowRiskCommands) {
            if case .result(let result) = update {
                finalResult = result
            }
        }
        guard let finalResult else {
            throw FoundationLabCoreError.invalidRequest("legacy stream ended without a result")
        }
        return finalResult
    }

    public func resolveStream(
        _ text: String,
        executeLowRiskCommands: Bool = true
    ) -> AsyncThrowingStream<LegacyResolverUpdate, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await resolveInternal(
                        text,
                        executeLowRiskCommands: executeLowRiskCommands,
                        emit: { event in
                            continuation.yield(.event(event))
                        }
                    )
                    continuation.yield(.result(result))
                    continuation.finish()
                } catch {
                    continuation.yield(
                        .event(
                            LegacyPipelineEvent(
                                stage: .resolver,
                                title: "Resolver",
                                status: .failed,
                                detail: error.localizedDescription
                            )
                        )
                    )
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func lastMetricsJSON() async -> String? {
        await metricsCollector.lastMetricsJSON()
    }

    private func event(
        _ stage: LegacyPipelineStage,
        _ title: String,
        _ status: LegacyPipelineEvent.Status,
        _ detail: String = ""
    ) -> LegacyPipelineEvent {
        LegacyPipelineEvent(stage: stage, title: title, status: status, detail: detail)
    }

    private func resolveInternal(
        _ text: String,
        executeLowRiskCommands: Bool,
        emit: @escaping LegacyEventSink
    ) async throws -> HomeAutomationResolverResult {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw FoundationLabCoreError.invalidRequest("Missing home command")
        }

        let eventCounter = LegacyEventCounter()
        let emitEvent: LegacyEventSink = { event in
            eventCounter.increment()
            emit(event)
        }

        emitEvent(event(.input, "Input", .completed, trimmedText))
        var metrics = LegacyResolutionMetrics(
            command: trimmedText,
            foundationModelAvailable: foundationModelAvailability()
        )

        emitEvent(event(.ruleBasedPrecheck, "Rule-Based Precheck", .running))
        if let ruleResult = try await ruleBasedResolver.resolveIfHighConfidence(
            trimmedText,
            executeLowRiskCommands: executeLowRiskCommands
        ) {
            emitEvent(event(.ruleBasedPrecheck, "Rule-Based Precheck", .completed, ruleResult.resolution.displaySummary))
            metrics.usedRuleBasedFallback = true
            metrics.fallbackReason = "high-confidence rule-based match"
            metrics.stageDurations["ruleBased"] = 0
            finishMetrics(&metrics, result: ruleResult)
            metrics.emittedEventCount = eventCounter.count
            await metricsCollector.store(metrics)
            emitEvent(event(.metrics, "Metrics", .completed))
            emitEvent(event(.outcome, "Outcome", .completed, ruleResult.resolution.displaySummary))
            metrics.emittedEventCount = eventCounter.count
            await metricsCollector.store(metrics)
            return ruleResult
        }
        emitEvent(event(.ruleBasedPrecheck, "Rule-Based Precheck", .completed, "No high-confidence rule match"))

        emitEvent(event(.availability, "Foundation Models Availability", .completed, metrics.foundationModelAvailable ? "available" : "unavailable"))
        guard metrics.foundationModelAvailable else {
            emitEvent(event(.fallback, "Fallback Resolver", .running, "Foundation Models unavailable"))
            let timer = LegacyStageTimer()
            let result = try await ruleBasedResolver.resolve(
                trimmedText,
                executeLowRiskCommands: executeLowRiskCommands
            )
            metrics.usedRuleBasedFallback = true
            metrics.fallbackReason = "foundation model unavailable"
            metrics.stageDurations["ruleBased"] = timer.elapsedSeconds()
            finishMetrics(&metrics, result: result)
            emitEvent(event(.fallback, "Fallback Resolver", .completed, result.resolution.displaySummary))
            emitEvent(event(.metrics, "Metrics", .completed))
            emitEvent(event(.outcome, "Outcome", .completed, result.resolution.displaySummary))
            metrics.emittedEventCount = eventCounter.count
            await metricsCollector.store(metrics)
            return result
        }

        do {
            let initialMetrics = metrics
            let output = try await LegacyTimeout.run(nanoseconds: pipelineTimeoutNanoseconds) {
                var foundationMetrics = initialMetrics
                let result = try await self.resolveWithFoundationModels(
                    trimmedText,
                    executeLowRiskCommands: executeLowRiskCommands,
                    metrics: &foundationMetrics,
                    emit: emitEvent
                )
                return LegacyPipelineOutput(result: result, metrics: foundationMetrics)
            }
            metrics = output.metrics
            let result = output.result
            finishMetrics(&metrics, result: result)
            metrics = await applyingDraftAndAdapterMetrics(to: metrics)
            metrics.emittedEventCount = eventCounter.count
            await metricsCollector.store(metrics)
            emitEvent(event(.metrics, "Metrics", .completed))
            emitEvent(event(.outcome, "Outcome", .completed, result.resolution.displaySummary))
            metrics.emittedEventCount = eventCounter.count
            await metricsCollector.store(metrics)
            return result
        } catch {
            emitEvent(event(.fallback, "Fallback Resolver", .running, "Foundation Models failed: \(error.localizedDescription)"))
            let timer = LegacyStageTimer()
            let result = try await ruleBasedResolver.resolve(
                trimmedText,
                executeLowRiskCommands: executeLowRiskCommands
            )
            metrics.usedRuleBasedFallback = true
            metrics.fallbackReason = "foundation model failure"
            metrics.failureDescription = error.localizedDescription
            metrics.stageDurations["fallbackAfterFailure"] = timer.elapsedSeconds()
            finishMetrics(&metrics, result: result)
            metrics = await applyingDraftAndAdapterMetrics(to: metrics)
            emitEvent(event(.fallback, "Fallback Resolver", .completed, result.resolution.displaySummary))
            emitEvent(event(.metrics, "Metrics", .completed))
            emitEvent(event(.outcome, "Outcome", .completed, result.resolution.displaySummary))
            metrics.emittedEventCount = eventCounter.count
            await metricsCollector.store(metrics)
            return result
        }
    }

    private func resolveWithFoundationModels(
        _ text: String,
        executeLowRiskCommands: Bool,
        metrics: inout LegacyResolutionMetrics,
        emit: @escaping LegacyEventSink
    ) async throws -> HomeAutomationResolverResult {
        metrics.usedFoundationModels = true

        emit(event(.workers, "Worker Analysis", .running))
        var timer = LegacyStageTimer()
        let state = try await workerLayer.analyze(text)
        metrics.stageDurations["workers"] = timer.elapsedSeconds()
        metrics.workerConfidence = min(
            state.language.confidence,
            state.domain.confidence,
            state.intent.confidence,
            state.deviceType.confidence,
            state.slots.confidence,
            state.risk.confidence
        )
        metrics.riskLevel = String(describing: state.risk.riskLevel)
        emit(
            event(
                .workers,
                "Worker Analysis",
                .completed,
                state.intent.topFamilies.map { String(describing: $0) }.joined(separator: ", ")
            )
        )

        guard state.domain.domain == .homeAutomation else {
            return HomeAutomationResolverResult(
                state: state,
                retrievedCandidates: [],
                aggregation: HomeCandidateAggregationResult(
                    finalCandidateIDs: [],
                    needsClarification: false,
                    confidence: state.domain.confidence
                ),
                hydratedCandidates: [],
                draft: nil,
                resolution: .unsupported("This does not look like a home-automation command.")
            )
        }

        emit(event(.registry, "Candidate Retrieval", .running))
        timer = LegacyStageTimer()
        let candidates = await registry.retrieveCandidates(text: text, hints: state)
        metrics.stageDurations["registry"] = timer.elapsedSeconds()
        metrics.retrievedCandidateCount = candidates.count
        await candidateStore.save(candidates)
        emit(event(.registry, "Candidate Retrieval", .completed, "\(candidates.count) candidate(s)"))

        emit(event(.candidateResolution, "Candidate Resolution", .running))
        timer = LegacyStageTimer()
        let aggregation = try await candidateResolver.resolveCandidates(
            userText: text,
            resolutionState: state,
            candidates: candidates.map(\.compactView)
        )
        metrics.stageDurations["candidateResolution"] = timer.elapsedSeconds()
        metrics.candidateStrategy = await candidateMetrics.lastStrategy
        metrics.candidateConfidence = aggregation.confidence
        metrics.selectedCandidateIDs = aggregation.finalCandidateIDs
        emit(
            event(
                .candidateResolution,
                "Candidate Resolution",
                .completed,
                aggregation.finalCandidateIDs.joined(separator: ", ")
            )
        )

        if aggregation.needsClarification {
            return HomeAutomationResolverResult(
                state: state,
                retrievedCandidates: candidates,
                aggregation: aggregation,
                hydratedCandidates: [],
                draft: nil,
                resolution: .needsClarification(
                    aggregation.clarificationQuestion ?? "Which device do you want to control?"
                )
            )
        }

        emit(event(.hydration, "Candidate Hydration", .running))
        timer = LegacyStageTimer()
        let hydratedCandidates = await candidateStore.hydrate(ids: aggregation.finalCandidateIDs)
        metrics.stageDurations["hydration"] = timer.elapsedSeconds()
        emit(event(.hydration, "Candidate Hydration", .completed, "\(hydratedCandidates.count) candidate(s)"))
        let finalInput = HomeFinalResolutionInput(
            rawText: text,
            resolutionState: state,
            hydratedCandidates: hydratedCandidates,
            aggregation: aggregation
        )

        emit(event(.draftResolution, "Draft Resolution", .running))
        timer = LegacyStageTimer()
        let package = instructionFactory.makePackage(from: finalInput)
        metrics.selectedToolNames = package.tools.map(\.name)
        let draft = try await draftResolver.resolveDraft(from: package)
        metrics.stageDurations["draftResolution"] = timer.elapsedSeconds()
        metrics.draftConfidence = draft.confidence
        emit(event(.draftResolution, "Draft Resolution", .completed, "confidence \(draft.confidence)"))

        emit(event(.validation, "Validation", .running))
        timer = LegacyStageTimer()
        var resolution = validator.validate(draft, input: finalInput)
        metrics.stageDurations["validation"] = timer.elapsedSeconds()
        emit(event(.validation, "Validation", .completed, resolution.displaySummary))

        if executeLowRiskCommands,
           case .readyToExecute(let plan) = resolution,
           !plan.requiresConfirmation,
           plan.steps.allSatisfy({ $0.type != "query" }) {
            emit(event(.execution, "Execution", .running))
            timer = LegacyStageTimer()
            let updatedDevice = try await executor.executeLowRiskPlan(plan)
            metrics.stageDurations["execution"] = timer.elapsedSeconds()
            resolution = .executed(plan, updatedDevice: updatedDevice)
            emit(event(.execution, "Execution", .completed, updatedDevice.displayName))
        } else {
            emit(event(.execution, "Execution", .completed, "skipped"))
        }

        return HomeAutomationResolverResult(
            state: state,
            retrievedCandidates: candidates,
            aggregation: aggregation,
            hydratedCandidates: hydratedCandidates,
            draft: draft,
            resolution: resolution
        )
    }

    private func finishMetrics(
        _ metrics: inout LegacyResolutionMetrics,
        result: HomeAutomationResolverResult
    ) {
        metrics.finishedAt = Date()
        metrics.retrievedCandidateCount = max(metrics.retrievedCandidateCount, result.retrievedCandidates.count)
        if metrics.selectedCandidateIDs.isEmpty {
            metrics.selectedCandidateIDs = result.aggregation.finalCandidateIDs
        }
        metrics.candidateConfidence = max(metrics.candidateConfidence, result.aggregation.confidence)
        metrics.riskLevel = String(describing: result.state.risk.riskLevel)
        metrics.draftConfidence = metrics.draftConfidence ?? result.draft?.confidence
        metrics.falseExecutionRiskTracked = true

        switch result.resolution {
        case .readyToExecute:
            metrics.outcome = "readyToExecute"
        case .executed:
            metrics.outcome = "executed"
            metrics.executed = true
        case .requiresConfirmation:
            metrics.outcome = "requiresConfirmation"
            metrics.requiresConfirmation = true
        case .needsClarification:
            metrics.outcome = "needsClarification"
        case .unsupported:
            metrics.outcome = "unsupported"
        }

        metrics.workerDuration = metrics.stageDurations["workers"]
        metrics.retrievalDuration = metrics.stageDurations["registry"]
        metrics.candidateResolutionDuration = metrics.stageDurations["candidateResolution"]
        metrics.hydrationDuration = metrics.stageDurations["hydration"]
        metrics.draftResolutionDuration = metrics.stageDurations["draftResolution"]
        metrics.validationDuration = metrics.stageDurations["validation"]
        metrics.executionDuration = metrics.stageDurations["execution"]
        if let finishedAt = metrics.finishedAt {
            metrics.totalDuration = finishedAt.timeIntervalSince(metrics.startedAt)
        }
    }

    private func applyingDraftAndAdapterMetrics(to metrics: LegacyResolutionMetrics) async -> LegacyResolutionMetrics {
        var metrics = metrics
        if let report = await draftMetrics.lastReport() {
            metrics.draftAttemptCount = report.attemptCount
            metrics.draftAttemptSummaries = report.attemptSummaries
            metrics.bestDraftAttempt = report.bestDraftAttempt
        }

        if let diagnostic = adapterDiagnosticsStore.lastDiagnostic() {
            metrics.adapterLoadAttempted = diagnostic.attempted
            metrics.adapterLoadSucceeded = diagnostic.succeeded
            metrics.adapterLoadErrorDescription = diagnostic.errorDescription
        }
        return metrics
    }
}

private struct LegacyPipelineOutput: Sendable {
    let result: HomeAutomationResolverResult
    let metrics: LegacyResolutionMetrics
}

private final class LegacyEventCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}
