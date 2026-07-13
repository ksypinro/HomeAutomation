import Foundation
import HomeAutomationCore

public struct AdaptivePortfolioController: Sendable {
    public let rolloutMode: PortfolioRolloutMode
    public let router: StaticPortfolioRouter
    public let learnedRouter: LearnedPortfolioRouter?
    public let configuration: PortfolioRolloutConfiguration

    public init(
        rolloutMode: PortfolioRolloutMode,
        router: StaticPortfolioRouter,
        learnedRouter: LearnedPortfolioRouter? = nil,
        configuration: PortfolioRolloutConfiguration = PortfolioRolloutConfiguration()
    ) {
        self.rolloutMode = rolloutMode
        self.router = router
        self.learnedRouter = learnedRouter
        self.configuration = configuration
    }

    public func decision(for prepared: PreparedOrchestrationRequest) -> PortfolioDecision? {
        guard rolloutMode.computesDecision else { return nil }
        guard configuration.allows(prepared: prepared) else { return nil }
        if rolloutMode.usesLearnedRouter {
            guard let learnedRouter else {
                return graphRollbackDecision(
                    prepared: prepared,
                    ruleID: "phase10.rollback.missingLearnedArtifact",
                    explanation: "learned rollout requested without a model artifact; graph fallback selected"
                )
            }
            return learnedRouter.decide(prepared)
        }
        return router.decide(prepared)
    }

    public func executionPlan(
        decision: PortfolioDecision?,
        defaultArm: FoundationModelCallArm,
        hasVerifierLoopExecutor: Bool,
        hasTier1Registry: Bool
    ) -> PortfolioArmExecutionPlan {
        guard rolloutMode.executesSelectedArm, let decision else {
            return PortfolioArmExecutionPlan(selectedArm: defaultArm, executingArm: defaultArm)
        }

        let eligible = Set(decision.eligibleArms.map(\.arm))
        guard eligible.contains(decision.selectedArm) else {
            return PortfolioArmExecutionPlan(
                selectedArm: decision.selectedArm,
                executingArm: .graph,
                fallbackReason: .selectedArmNotEligible
            )
        }
        guard configuration.allows(arm: decision.selectedArm) else {
            return PortfolioArmExecutionPlan(
                selectedArm: decision.selectedArm,
                executingArm: .graph,
                fallbackReason: .selectedArmNotEligible
            )
        }

        switch decision.selectedArm {
        case .graph:
            return PortfolioArmExecutionPlan(selectedArm: .graph, executingArm: .graph)
        case .graphWithTier1:
            guard hasTier1Registry else {
                return PortfolioArmExecutionPlan(
                    selectedArm: .graphWithTier1,
                    executingArm: .graph,
                    fallbackReason: .missingTier1Registry
                )
            }
            return PortfolioArmExecutionPlan(selectedArm: .graphWithTier1, executingArm: .graphWithTier1)
        case .verifierLoop:
            guard hasVerifierLoopExecutor else {
                return PortfolioArmExecutionPlan(
                    selectedArm: .verifierLoop,
                    executingArm: .graph,
                    fallbackReason: .missingVerifierLoopExecutor
                )
            }
            return PortfolioArmExecutionPlan(selectedArm: .verifierLoop, executingArm: .verifierLoop)
        case .exactTemplate, .evaluation, .unknown:
            return PortfolioArmExecutionPlan(
                selectedArm: decision.selectedArm,
                executingArm: .graph,
                fallbackReason: .nonExecutableArm
            )
        }
    }

    public func rolloutEvidence(
        decision: PortfolioDecision?,
        executionPlan: PortfolioArmExecutionPlan,
        prepared: PreparedOrchestrationRequest
    ) -> PortfolioRolloutEvidence {
        let selectedUtility = decision?.eligibleArms.first { $0.arm == decision?.selectedArm }?.utility.total
        return PortfolioRolloutEvidence(
            rolloutMode: rolloutMode,
            selectedArm: decision?.selectedArm,
            executingArm: executionPlan.executingArm,
            safeFallbackArm: decision?.safeFallbackArm ?? .graph,
            fallbackReason: executionPlan.fallbackReason,
            ruleID: decision?.ruleID,
            eligibleArms: decision?.eligibleArms.map(\.arm) ?? [],
            rejectedArms: decision?.rejectedArms.map(\.arm) ?? [],
            predictedUtility: selectedUtility,
            policyVersion: decision?.policyVersion ?? configuration.policyVersion,
            modelVersion: configuration.modelVersion,
            configVersion: configuration.configVersion,
            rollbackReasons: configuration.rollbackReasons,
            canary: configuration.canaryDecision(for: prepared),
            switches: PortfolioRolloutSwitches(configuration: configuration)
        )
    }

    private func graphRollbackDecision(
        prepared: PreparedOrchestrationRequest,
        ruleID: String,
        explanation: String
    ) -> PortfolioDecision {
        let records = router.policy.records(for: prepared)
        let graphRecord = records.first { $0.arm == .graph && $0.isEligible } ?? PortfolioArmDecisionRecord(
            arm: .graph,
            isEligible: true,
            selectionReasons: [.graphFallback],
            utility: router.policy.utility(for: .graph, prepared: prepared, rejected: false)
        )
        return PortfolioDecision(
            decisionID: ["phase10", ruleID, prepared.registryVersion].joined(separator: "-"),
            policyVersion: configuration.policyVersion,
            rolloutMode: rolloutMode,
            selectedArm: .graph,
            safeFallbackArm: .graph,
            ruleID: ruleID,
            explanation: explanation,
            eligibleArms: [graphRecord],
            rejectedArms: records.filter { $0.arm != .graph },
            uncertainty: router.policy.uncertainty(for: prepared),
            featureSchemaVersion: prepared.featureSnapshot.featureSchemaVersion,
            registryVersion: prepared.registryVersion,
            registryFreshness: prepared.registryFreshness(comparedTo: prepared.deviceSnapshot)
        )
    }
}
