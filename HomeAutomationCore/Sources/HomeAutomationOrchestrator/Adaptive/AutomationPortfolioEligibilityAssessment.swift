import Foundation
import HomeAutomationCore

/// Reason a conditional automation was disqualified from the Graph + Tier-1 cohort.
/// These are consumed for router audit trails and shadow/canary telemetry.
public enum AutomationConditionalTier1RejectionReason: String, Sendable, Codable, Hashable, CaseIterable {
    case featureDisabled
    case notAutomationCreation
    case notScheduleTrigger
    case notExactlyOneConditionLeaf
    case conditionTreeNotSingleLeaf
    case conditionLeafIncomplete
    case actionCountOutOfRange
    case unsupportedFragments
    case memoryReference
    case precedenceAmbiguity
    case lowConfidence
    case oodOrUncertain
    case highRisk
    case staleRegistry
    case externalMutation
}

/// Centralized eligibility result for the Phase 3 conditional Tier-1 cohort.
///
/// The assessment is reason-coded so a rejected request records *why* it stayed on Graph,
/// and an eligible request can be routed to Graph + Tier-1 by a single, distinct router rule.
public struct AutomationPortfolioEligibilityAssessment: Sendable, Hashable {
    public let isEligible: Bool
    public let rejectionReasons: [AutomationConditionalTier1RejectionReason]

    public init(
        isEligible: Bool,
        rejectionReasons: [AutomationConditionalTier1RejectionReason]
    ) {
        self.isEligible = isEligible
        self.rejectionReasons = rejectionReasons
    }

    public static let eligible = AutomationPortfolioEligibilityAssessment(
        isEligible: true,
        rejectionReasons: []
    )
}
