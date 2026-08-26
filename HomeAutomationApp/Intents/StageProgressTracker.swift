import Foundation
import HomeAutomationAgents

/// What to write into the intent's `progress` at one moment.
///
/// The fields map onto exactly what Live Activities reads: `title` becomes
/// `Progress.localizedDescription`, `subtitle` becomes
/// `localizedAdditionalDescription`, and the two counts drive the bar.
struct ProgressReport: Sendable, Equatable {
    var completedUnitCount: Int64
    var totalUnitCount: Int64
    var title: String
    var subtitle: String

    var fraction: Double {
        totalUnitCount > 0 ? Double(completedUnitCount) / Double(totalUnitCount) : 0
    }
}

/// Turns the orchestrator's pipeline events into `ProgressReport`s.
///
/// This deliberately holds **no reference to `Progress`**. `ProgressReportingIntent.progress`
/// is a getter-only computed property on a protocol extension, backed by the
/// `NSProgress` the system passes into its perform call — not by storage on the
/// intent. Outside an execution context it returns a fresh throwaway object on
/// every access. Capturing it once would therefore be relying on undocumented
/// behaviour, so the intent reads `progress` at each update site instead and
/// this type stays a pure state machine (which also makes it testable).
///
/// **Granularity.** A work unit is not a stage. One graph node can host several
/// agents, the automation path fans out per action and per condition clause, and
/// the verifier loop re-invokes the same agent up to three times with repairs.
/// Units are keyed on every identity the event carries, so a new agent starting
/// is a new unit and the same agent moving `running → completed` is a state
/// change on an existing one. Both move the bar.
///
/// **Liveness.** `performBackgroundTask`'s documentation is explicit: if you do
/// not update `progress` regularly, the system can cancel the runtime extension
/// and end the task early. Events alone are not enough — a single agent can hold
/// for 60 seconds emitting nothing — so `heartbeat()` fills those gaps.
@MainActor
final class StageProgressTracker {
    /// Fine-grained so single-unit and heartbeat increments are both visible.
    private static let totalUnits: Int64 = 1000
    /// The last 5% belongs to the result actually arriving.
    private static let ceilingBeforeFinish: Int64 = 950

    /// Work units are discovered lazily, so a naive finished ÷ discovered ratio
    /// reads 100% the moment the first unit completes — there is nothing else
    /// discovered yet to weigh it against. The denominator therefore never drops
    /// below a nominal run size, and always reserves headroom for work not yet
    /// seen. Both only shape the curve; `finish()` is what reaches 100%.
    private static let nominalRunUnits = 14.0
    private static let undiscoveredAllowance = 1.25

    private let startedAt = Date()

    /// Latest status per work unit. Insertion order is kept separately so the
    /// denominator counts distinct units, including ones still pending.
    private var unitStatus: [String: OrchestratorPipelineEvent.EventStatus] = [:]
    private var unitOrder: [String] = []

    /// The value justified purely by completed-vs-discovered work. Heartbeats
    /// may run slightly ahead of this, never behind.
    private var honestValue: Int64 = 0
    private var reportedValue: Int64 = 0
    private var title = "Starting"

    init() {}

    /// The current state, without advancing anything.
    var report: ProgressReport {
        ProgressReport(
            completedUnitCount: reportedValue,
            totalUnitCount: Self.totalUnits,
            title: title,
            subtitle: subtitleText()
        )
    }

    // MARK: - Advancing

    /// Records one pipeline event: a new unit of work, or a state change on one
    /// already seen. Either way the bar moves and the title follows the agent.
    func observe(_ event: OrchestratorPipelineEvent) -> ProgressReport {
        let key = Self.workUnitKey(for: event)
        if unitStatus[key] == nil {
            unitOrder.append(key)
        }
        unitStatus[key] = event.status

        recomputeHonestValue()

        // Guarantee forward motion on every event. A burst of `.running` events
        // adds units to the denominator without adding completions, which would
        // otherwise leave the bar flat.
        let candidate = max(honestValue, reportedValue + 1)
        reportedValue = min(candidate, Self.ceilingBeforeFinish)
        title = Self.title(for: event)

        return report
    }

    /// Signals liveness while the pipeline is silent. Bounded to half a unit
    /// past the honest value so a long stage looks alive without the bar
    /// claiming work that hasn't happened.
    func heartbeat() -> ProgressReport {
        let unitSpan = Int64(Double(Self.ceilingBeforeFinish) / denominator)
        let ceiling = min(honestValue + max(unitSpan / 2, 1), Self.ceilingBeforeFinish)
        if reportedValue < ceiling {
            reportedValue += 1
        }
        // The report is returned regardless — the elapsed time in the subtitle
        // changes even when the count is capped, so the Progress object still
        // gets written to and the task still looks tended.
        return report
    }

    func finish() -> ProgressReport {
        reportedValue = Self.totalUnits
        honestValue = Self.totalUnits
        title = "Finishing up"
        return ProgressReport(
            completedUnitCount: Self.totalUnits,
            totalUnitCount: Self.totalUnits,
            title: title,
            subtitle: "Done"
        )
    }

    // MARK: - Internals

    /// Discovered units, padded for work not yet seen and floored at a nominal
    /// run size so early completions don't read as "almost done".
    private var denominator: Double {
        max(Double(unitOrder.count) * Self.undiscoveredAllowance, Self.nominalRunUnits)
    }

    private var finishedUnits: Int {
        unitStatus.values.count { $0.isTerminal }
    }

    private func recomputeHonestValue() {
        let ratio = min(Double(finishedUnits) / denominator, 1.0)
        honestValue = Int64((ratio * Double(Self.ceilingBeforeFinish)).rounded())
    }

    /// "4 of 11 steps · 18s" — more use to a watcher than a raw percentage,
    /// and it keeps changing even while the count is capped.
    private func subtitleText() -> String {
        let elapsed = Int(Date().timeIntervalSince(startedAt).rounded())
        let time = elapsed < 60 ? "\(elapsed)s" : "\(elapsed / 60)m \(elapsed % 60)s"
        guard !unitOrder.isEmpty else { return time }
        return "\(finishedUnits) of \(unitOrder.count) steps · \(time)"
    }

    /// Every identity the event carries. Two agents inside one graph node, two
    /// actions inside one automation, and two verifier-loop invocations of the
    /// same agent are all distinct work.
    private static func workUnitKey(for event: OrchestratorPipelineEvent) -> String {
        [
            event.stage,
            event.agentID ?? "-",
            event.graphNodeID ?? "-",
            event.componentID ?? "-",
            event.actionID ?? "-",
            event.conditionID ?? "-",
            event.agentInvocationID ?? "-",
            event.agentRunID.map(String.init) ?? "-"
        ].joined(separator: "|")
    }

    /// Prefer the agent — that is the thing a watcher sees change.
    private static func title(for event: OrchestratorPipelineEvent) -> String {
        if let agentID = event.agentID, !agentID.isEmpty {
            return stageLabel(agentID)
        }
        return stageLabel(event.stage)
    }

    /// Pipeline identifiers are internal, e.g. `draft-generation`.
    static func stageLabel(_ raw: String) -> String {
        let spaced = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
        let words = spaced.split(whereSeparator: { $0.isWhitespace }).map { $0.lowercased() }
        guard let first = words.first else { return "Working" }
        return ([first.capitalized] + words.dropFirst()).joined(separator: " ")
    }
}

private extension OrchestratorPipelineEvent.EventStatus {
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .skipped: return true
        case .pending, .running: return false
        }
    }
}
