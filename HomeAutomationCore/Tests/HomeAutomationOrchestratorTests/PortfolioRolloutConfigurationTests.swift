import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Portfolio rollout configuration")
struct PortfolioRolloutConfigurationTests {

    @Test("learned rollout modes compute decisions and only active learned executes")
    func learnedRolloutModeSemantics() {
        #expect(PortfolioRolloutMode.shadowLearned.computesDecision)
        #expect(PortfolioRolloutMode.shadowLearned.usesLearnedRouter)
        #expect(!PortfolioRolloutMode.shadowLearned.executesSelectedArm)
        #expect(PortfolioRolloutMode.activeLearned.executesSelectedArm)
    }

    @Test("rollback reasons disable adaptive routing")
    func rollbackDisablesRouting() async {
        let prepared = await Self.prepared()
        let config = PortfolioRolloutConfiguration(
            rollbackReasons: [.safetyDivergence]
        )

        #expect(config.forcesGraphRollback)
        #expect(!config.allows(prepared: prepared))
    }

    @Test("learned rollout without artifact returns graph rollback decision")
    func missingLearnedArtifactFallsBackToGraph() async {
        let prepared = await Self.prepared()
        let controller = AdaptivePortfolioController(
            rolloutMode: .activeLearned,
            router: StaticPortfolioRouter(rolloutMode: .activeLearned),
            learnedRouter: nil,
            configuration: PortfolioRolloutConfiguration(canaryPercentage: 100, graphHoldbackPercentage: 0)
        )

        let decision = controller.decision(for: prepared)
        let plan = controller.executionPlan(
            decision: decision,
            defaultArm: .graph,
            hasVerifierLoopExecutor: true,
            hasTier1Registry: true
        )
        let evidence = controller.rolloutEvidence(
            decision: decision,
            executionPlan: plan,
            prepared: prepared
        )

        #expect(decision?.selectedArm == .graph)
        #expect(decision?.ruleID == "phase10.rollback.missingLearnedArtifact")
        #expect(plan.executingArm == .graph)
        #expect(evidence.rolloutMode == .activeLearned)
        #expect(evidence.configVersion == "local")
    }

    private static func prepared() async -> PreparedOrchestrationRequest {
        await OrchestrationFeatureExtractor(registry: MockHomeDeviceRegistry())
            .prepare(.init(
                request: CommandRequest(text: "turn on the bedroom lamp", executeLowRiskCommands: false),
                foundationModelAvailability: .available,
                ragAvailability: .unknown,
                gateDepth: .none,
                warmStateHint: .unknown
            ))
    }
}
