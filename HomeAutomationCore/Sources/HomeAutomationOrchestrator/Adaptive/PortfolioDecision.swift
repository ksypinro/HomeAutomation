import Foundation
import HomeAutomationCore

public enum PortfolioSelectionReason: String, Sendable, Codable, Hashable {
    case directLowRisk
    case simpleScheduleAutomation
    case graphFallback
    case highUncertainty
    case noEligibleArm
}

public enum PortfolioRejectionReason: String, Sendable, Codable, Hashable {
    case modelUnavailable
    case unsupportedOperation
    case missingSpecialistCoverage
    case highRiskPolicy
    case externalMutationRequired
    case memoryUnsupported
    case oodOrUncertain
    case staleRegistrySnapshot
    case finalizerReadinessUnknown
    case nonExecutableTelemetryArm
    case featureMissing
}

public struct PortfolioUtilityComponents: Sendable, Codable, Hashable {
    public let correctnessPrior: Double
    public let latencyPrior: Double
    public let modelCallPrior: Double
    public let escalationRisk: Double
    public let uncertainty: Double
    public let safetyPenalty: Double

    public init(
        correctnessPrior: Double,
        latencyPrior: Double,
        modelCallPrior: Double,
        escalationRisk: Double,
        uncertainty: Double,
        safetyPenalty: Double
    ) {
        self.correctnessPrior = Self.clamp(correctnessPrior)
        self.latencyPrior = Self.clamp(latencyPrior)
        self.modelCallPrior = Self.clamp(modelCallPrior)
        self.escalationRisk = Self.clamp(escalationRisk)
        self.uncertainty = Self.clamp(uncertainty)
        self.safetyPenalty = Self.clamp(safetyPenalty)
    }

    public var total: Double {
        correctnessPrior + latencyPrior + modelCallPrior - escalationRisk - uncertainty - safetyPenalty
    }

    private static func clamp(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

public struct PortfolioArmDecisionRecord: Sendable, Codable, Hashable {
    public let arm: FoundationModelCallArm
    public let isEligible: Bool
    public let rejectionReasons: [PortfolioRejectionReason]
    public let selectionReasons: [PortfolioSelectionReason]
    public let utility: PortfolioUtilityComponents

    public init(
        arm: FoundationModelCallArm,
        isEligible: Bool,
        rejectionReasons: [PortfolioRejectionReason] = [],
        selectionReasons: [PortfolioSelectionReason] = [],
        utility: PortfolioUtilityComponents
    ) {
        self.arm = arm
        self.isEligible = isEligible
        self.rejectionReasons = rejectionReasons
        self.selectionReasons = selectionReasons
        self.utility = utility
    }
}

public struct PortfolioDecision: Sendable, Codable, Hashable {
    public let decisionID: String
    public let policyVersion: Int
    public let rolloutMode: PortfolioRolloutMode
    public let selectedArm: FoundationModelCallArm
    public let safeFallbackArm: FoundationModelCallArm
    public let ruleID: String
    public let explanation: String
    public let eligibleArms: [PortfolioArmDecisionRecord]
    public let rejectedArms: [PortfolioArmDecisionRecord]
    public let uncertainty: Double
    public let featureSchemaVersion: Int
    public let registryVersion: String
    public let registryFreshness: PreparedRegistryFreshness

    public init(
        decisionID: String,
        policyVersion: Int,
        rolloutMode: PortfolioRolloutMode,
        selectedArm: FoundationModelCallArm,
        safeFallbackArm: FoundationModelCallArm = .graph,
        ruleID: String,
        explanation: String,
        eligibleArms: [PortfolioArmDecisionRecord],
        rejectedArms: [PortfolioArmDecisionRecord],
        uncertainty: Double,
        featureSchemaVersion: Int,
        registryVersion: String,
        registryFreshness: PreparedRegistryFreshness
    ) {
        self.decisionID = decisionID
        self.policyVersion = policyVersion
        self.rolloutMode = rolloutMode
        self.selectedArm = selectedArm
        self.safeFallbackArm = safeFallbackArm
        self.ruleID = ruleID
        self.explanation = explanation
        self.eligibleArms = eligibleArms
        self.rejectedArms = rejectedArms
        self.uncertainty = min(1.0, max(0.0, uncertainty))
        self.featureSchemaVersion = featureSchemaVersion
        self.registryVersion = registryVersion
        self.registryFreshness = registryFreshness
    }

    public var eligibleArmLabels: [String] {
        eligibleArms.map(\.arm.rawValue)
    }

    public var rejectedArmLabels: [String] {
        rejectedArms.map(\.arm.rawValue)
    }

    public var selectedArmIsEligible: Bool {
        eligibleArms.contains { $0.arm == selectedArm }
    }
}
