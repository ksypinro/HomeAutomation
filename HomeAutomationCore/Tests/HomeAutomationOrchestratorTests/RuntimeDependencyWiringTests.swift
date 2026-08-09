import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Runtime dependency wiring")
struct RuntimeDependencyWiringTests {

    private func makeCoordinator() -> HomeAutomationCoordinator {
        HomeAutomationCoordinator(
            deviceRegistry: HomeAutomationCoordinator.makeMockDeviceRegistry(),
            foundationModelAvailability: { false }
        )
    }

    @Test("verifierLoop mode wires a loop orchestrator into runtime deps")
    func verifierLoopModeWiresLoopOrchestrator() {
        let deps = makeCoordinator().makeRuntimeDependencies(orchestrationMode: .verifierLoop)

        #expect(deps.orchestrationMode == .verifierLoop)
        #expect(deps.loopOrchestrator != nil)
    }

    @Test("adaptivePortfolio mode wires rollback executors and Tier-1 registry")
    func adaptivePortfolioModeWiresPortfolioDependencies() {
        let deps = makeCoordinator().makeRuntimeDependencies(
            orchestrationMode: .adaptivePortfolio,
            portfolioRolloutMode: .activeStatic
        )

        #expect(deps.orchestrationMode == .adaptivePortfolio)
        #expect(deps.loopOrchestrator != nil)
        #expect(deps.tier1AgentRegistry != nil)
        #expect(deps.portfolioRolloutMode == .activeStatic)
    }

    @Test("runtime dependencies preserve conditional Tier-1 policy opt-in")
    func runtimeDependenciesPreserveConditionalTier1Policy() {
        let defaultDeps = makeCoordinator().makeRuntimeDependencies(
            orchestrationMode: .adaptivePortfolio,
            portfolioRolloutMode: .activeStatic
        )
        let enabledDeps = makeCoordinator().makeRuntimeDependencies(
            orchestrationMode: .adaptivePortfolio,
            portfolioRolloutMode: .activeStatic,
            portfolioEligibilityPolicy: PortfolioEligibilityPolicy(conditionalTier1Enabled: true)
        )

        #expect(!defaultDeps.portfolioEligibilityPolicy.conditionalTier1Enabled)
        #expect(enabledDeps.portfolioEligibilityPolicy.conditionalTier1Enabled)
    }

    @Test("graph mode carries no loop orchestrator")
    func graphModeHasNoLoopOrchestrator() {
        let deps = makeCoordinator().makeRuntimeDependencies(orchestrationMode: .graph)

        #expect(deps.orchestrationMode == .graph)
        #expect(deps.loopOrchestrator == nil)
    }

    @Test("runtime dependencies expose bounded Foundation Model arm")
    func runtimeDependenciesExposeFoundationModelArm() {
        let coordinator = makeCoordinator()
        let graph = coordinator.makeRuntimeDependencies(orchestrationMode: .graph)
        let tier1 = coordinator.makeRuntimeDependencies(orchestrationMode: .graph, useMiniPipeline: true)
        let loop = coordinator.makeRuntimeDependencies(orchestrationMode: .verifierLoop)

        #expect(graph.foundationModelArm == .graph)
        #expect(tier1.foundationModelArm == .graphWithTier1)
        #expect(loop.foundationModelArm == .verifierLoop)
    }

    @Test("detached executor preserves Foundation Model usage ledger scope")
    func detachedExecutorPreservesUsageLedgerScope() async {
        let ledger = FoundationModelUsageLedger(runID: "detached-run")
        let executor = DetachedAgentExecutor()
        let context = HomeAutomationTelemetryContext(runID: "detached-run")

        let inheritedRunID = await FoundationModelUsageLedgerScope.$current.withValue(ledger) {
            await executor.runDetachedValue(telemetryContext: context) {
                FoundationModelUsageLedgerScope.current?.runID
            }
        }

        #expect(inheritedRunID == "detached-run")
    }

    @Test("detached executor preserves Foundation Model admission context")
    func detachedExecutorPreservesAdmissionContextScope() async {
        let executor = DetachedAgentExecutor()
        let telemetry = HomeAutomationTelemetryContext(runID: "detached-run")
        let context = FMAdmissionContext(
            schedulerMode: .shadow,
            runID: "detached-run",
            graphID: "graph",
            nodeID: "node",
            agentID: "agent",
            jobKind: .automationResolution,
            criticalPathRemainingMs: 250,
            estimatedServiceMs: 50,
            deadlineClass: .pipeline,
            cancellationClass: .normal,
            prefixAffinityKey: "agent",
            workflowScopeID: "graph"
        )

        let inherited = await FMAdmissionContextScope.$current.withValue(context) {
            await executor.runDetachedValue(telemetryContext: telemetry) {
                FMAdmissionContextScope.current
            }
        }

        #expect(inherited == context)
    }

    @Test("withMiniPipeline(true) produces a mini-pipeline-backed action resolver")
    func withMiniPipelineEnablesTier1Resolver() {
        let coordinator = makeCoordinator()
        let tier1 = coordinator.automationCoordinator.withMiniPipeline(true)
        let resolver = tier1.makeActionResolver(
            agentRegistry: coordinator.makeAgentRegistry(),
            graphCoordinator: coordinator.graphCoordinator,
            deviceRegistry: coordinator.deviceRegistry
        )

        #expect(resolver.usesMiniPipeline)
    }

    @Test("default automation coordinator keeps the graph-backed action resolver")
    func defaultCoordinatorKeepsGraphResolver() {
        let coordinator = makeCoordinator()
        let resolver = coordinator.automationCoordinator.makeActionResolver(
            agentRegistry: coordinator.makeAgentRegistry(),
            graphCoordinator: coordinator.graphCoordinator,
            deviceRegistry: coordinator.deviceRegistry
        )

        #expect(!resolver.usesMiniPipeline)
    }

    @Test("verifierLoop mode actually runs the loop and records loop metrics")
    func verifierLoopModeRecordsLoopMetrics() async throws {
        let coordinator = makeCoordinator()
        let deps = coordinator.makeRuntimeDependencies(orchestrationMode: .verifierLoop)
        let orchestrator = HomeCommandOrchestrator(dependencies: deps)

        _ = try await orchestrator.resolve("Turn on the light", executeLowRiskCommands: false)
        let metrics = await orchestrator.lastMetrics()

        #expect(metrics?.loop != nil)
        #expect((metrics?.loop?.iterations ?? 0) >= 1)
    }

    @Test("graph mode records no loop metrics")
    func graphModeRecordsNoLoopMetrics() async throws {
        let coordinator = makeCoordinator()
        let deps = coordinator.makeRuntimeDependencies(orchestrationMode: .graph)
        let orchestrator = HomeCommandOrchestrator(dependencies: deps)

        _ = try await orchestrator.resolve("Turn on the light", executeLowRiskCommands: false)
        let metrics = await orchestrator.lastMetrics()

        #expect(metrics?.loop == nil)
    }

    // MARK: - H5: capability repair specialist

    private func makeSpecialists(
        registry: any DeviceRegistryProtocol,
        capabilityWorker: CapabilityResolutionWorker?
    ) -> RepairSpecialistRegistry {
        RepairSpecialistRegistry(
            fragmentNLU: FragmentNLUWorkerSession(foundationModelAvailability: { false }),
            targetResolver: ActionTargetResolver(registry: registry),
            riskAssessor: AutomationRiskAssessor(),
            capabilityWorker: capabilityWorker,
            operationDetection: { _ in nil }
        )
    }

    @Test("capability repair steps resolve through the capability worker")
    func capabilitySpecialistResolvesDispute() async {
        let registry = HomeAutomationCoordinator.makeMockDeviceRegistry()
        let envelope = await DeterministicDraftPipeline(registry: registry)
            .makeCommandEnvelope(text: "turn on the bedroom lamp")
        let specialists = makeSpecialists(
            registry: registry,
            capabilityWorker: CapabilityResolutionWorker(foundationModelAvailability: { false })
        )
        let step = RepairPlanner.RepairStep(
            specialist: .capability,
            fieldIDs: [FieldID(rawValue: "command.capability")],
            disputes: [DraftDispute(fieldID: "command.capability", kind: .wrongValue, evidence: "test")]
        )

        let result = await specialists.execute(step, envelope)

        guard case .capability(let fieldID, _)? = result else {
            Issue.record("Expected .capability repair result, got \(String(describing: result))")
            return
        }
        #expect(fieldID.rawValue == "command.capability")
    }

    @Test("capability repair steps without a worker defer gracefully")
    func capabilitySpecialistWithoutWorkerReturnsNil() async {
        let registry = HomeAutomationCoordinator.makeMockDeviceRegistry()
        let envelope = await DeterministicDraftPipeline(registry: registry)
            .makeCommandEnvelope(text: "turn on the bedroom lamp")
        let specialists = makeSpecialists(registry: registry, capabilityWorker: nil)
        let step = RepairPlanner.RepairStep(
            specialist: .capability,
            fieldIDs: [FieldID(rawValue: "command.capability")],
            disputes: [DraftDispute(fieldID: "command.capability", kind: .wrongValue, evidence: "test")]
        )

        let result = await specialists.execute(step, envelope)

        #expect(result == nil)
    }
}
