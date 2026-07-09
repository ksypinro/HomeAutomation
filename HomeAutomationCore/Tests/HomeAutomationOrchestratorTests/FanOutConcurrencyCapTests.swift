import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Fan-Out Concurrency Cap")
struct FanOutConcurrencyCapTests {

    @Test("defaultMaxConcurrentComponents is bounded and reasonable")
    func defaultCapIsBounded() {
        let cap = AutomationComponentFanOutRunner.defaultMaxConcurrentComponents
        #expect(cap >= 2)
        #expect(cap <= 16)
    }

    @Test("Multi-action automation resolves correctly under the cap")
    func multiActionResolvesUnderCap() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Every day at 7 PM turn on the bedroom lamp, turn off the bedroom AC, and close the living room blinds",
            executeLowRiskCommands: false
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.resolvedActions.count >= 2)
    }

    @Test("Single-action automation still resolves with cap = 1")
    func singleActionResolvesWithMinCap() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on the bedroom lamp every day at 7 PM",
            executeLowRiskCommands: false
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.resolvedActions.count == 1)
    }
}
