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

    @Test("graph mode carries no loop orchestrator")
    func graphModeHasNoLoopOrchestrator() {
        let deps = makeCoordinator().makeRuntimeDependencies(orchestrationMode: .graph)

        #expect(deps.orchestrationMode == .graph)
        #expect(deps.loopOrchestrator == nil)
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
}
