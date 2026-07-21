import Foundation
import HomeAutomationCore
import os

/// Telemetry cleanup and optimization for condition batch resolution.
/// Removes redundant telemetry, tracks session reuse, and records deterministic candidates.
public struct ConditionTelemetryCleanup: Sendable {
    private let logger = Logger(subsystem: "HomeAutomation", category: "ConditionTelemetry")

    public init() {}

    /// Filter tool-selection telemetry to remove unattached tools.
    /// Only report tools that were actually used in the FM call output.
    public func cleanToolSelectionTelemetry(
        selectedTools: [String],
        usedTools: [String]
    ) -> [String] {
        let used = Set(usedTools)
        let attached = selectedTools.filter { used.contains($0) }
        if attached.count < selectedTools.count {
            logger.debug("Tool selection cleanup: removed \(selectedTools.count - attached.count) unattached tool(s)")
        }
        return attached
    }

    /// Record deterministic candidate retention.
    /// For batch resolution, we retain the deterministic candidate from Phase 1
    /// to use as a fallback if FM fails, avoiding re-evaluation.
    public func recordDeterministicCandidateRetention(
        conditionID: String,
        candidate: HomeAutomationCondition?
    ) {
        guard let candidate = candidate else {
            logger.debug("Deterministic candidate: none for \(conditionID)")
            return
        }
        logger.debug("Deterministic candidate retained for \(conditionID): \(String(describing: candidate))")
    }

    /// Record session reuse event for telemetry.
    public func recordSessionReuseEvent(
        batchSize: Int,
        wasReused: Bool,
        reuseStrategy: ConditionBatchSessionContext.SessionReuseStrategy,
        durationMs: Double
    ) {
        let strategyName = reuseStrategy.rawValue
        let reuseLabel = wasReused ? "reused" : "fresh"
        logger.info("Session reuse: \(reuseLabel) session (\(strategyName)) for batch of \(batchSize) residuals, duration=\(String(format: "%.0f", durationMs))ms")
    }

    /// Record prompt budget compliance.
    public func recordPromptBudgetCompliance(
        totalCharacters: Int,
        budgetCharacters: Int,
        complies: Bool
    ) {
        if complies {
            let utilization = Double(totalCharacters) / Double(budgetCharacters) * 100
            logger.debug("Prompt budget: \(totalCharacters)/\(budgetCharacters) chars (\(String(format: "%.0f", utilization))% utilization)")
        } else {
            logger.warning("Prompt budget exceeded: \(totalCharacters)/\(budgetCharacters) chars")
        }
    }

    /// Record ambiguity alternative closure.
    /// When a condition is accepted deterministically, we don't need to track
    /// alternative interpretations (ambiguous candidates).
    public func recordAmbiguityAlternativeClosure(
        conditionID: String,
        wasAcceptedDeterministically: Bool
    ) {
        if wasAcceptedDeterministically {
            logger.debug("Ambiguity alternatives closed: deterministic acceptance for \(conditionID)")
        }
    }
}
