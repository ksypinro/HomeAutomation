import Foundation
import HomeAutomationCore

public struct PortfolioEligibilityPolicy: Sendable {
    public static let currentPolicyVersion = 1

    public let policyVersion: Int
    public let candidateArms: [FoundationModelCallArm]

    public init(
        policyVersion: Int = Self.currentPolicyVersion,
        candidateArms: [FoundationModelCallArm] = [.graph, .graphWithTier1, .verifierLoop]
    ) {
        self.policyVersion = policyVersion
        self.candidateArms = candidateArms
    }

    public func records(for prepared: PreparedOrchestrationRequest) -> [PortfolioArmDecisionRecord] {
        candidateArms.map { arm in
            let reasons = rejectionReasons(for: arm, prepared: prepared)
            return PortfolioArmDecisionRecord(
                arm: arm,
                isEligible: reasons.isEmpty,
                rejectionReasons: reasons,
                utility: utility(for: arm, prepared: prepared, rejected: !reasons.isEmpty)
            )
        }
    }

    public func rejectionReasons(
        for arm: FoundationModelCallArm,
        prepared: PreparedOrchestrationRequest
    ) -> [PortfolioRejectionReason] {
        guard [.graph, .graphWithTier1, .verifierLoop].contains(arm) else {
            return [.nonExecutableTelemetryArm]
        }

        let features = prepared.featureSnapshot
        var reasons: [PortfolioRejectionReason] = []

        if missingRequiredFeature(features, for: arm) {
            reasons.append(.featureMissing)
        }

        if arm != .graph, isUnsupportedOperation(features) {
            reasons.append(.unsupportedOperation)
        }

        if arm != .graph, isModelUnavailable(features) {
            reasons.append(.modelUnavailable)
        }

        if arm != .graph, isHighRisk(features) {
            reasons.append(.highRiskPolicy)
        }

        if arm != .graph, prepared.request.automationCreationMode == "create" {
            reasons.append(.externalMutationRequired)
        }

        if arm != .graph, features.memoryReference.value == true {
            reasons.append(.memoryUnsupported)
        }

        if arm != .graph, isOODOrUncertain(features) {
            reasons.append(.oodOrUncertain)
        }

        if arm != .graph, prepared.registryFreshness(comparedTo: prepared.deviceSnapshot) != .fresh {
            reasons.append(.staleRegistrySnapshot)
        }

        switch arm {
        case .graph:
            break

        case .graphWithTier1:
            if features.operation.value != .automationCreation {
                reasons.append(.unsupportedOperation)
            }
            if !isSimpleConfidentAutomation(prepared) {
                reasons.append(.missingSpecialistCoverage)
            }

        case .verifierLoop:
            if features.operation.value != .executeDeviceCommand {
                reasons.append(.unsupportedOperation)
            }
            if !isStrongLowRiskDirectCommand(features) {
                reasons.append(.missingSpecialistCoverage)
            }

        default:
            reasons.append(.nonExecutableTelemetryArm)
        }

        return Array(Set(reasons)).sorted { $0.rawValue < $1.rawValue }
    }

    public func uncertainty(for prepared: PreparedOrchestrationRequest) -> Double {
        let features = prepared.featureSnapshot
        var uncertainty = 0.0
        uncertainty = max(uncertainty, 1.0 - (features.operationConfidence.value ?? 0.0))
        uncertainty = max(uncertainty, 1.0 - (features.minimumFieldConfidence.value ?? 0.0))
        if features.languageOODSignal.value != .inDomain { uncertainty = max(uncertainty, 0.85) }
        if features.precedenceAmbiguity.value == true { uncertainty = max(uncertainty, 0.70) }
        if features.operation.value == nil || features.riskFloor.value == nil { uncertainty = 1.0 }
        return min(1.0, max(0.0, uncertainty))
    }

    public func isStrongLowRiskDirectCommand(_ features: PortfolioFeatureSnapshot) -> Bool {
        features.operation.value == .executeDeviceCommand &&
            (features.operationConfidence.value ?? 0.0) >= 0.80 &&
            (features.minimumFieldConfidence.value ?? 0.0) >= 0.70 &&
            (features.actionCount.value ?? 0) == 1 &&
            (features.conditionCount.value ?? 0) == 0 &&
            features.riskFloor.value == .low &&
            features.memoryReference.value != true &&
            features.exactTemplateMatch.value == true
    }

    public func isSimpleConfidentAutomation(_ prepared: PreparedOrchestrationRequest) -> Bool {
        let features = prepared.featureSnapshot
        let triggerIsSchedule = prepared.deterministicEnvelope.automation?.trigger?.type == .schedule
        return features.operation.value == .automationCreation &&
            triggerIsSchedule &&
            (features.operationConfidence.value ?? 0.0) >= 0.80 &&
            (features.minimumFieldConfidence.value ?? 0.0) >= 0.50 &&
            (features.actionCount.value ?? 0) >= 1 &&
            (features.actionCount.value ?? 0) <= 3 &&
            (features.conditionCount.value ?? 0) == 0 &&
            (features.unsupportedFragmentCount.value ?? 0) == 0 &&
            features.precedenceAmbiguity.value != true &&
            features.memoryReference.value != true &&
            (features.riskFloor.value == .low || features.riskFloor.value == .medium)
    }

    public func isOODOrUncertain(_ features: PortfolioFeatureSnapshot) -> Bool {
        guard let signal = features.languageOODSignal.value else { return true }
        if signal != .inDomain { return true }
        return (features.operationConfidence.value ?? 0.0) < 0.55
    }

    public func isHighRisk(_ features: PortfolioFeatureSnapshot) -> Bool {
        features.riskFloor.value == .high || features.riskFloor.value == .critical
    }

    public func isUnsupportedOperation(_ features: PortfolioFeatureSnapshot) -> Bool {
        features.operation.value == .unsupported
    }

    public func isModelUnavailable(_ features: PortfolioFeatureSnapshot) -> Bool {
        features.foundationModelAvailability.value == .unavailable
    }

    public func missingRequiredFeature(
        _ features: PortfolioFeatureSnapshot,
        for arm: FoundationModelCallArm
    ) -> Bool {
        if features.operation.value == nil ||
            features.operationConfidence.value == nil ||
            features.languageOODSignal.value == nil ||
            features.riskFloor.value == nil {
            return true
        }

        switch arm {
        case .graphWithTier1, .verifierLoop:
            return features.minimumFieldConfidence.value == nil ||
                features.actionCount.value == nil ||
                features.conditionCount.value == nil ||
                features.memoryReference.value == nil
        default:
            return false
        }
    }

    public func utility(
        for arm: FoundationModelCallArm,
        prepared: PreparedOrchestrationRequest,
        rejected: Bool
    ) -> PortfolioUtilityComponents {
        let features = prepared.featureSnapshot
        let uncertaintyValue = uncertainty(for: prepared)
        let safetyPenalty = rejected ? 1.0 : (isHighRisk(features) ? 0.8 : 0.0)

        switch arm {
        case .verifierLoop:
            return PortfolioUtilityComponents(
                correctnessPrior: isStrongLowRiskDirectCommand(features) ? 0.82 : 0.55,
                latencyPrior: 0.74,
                modelCallPrior: 0.66,
                escalationRisk: features.memoryReference.value == true ? 0.60 : 0.25,
                uncertainty: uncertaintyValue,
                safetyPenalty: safetyPenalty
            )
        case .graphWithTier1:
            return PortfolioUtilityComponents(
                correctnessPrior: isSimpleConfidentAutomation(prepared) ? 0.82 : 0.58,
                latencyPrior: 0.72,
                modelCallPrior: 0.72,
                escalationRisk: (features.conditionCount.value ?? 0) > 0 ? 0.45 : 0.20,
                uncertainty: uncertaintyValue,
                safetyPenalty: safetyPenalty
            )
        case .graph:
            return PortfolioUtilityComponents(
                correctnessPrior: 0.78,
                latencyPrior: 0.42,
                modelCallPrior: 0.35,
                escalationRisk: 0.12,
                uncertainty: min(0.40, uncertaintyValue),
                safetyPenalty: 0.0
            )
        default:
            return PortfolioUtilityComponents(
                correctnessPrior: 0,
                latencyPrior: 0,
                modelCallPrior: 0,
                escalationRisk: 1,
                uncertainty: 1,
                safetyPenalty: 1
            )
        }
    }
}
