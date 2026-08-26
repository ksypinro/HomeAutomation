import AppIntents
import Foundation

/// Draws the result of a `ResolveHomeCommandIntent` run.
///
/// The system invokes this independently of the intent that returned it, and
/// re-invokes it on every `reload()` — which is what makes the snippet update
/// live while the pipeline is still running. It therefore reads its state from
/// `HomeCommandRunStore` rather than from the parent intent, keyed by a run id
/// carried as a parameter.
struct HomeCommandSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Home Command Result"

    /// Not a user-facing action — it exists only to render the snippet, so keep
    /// it out of Shortcuts and Spotlight.
    static var isDiscoverable: Bool { false }

    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Run")
    var runID: String

    init() {}

    init(runID: String) {
        self.runID = runID
    }

    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let id = runID
        let phase = await MainActor.run {
            UUID(uuidString: id).flatMap { HomeCommandRunStore.shared.phase(for: $0) }
        }
        return .result(view: HomeCommandSnippetView(runID: id, phase: phase))
    }
}
