import Foundation
import HomeAutomationCore

public struct LearnedPortfolioRouter: Sendable {
    public let artifact: PortfolioModelArtifact
    public let policy: PortfolioEligibilityPolicy
    public let staticRouter: StaticPortfolioRouter
    public let rolloutMode: PortfolioRolloutMode

    public init(
        artifact: PortfolioModelArtifact,
        policy: PortfolioEligibilityPolicy = PortfolioEligibilityPolicy(),
        staticRouter: StaticPortfolioRouter = StaticPortfolioRouter(),
        rolloutMode: PortfolioRolloutMode = .shadowStatic
    ) {
        self.artifact = artifact
        self.policy = policy
        self.staticRouter = staticRouter
        self.rolloutMode = rolloutMode
    }

    public func decide(_ prepared: PreparedOrchestrationRequest) -> PortfolioDecision {
        let staticDecision = staticRouter.decide(prepared)

        do {
            try artifact.validate(
                featureSchemaVersion: prepared.featureSnapshot.featureSchemaVersion,
                policyVersion: policy.policyVersion
            )
        } catch {
            return fallback(
                staticDecision,
                ruleID: "learned.fallback.schemaOrPolicyMismatch",
                explanation: "learned router fell back to static: artifact schema or policy mismatch"
            )
        }

        if shouldRejectForOOD(prepared.featureSnapshot) {
            return fallback(
                staticDecision,
                ruleID: "learned.fallback.ood",
                explanation: "learned router fell back to static: out-of-domain or low-confidence features"
            )
        }

        if hasMissingRequiredLearnedFeatures(prepared.featureSnapshot) {
            return fallback(
                staticDecision,
                ruleID: "learned.fallback.missingFeatures",
                explanation: "learned router fell back to static: required learned-router features are missing"
            )
        }

        let baseRecords = policy.records(for: prepared)
        let eligible = baseRecords.filter(\.isEligible)
        let rejected = baseRecords.filter { !$0.isEligible }
        guard !eligible.isEmpty else {
            return fallback(
                staticDecision,
                ruleID: "learned.fallback.noEligibleArm",
                explanation: "learned router fell back to static: no eligible arm"
            )
        }

        var scored: [PortfolioArmDecisionRecord] = []
        for record in eligible {
            guard let model = try? artifact.model(for: record.arm) else {
                return fallback(
                    staticDecision,
                    ruleID: "learned.fallback.missingArmModel",
                    explanation: "learned router fell back to static: artifact missing an eligible arm model"
                )
            }
            let utility = utilityComponents(
                score: model.score(prepared.featureSnapshot),
                uncertainty: policy.uncertainty(for: prepared)
            )
            scored.append(PortfolioArmDecisionRecord(
                arm: record.arm,
                isEligible: true,
                rejectionReasons: [],
                utility: utility
            ))
        }

        let ranked = scored.sorted {
            if $0.utility.total == $1.utility.total {
                return armPriority($0.arm) < armPriority($1.arm)
            }
            return $0.utility.total > $1.utility.total
        }
        guard let best = ranked.first else {
            return fallback(
                staticDecision,
                ruleID: "learned.fallback.noScore",
                explanation: "learned router fell back to static: no learned score"
            )
        }
        if let second = ranked.dropFirst().first,
           best.utility.total - second.utility.total < artifact.minimumUtilityMargin {
            return fallback(
                staticDecision,
                ruleID: "learned.fallback.lowMargin",
                explanation: "learned router fell back to static: learned utility margin was too small"
            )
        }

        let finalEligible = ranked.map { record in
            guard record.arm == best.arm else { return record }
            return PortfolioArmDecisionRecord(
                arm: record.arm,
                isEligible: true,
                rejectionReasons: [],
                selectionReasons: [.graphFallback],
                utility: record.utility
            )
        }

        return PortfolioDecision(
            decisionID: decisionID(for: prepared),
            policyVersion: artifact.policyVersion,
            rolloutMode: rolloutMode,
            selectedArm: best.arm,
            safeFallbackArm: .graph,
            ruleID: "learned.utility.bestEligible",
            explanation: "learned router would choose \(best.arm.rawValue): highest calibrated utility among eligible arms",
            eligibleArms: finalEligible,
            rejectedArms: rejected,
            uncertainty: policy.uncertainty(for: prepared),
            featureSchemaVersion: prepared.featureSnapshot.featureSchemaVersion,
            registryVersion: prepared.registryVersion,
            registryFreshness: prepared.registryFreshness(comparedTo: prepared.deviceSnapshot)
        )
    }

    private func fallback(
        _ decision: PortfolioDecision,
        ruleID: String,
        explanation: String
    ) -> PortfolioDecision {
        PortfolioDecision(
            decisionID: decision.decisionID,
            policyVersion: decision.policyVersion,
            rolloutMode: decision.rolloutMode,
            selectedArm: decision.selectedArm,
            safeFallbackArm: decision.safeFallbackArm,
            ruleID: ruleID,
            explanation: explanation,
            eligibleArms: decision.eligibleArms,
            rejectedArms: decision.rejectedArms,
            uncertainty: decision.uncertainty,
            featureSchemaVersion: decision.featureSchemaVersion,
            registryVersion: decision.registryVersion,
            registryFreshness: decision.registryFreshness
        )
    }

    private func shouldRejectForOOD(_ features: PortfolioFeatureSnapshot) -> Bool {
        guard let signal = features.languageOODSignal.value else { return true }
        if signal != .inDomain { return true }
        return (features.operationConfidence.value ?? 0) < 0.55
    }

    private func hasMissingRequiredLearnedFeatures(_ features: PortfolioFeatureSnapshot) -> Bool {
        features.operation.value == nil ||
            features.operationConfidence.value == nil ||
            features.textSizeBucket.value == nil ||
            features.actionCount.value == nil ||
            features.conditionCount.value == nil ||
            features.riskFloor.value == nil ||
            features.memoryReference.value == nil ||
            features.foundationModelAvailability.value == nil
    }

    private func utilityComponents(
        score: Double,
        uncertainty: Double
    ) -> PortfolioUtilityComponents {
        PortfolioUtilityComponents(
            correctnessPrior: min(1, max(0, score)),
            latencyPrior: 0,
            modelCallPrior: 0,
            escalationRisk: 0,
            uncertainty: min(1, max(0, uncertainty)),
            safetyPenalty: 0
        )
    }

    private func decisionID(for prepared: PreparedOrchestrationRequest) -> String {
        [
            "learned",
            artifact.modelVersion,
            artifact.stableFingerprint,
            prepared.featureSnapshot.operation.value?.rawValue ?? "unknown",
            prepared.registryVersion
        ].joined(separator: "-")
    }

    private func armPriority(_ arm: FoundationModelCallArm) -> Int {
        switch arm {
        case .graph: return 0
        case .graphWithTier1: return 1
        case .verifierLoop: return 2
        default: return 99
        }
    }
}
