import AppIntents
import Foundation
import HomeAutomationCore

/// Shared state handoff between `ResolveHomeCommandIntent` and
/// `HomeCommandSnippetIntent`.
///
/// A `SnippetIntent`'s `perform()` is a *separate* invocation from the intent
/// that returned it, and it runs again on every `reload()`. It therefore cannot
/// read the parent intent's locals — it only gets its own `@Parameter` values.
/// So the parent writes phases here under a run id and passes just that id to
/// the snippet. This works because both intents declare
/// `allowedExecutionTargets = .main` and so share one process.
@MainActor
final class HomeCommandRunStore {
    static let shared = HomeCommandRunStore()

    enum Phase {
        case running(stage: String, fraction: Double)
        case finished(HomeAutomationResolverResult)
        case failed(String)
        case cancelled(IntentCancellationReason)
    }

    /// Runs are only needed for as long as their snippet is on screen; keep a
    /// small ring so a long Shortcuts session can't grow this without bound.
    private static let retainedRunCount = 8

    private var phases: [UUID: Phase] = [:]
    private var order: [UUID] = []

    private init() {}

    func set(_ phase: Phase, for id: UUID) {
        if phases[id] == nil {
            order.append(id)
            while order.count > Self.retainedRunCount {
                phases.removeValue(forKey: order.removeFirst())
            }
        }
        phases[id] = phase
    }

    func phase(for id: UUID) -> Phase? {
        phases[id]
    }

    func result(for id: UUID) -> HomeAutomationResolverResult? {
        if case .finished(let result) = phases[id] { return result }
        return nil
    }
}
