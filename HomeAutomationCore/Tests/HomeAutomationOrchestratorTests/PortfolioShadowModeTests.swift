import Foundation
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Portfolio shadow mode")
struct PortfolioShadowModeTests {

    @Test("disabled mode does not compute portfolio decision")
    func disabledModeDoesNotComputeDecision() async throws {
        let coordinator = HomeAutomationCoordinator(
            deviceRegistry: HomeAutomationCoordinator.makeMockDeviceRegistry(),
            foundationModelAvailability: { false }
        )
        let orchestrator = HomeCommandOrchestrator(
            dependencies: coordinator.makeRuntimeDependencies(portfolioRolloutMode: .disabled)
        )

        _ = try await orchestrator.resolve("Turn on the bedroom lamp", executeLowRiskCommands: false)
        let metrics = await orchestrator.lastMetrics()

        #expect(metrics?.portfolioDecision == nil)
    }

    @Test("shadow mode records decision without changing outcome or model calls")
    func shadowModeRecordsDecisionWithoutChangingOutcome() async throws {
        let disabledCoordinator = HomeAutomationCoordinator(
            deviceRegistry: HomeAutomationCoordinator.makeMockDeviceRegistry(),
            foundationModelAvailability: { false }
        )
        let shadowCoordinator = HomeAutomationCoordinator(
            deviceRegistry: HomeAutomationCoordinator.makeMockDeviceRegistry(),
            foundationModelAvailability: { false }
        )
        let disabled = HomeCommandOrchestrator(
            dependencies: disabledCoordinator.makeRuntimeDependencies(portfolioRolloutMode: .disabled)
        )
        let shadow = HomeCommandOrchestrator(
            dependencies: shadowCoordinator.makeRuntimeDependencies(portfolioRolloutMode: .shadowStatic)
        )

        let disabledResult = try await disabled.resolve("Turn on the bedroom lamp", executeLowRiskCommands: false)
        let shadowResult = try await shadow.resolve("Turn on the bedroom lamp", executeLowRiskCommands: false)
        let disabledMetrics = await disabled.lastMetrics()
        let shadowMetrics = await shadow.lastMetrics()

        #expect(disabledResult.resolution.displaySummary == shadowResult.resolution.displaySummary)
        #expect(shadowMetrics?.portfolioDecision != nil)
        #expect(shadowMetrics?.portfolioDecision?.rolloutMode == .shadowStatic)
        #expect(disabledMetrics?.foundationModelUsageSnapshot?.summary.actualCallCount == shadowMetrics?.foundationModelUsageSnapshot?.summary.actualCallCount)
    }
}
