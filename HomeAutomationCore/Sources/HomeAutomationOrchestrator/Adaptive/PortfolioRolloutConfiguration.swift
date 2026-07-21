import Foundation
import HomeAutomationCore

public enum AdaptiveRollbackReason: String, Sendable, Codable, Hashable, CaseIterable {
    case safetyDivergence
    case artifactMismatch
    case elevatedUnsupportedOrClarification
    case schedulerInvariantFailure
    case latencyRegression
    case manualOperatorOverride
}

public struct PortfolioRolloutConfiguration: Sendable, Codable, Hashable {
    public let adaptiveRoutingEnabled: Bool
    public let frontierSchedulingEnabled: Bool
    public let residualBatchingEnabled: Bool
    public let prewarmSessionAffinityEnabled: Bool
    public let allowedArms: [FoundationModelCallArm]
    public let allowedRiskLevels: [HomeAutomationRiskLevel]
    public let canaryPercentage: Double
    public let graphHoldbackPercentage: Double
    public let policyVersion: Int
    public let modelVersion: String?
    public let configVersion: String
    public let rollbackReasons: [AdaptiveRollbackReason]

    public init(
        adaptiveRoutingEnabled: Bool = true,
        frontierSchedulingEnabled: Bool = true,
        residualBatchingEnabled: Bool = true,
        prewarmSessionAffinityEnabled: Bool = true,
        allowedArms: [FoundationModelCallArm] = [.graph, .graphWithTier1, .verifierLoop],
        allowedRiskLevels: [HomeAutomationRiskLevel] = [.low, .medium],
        canaryPercentage: Double = 100,
        graphHoldbackPercentage: Double = 10,
        policyVersion: Int = PortfolioEligibilityPolicy.currentPolicyVersion,
        modelVersion: String? = nil,
        configVersion: String = "local",
        rollbackReasons: [AdaptiveRollbackReason] = []
    ) {
        self.adaptiveRoutingEnabled = adaptiveRoutingEnabled
        self.frontierSchedulingEnabled = frontierSchedulingEnabled
        self.residualBatchingEnabled = residualBatchingEnabled
        self.prewarmSessionAffinityEnabled = prewarmSessionAffinityEnabled
        self.allowedArms = allowedArms
        self.allowedRiskLevels = allowedRiskLevels
        self.canaryPercentage = min(100, max(0, canaryPercentage))
        self.graphHoldbackPercentage = min(100, max(0, graphHoldbackPercentage))
        self.policyVersion = policyVersion
        self.modelVersion = modelVersion
        self.configVersion = configVersion
        self.rollbackReasons = Array(Set(rollbackReasons)).sorted { $0.rawValue < $1.rawValue }
    }

    public var forcesGraphRollback: Bool {
        !adaptiveRoutingEnabled || !rollbackReasons.isEmpty
    }

    public func allows(prepared: PreparedOrchestrationRequest) -> Bool {
        guard !forcesGraphRollback else { return false }
        guard let risk = prepared.featureSnapshot.riskFloor.value else { return false }
        guard allowedRiskLevels.contains(risk) else { return false }
        return canaryDecision(for: prepared).included
    }

    public func allows(arm: FoundationModelCallArm) -> Bool {
        allowedArms.contains(arm)
    }

    public func canaryDecision(for prepared: PreparedOrchestrationRequest) -> PortfolioCanaryDecision {
        let bucket = Self.bucket(for: prepared.request.text)
        let canaryIncluded = Double(bucket) < canaryPercentage
        let holdbackIncluded = Double(bucket) >= (100 - graphHoldbackPercentage)
        return PortfolioCanaryDecision(
            bucket: bucket,
            included: canaryIncluded && !holdbackIncluded,
            graphHoldback: holdbackIncluded,
            canaryPercentage: canaryPercentage,
            graphHoldbackPercentage: graphHoldbackPercentage
        )
    }

    private static func bucket(for value: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(hash % 100)
    }
}

public struct PortfolioCanaryDecision: Sendable, Codable, Hashable {
    public let bucket: Int
    public let included: Bool
    public let graphHoldback: Bool
    public let canaryPercentage: Double
    public let graphHoldbackPercentage: Double

    public init(
        bucket: Int,
        included: Bool,
        graphHoldback: Bool,
        canaryPercentage: Double,
        graphHoldbackPercentage: Double
    ) {
        self.bucket = min(99, max(0, bucket))
        self.included = included
        self.graphHoldback = graphHoldback
        self.canaryPercentage = canaryPercentage
        self.graphHoldbackPercentage = graphHoldbackPercentage
    }
}

public struct PortfolioRolloutEvidence: Sendable, Codable, Hashable {
    public let rolloutMode: PortfolioRolloutMode
    public let selectedArm: FoundationModelCallArm?
    public let executingArm: FoundationModelCallArm
    public let safeFallbackArm: FoundationModelCallArm
    public let fallbackReason: PortfolioArmExecutionFallbackReason
    public let ruleID: String?
    public let eligibleArms: [FoundationModelCallArm]
    public let rejectedArms: [FoundationModelCallArm]
    public let predictedUtility: Double?
    public let observedUtility: Double?
    public let policyVersion: Int
    public let modelVersion: String?
    public let configVersion: String
    public let rollbackReasons: [AdaptiveRollbackReason]
    public let canary: PortfolioCanaryDecision
    public let switches: PortfolioRolloutSwitches

    public init(
        rolloutMode: PortfolioRolloutMode,
        selectedArm: FoundationModelCallArm?,
        executingArm: FoundationModelCallArm,
        safeFallbackArm: FoundationModelCallArm = .graph,
        fallbackReason: PortfolioArmExecutionFallbackReason,
        ruleID: String?,
        eligibleArms: [FoundationModelCallArm],
        rejectedArms: [FoundationModelCallArm],
        predictedUtility: Double?,
        observedUtility: Double? = nil,
        policyVersion: Int,
        modelVersion: String?,
        configVersion: String,
        rollbackReasons: [AdaptiveRollbackReason],
        canary: PortfolioCanaryDecision,
        switches: PortfolioRolloutSwitches
    ) {
        self.rolloutMode = rolloutMode
        self.selectedArm = selectedArm
        self.executingArm = executingArm
        self.safeFallbackArm = safeFallbackArm
        self.fallbackReason = fallbackReason
        self.ruleID = ruleID
        self.eligibleArms = eligibleArms
        self.rejectedArms = rejectedArms
        self.predictedUtility = predictedUtility
        self.observedUtility = observedUtility
        self.policyVersion = policyVersion
        self.modelVersion = modelVersion
        self.configVersion = configVersion
        self.rollbackReasons = rollbackReasons
        self.canary = canary
        self.switches = switches
    }
}

public struct PortfolioRolloutSwitches: Sendable, Codable, Hashable {
    public let adaptiveRouting: Bool
    public let frontierScheduling: Bool
    public let residualBatching: Bool
    public let prewarmSessionAffinity: Bool

    public init(configuration: PortfolioRolloutConfiguration) {
        self.adaptiveRouting = configuration.adaptiveRoutingEnabled
        self.frontierScheduling = configuration.frontierSchedulingEnabled
        self.residualBatching = configuration.residualBatchingEnabled
        self.prewarmSessionAffinity = configuration.prewarmSessionAffinityEnabled
    }
}
