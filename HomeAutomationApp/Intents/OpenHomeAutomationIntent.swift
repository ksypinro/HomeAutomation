import AppIntents
import Foundation

/// Brings the app forward from a snippet.
///
/// This is what the snippet offers when a resolution comes back as
/// `.requiresConfirmation`. It deliberately does *not* execute anything.
///
/// That resolution case is terminal by design: `OrchestratorPolicyEngine`
/// routes to it precisely to stop execution, and nothing in the codebase turns
/// a confirmed `HomeCommandDraft` back into an executable
/// `HomeAutomationExecutionPlan`. A "Confirm & run" button would have to
/// hand-build a plan and call `executeLowRiskPlan` directly, bypassing the
/// safety gate that the case exists to enforce. So the button opens the app,
/// where the existing confirmation UI governs.
struct OpenHomeAutomationIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Home Automation"

    static var isDiscoverable: Bool { false }

    /// The whole point is to bring the app forward.
    static var supportedModes: IntentModes { .foreground(.immediate) }

    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    init() {}

    func perform() async throws -> some IntentResult {
        .result()
    }
}
