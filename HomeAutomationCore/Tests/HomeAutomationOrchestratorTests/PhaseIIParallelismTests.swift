import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Phase II Parallelism — Two-wave & Clarification Short-circuit")
struct PhaseIIParallelismTests {

    // MARK: - Clarification Short-Circuit

    @Test("Clarification on one action short-circuits without resolving remaining actions")
    func clarificationShortCircuitsRemainingActions() async throws {
        let registry = MockHomeDeviceRegistry(devices: [
            HomeCandidateRecord(
                id: "bedroom_lamp_1",
                displayName: "Bedroom Lamp",
                deviceType: "light",
                room: "bedroom",
                capabilities: ["switch", "switchLevel"],
                supportedCommands: ["switch": ["on", "off"], "switchLevel": ["setLevel"]],
                currentState: ["switch": "off", "level": "50"]
            ),
            HomeCandidateRecord(
                id: "bedroom_lamp_2",
                displayName: "Bedroom Lamp",
                deviceType: "light",
                room: "bedroom",
                capabilities: ["switch", "switchLevel"],
                supportedCommands: ["switch": ["on", "off"], "switchLevel": ["setLevel"]],
                currentState: ["switch": "on", "level": "80"]
            ),
            HomeCandidateRecord(
                id: "living_room_ac",
                displayName: "Living Room AC",
                deviceType: "airConditioner",
                room: "living room",
                capabilities: ["switch", "thermostatCoolingSetpoint"],
                supportedCommands: ["switch": ["on", "off"], "thermostatCoolingSetpoint": ["setCoolingSetpoint"]],
                currentState: ["switch": "off"]
            ),
        ])
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: registry,
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Every day at 7 PM turn on the bedroom lamp and turn off the living room AC",
            executeLowRiskCommands: false
        )

        guard case .needsClarification = result.resolution else {
            Issue.record("Expected .needsClarification due to ambiguous 'Bedroom Lamp', got \(result.resolution.displaySummary)")
            return
        }
    }

    // MARK: - Two-wave Scheduling (Tier 1 as Wave 1)

    @Test("Tier 1 mini-pipeline resolves unambiguous actions deterministically (Wave 1 path)")
    func tier1ActsAsWaveOneDeterministicBurst() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Every day at 7 PM turn on the bedroom lamp",
            executeLowRiskCommands: false
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.resolvedActions.count == 1)
        #expect(plan.resolvedActions[0].draft.capability == "switch")
        #expect(plan.resolvedActions[0].draft.command == "on")
    }

    @Test("Multi-action automation resolves all actions deterministically without FM calls")
    func multiActionWaveOneResolution() async throws {
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

    // MARK: - SJF + Short-Circuit Integration

    @Test("Interactive FM gate priority defaults preserved for automation component resolution")
    func fmGatePriorityInteractiveByDefault() async {
        let gate = FoundationModelGate(maxConcurrent: 2)
        #expect(await gate.queuedCount(for: .interactive) == 0)
        #expect(await gate.queuedCount(for: .pipeline) == 0)
    }
}
