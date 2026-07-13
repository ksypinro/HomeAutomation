import Foundation
import HomeAutomationCore

public struct AdaptivePortfolioController: Sendable {
    public let rolloutMode: PortfolioRolloutMode
    public let router: StaticPortfolioRouter

    public init(
        rolloutMode: PortfolioRolloutMode,
        router: StaticPortfolioRouter
    ) {
        self.rolloutMode = rolloutMode
        self.router = router
    }

    public func decision(for prepared: PreparedOrchestrationRequest) -> PortfolioDecision? {
        guard rolloutMode.computesDecision else { return nil }
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
}
