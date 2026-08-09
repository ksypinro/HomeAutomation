import Foundation
import HomeAutomationCore
import HomeAutomationAgents
import os

/// Batches residual conditions (those requiring FM) and handles their resolution.
/// Applies to conditions that failed deterministic assessment.
public struct AutomationConditionResidualBatcher: Sendable {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "ResidualBatcher")

    public init() {}

    /// Classify a condition result as deterministic (complete) or residual (needs FM).
    public func isResidual(
        assessment: AutomationConditionDeterministicAssessment,
        target: some AutomationConditionRoundTripTarget
    ) -> Bool {
        !assessment.isSafeToAccept(for: target)
    }

    /// Batch residual conditions for efficient FM resolution.
    /// Returns grouped inputs with their assessment context.
    public func batchResiduals(
        from inputs: [AutomationConditionClauseResolutionInput],
        assessments: [String: AutomationConditionDeterministicAssessment]
    ) -> [AutomationConditionClauseResolutionInput] {
        inputs.filter { input in
            guard let assessment = assessments[input.component.id] else { return true }
            return assessment.residualReasons.contains { reason in
                reason != .notRoundTripSafe
            }
        }
    }

    /// Filter conditions that are safe to retain without FM (deterministic + round-trip safe).
    public func acceptedConditions(
        from inputs: [AutomationConditionClauseResolutionInput],
        assessments: [String: AutomationConditionDeterministicAssessment],
        target: some AutomationConditionRoundTripTarget
    ) -> [(input: AutomationConditionClauseResolutionInput, assessment: AutomationConditionDeterministicAssessment)] {
        inputs.compactMap { input in
            guard let assessment = assessments[input.component.id],
                  assessment.isSafeToAccept(for: target) else {
                return nil
            }
            return (input, assessment)
        }
    }

    /// Log batching decision for telemetry.
    public func logBatchingDecision(
        totalCount: Int,
        acceptedCount: Int,
        residualCount: Int
    ) {
        logger.info("Condition batching: total=\(totalCount) accepted=\(acceptedCount) residual=\(residualCount)")
    }
}
