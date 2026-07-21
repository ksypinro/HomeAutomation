import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Adaptive portfolio integration")
struct AdaptivePortfolioIntegrationTests {

    @Test("active static fallback executes graph when models are unavailable")
    func activeStaticExecutesGraphFallbackWhenModelsUnavailable() async throws {
        let coordinator = HomeAutomationCoordinator(
            deviceRegistry: HomeAutomationCoordinator.makeMockDeviceRegistry(),
            foundationModelAvailability: { false }
        )
        let orchestrator = HomeCommandOrchestrator(
            dependencies: coordinator.makeRuntimeDependencies(
                orchestrationMode: .adaptivePortfolio,
                portfolioRolloutMode: .activeStatic
            )
        )

        _ = try await orchestrator.resolve("Turn on the bedroom lamp", executeLowRiskCommands: false)
        let metrics = await orchestrator.lastMetrics()

        #expect(metrics?.portfolioDecision?.rolloutMode == .activeStatic)
        #expect(metrics?.portfolioExecutionPlan?.executingArm == .graph)
        #expect(metrics?.portfolioExecutionPlan?.fallbackReason == PortfolioArmExecutionFallbackReason.none)
        #expect(metrics?.foundationModelUsageSnapshot?.runID != nil)
        #expect(metrics?.loop == nil)
    }

    @Test("active static stream emits one input and one outcome event")
    func activeStaticStreamEmitsOneInputAndOutcome() async throws {
        let coordinator = HomeAutomationCoordinator(
            deviceRegistry: HomeAutomationCoordinator.makeMockDeviceRegistry(),
            foundationModelAvailability: { false }
        )
        let orchestrator = HomeCommandOrchestrator(
            dependencies: coordinator.makeRuntimeDependencies(
                orchestrationMode: .adaptivePortfolio,
                portfolioRolloutMode: .activeStatic
            )
        )

        var inputEvents = 0
        var outcomeEvents = 0
        for try await update in orchestrator.resolveStream("Turn on the bedroom lamp", executeLowRiskCommands: false) {
            if case .event(let event) = update {
                if event.stage == "input" { inputEvents += 1 }
                if event.stage == "outcome" { outcomeEvents += 1 }
            }
        }
        let metrics = await orchestrator.lastMetrics()
        let encoded = try JSONEncoder().encode(metrics)

        #expect(inputEvents == 1)
        #expect(outcomeEvents == 1)
        #expect(metrics?.portfolioExecutionPlan?.executingArm == .graph)
        #expect(!encoded.isEmpty)
    }

    @Test("controller selects verifier loop for eligible direct command")
    func controllerSelectsVerifierLoopForEligibleDirectCommand() async {
        let prepared = await preparedRequest(
            text: "turn on the bedroom lamp",
            foundationModelAvailability: .available
        )
        let controller = AdaptivePortfolioController(
            rolloutMode: .activeStatic,
            router: StaticPortfolioRouter(rolloutMode: .activeStatic)
        )

        let decision = controller.decision(for: prepared)
        let plan = controller.executionPlan(
            decision: decision,
            defaultArm: .graph,
            hasVerifierLoopExecutor: true,
            hasTier1Registry: true
        )

        #expect(decision?.selectedArm == .verifierLoop)
        #expect(plan.selectedArm == .verifierLoop)
        #expect(plan.executingArm == .verifierLoop)
        #expect(plan.fallbackReason == .none)
    }

    @Test("controller selects Tier-1 for eligible simple schedule")
    func controllerSelectsTier1ForEligibleSimpleSchedule() async {
        let prepared = await preparedRequest(
            text: "turn on the bedroom lamp every day at 7 PM",
            foundationModelAvailability: .available
        )
        let controller = AdaptivePortfolioController(
            rolloutMode: .activeStatic,
            router: StaticPortfolioRouter(rolloutMode: .activeStatic)
        )

        let decision = controller.decision(for: prepared)
        let plan = controller.executionPlan(
            decision: decision,
            defaultArm: .graph,
            hasVerifierLoopExecutor: true,
            hasTier1Registry: true
        )

        #expect(decision?.selectedArm == .graphWithTier1)
        #expect(plan.selectedArm == .graphWithTier1)
        #expect(plan.executingArm == .graphWithTier1)
        #expect(plan.fallbackReason == .none)
    }

    @Test("controller falls back when selected executor is missing")
    func controllerFallsBackWhenExecutorMissing() async {
        let prepared = await preparedRequest(
            text: "turn on the bedroom lamp",
            foundationModelAvailability: .available
        )
        let controller = AdaptivePortfolioController(
            rolloutMode: .activeStatic,
            router: StaticPortfolioRouter(rolloutMode: .activeStatic)
        )

        let decision = controller.decision(for: prepared)
        let plan = controller.executionPlan(
            decision: decision,
            defaultArm: .graph,
            hasVerifierLoopExecutor: false,
            hasTier1Registry: true
        )

        #expect(decision?.selectedArm == .verifierLoop)
        #expect(plan.executingArm == .graph)
        #expect(plan.fallbackReason == .missingVerifierLoopExecutor)
    }

    @Test("active static high-risk request falls back to graph")
    func activeStaticHighRiskFallsBackToGraph() async {
        let prepared = await preparedRequest(
            text: "unlock the front door",
            foundationModelAvailability: .available
        )
        let controller = AdaptivePortfolioController(
            rolloutMode: .activeStatic,
            router: StaticPortfolioRouter(rolloutMode: .activeStatic)
        )

        let decision = controller.decision(for: prepared)
        let plan = controller.executionPlan(
            decision: decision,
            defaultArm: .graph,
            hasVerifierLoopExecutor: true,
            hasTier1Registry: true
        )

        #expect(decision == nil)
        #expect(plan.executingArm == .graph)
    }

    @Test("active static direct command retains finalization receipt")
    func activeStaticDirectCommandHasFinalizationReceipt() async throws {
        let coordinator = HomeAutomationCoordinator(
            deviceRegistry: HomeAutomationCoordinator.makeMockDeviceRegistry(),
            foundationModelAvailability: { false }
        )
        let orchestrator = HomeCommandOrchestrator(
            dependencies: coordinator.makeRuntimeDependencies(
                orchestrationMode: .adaptivePortfolio,
                portfolioRolloutMode: .activeStatic
            )
        )

        _ = try await orchestrator.resolve("Turn on the bedroom lamp", executeLowRiskCommands: false)
        let metrics = await orchestrator.lastMetrics()

        #expect(metrics?.portfolioExecutionPlan?.executingArm == .graph)
        #expect(metrics?.safetyMetrics.finalizationReceipt != nil)
    }

    private func preparedRequest(
        text: String,
        foundationModelAvailability: PortfolioFeatureAvailability
    ) async -> PreparedOrchestrationRequest {
        let extractor = OrchestrationFeatureExtractor(
            registry: HomeAutomationCoordinator.makeMockDeviceRegistry()
        )
        return await extractor.prepare(.init(
            request: CommandRequest(text: text, executeLowRiskCommands: false),
            foundationModelAvailability: foundationModelAvailability,
            ragAvailability: .unknown,
            gateDepth: .none,
            warmStateHint: .unknown
        ))
    }
}
