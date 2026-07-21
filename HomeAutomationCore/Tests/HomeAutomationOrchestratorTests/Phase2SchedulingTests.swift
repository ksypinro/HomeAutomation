import Foundation
import Testing
@testable import HomeAutomationAgents
@testable import HomeAutomationOrchestrator
import HomeAutomationCore

@Suite("Phase 2 — Fan-out scheduling caps and prompt budget")
struct Phase2SchedulingTests {

    // MARK: - Per-kind action concurrency cap (pure scheduling policy)

    @Test("Non-action items stay eligible while actions are capped")
    func actionCapSkipsActionsButAllowsConditions() {
        // pending order: [condition, action, action, action]
        let pending = [false, true, true, true]
        // 2 actions already running, action cap = 2, overall cap = 6, 3 running total
        let index = AutomationComponentFanOutRunner.nextEligibleIndex(
            pendingIsAction: pending,
            runningActions: 2,
            runningTotal: 3,
            maxConcurrentActions: 2,
            maxConcurrentComponents: 6
        )
        // Actions are capped, but the condition at index 0 is still eligible.
        #expect(index == 0)
    }

    @Test("No action starts once the action cap is reached")
    func actionCapBlocksFurtherActions() {
        let pending = [true, true] // only actions remain
        let index = AutomationComponentFanOutRunner.nextEligibleIndex(
            pendingIsAction: pending,
            runningActions: 2,
            runningTotal: 2,
            maxConcurrentActions: 2,
            maxConcurrentComponents: 6
        )
        #expect(index == nil)
    }

    @Test("Front-of-queue order is preserved (conditions before actions)")
    func prefersFrontOfQueue() {
        let pending = [false, false, true] // trigger/condition first, action last
        let index = AutomationComponentFanOutRunner.nextEligibleIndex(
            pendingIsAction: pending,
            runningActions: 0,
            runningTotal: 0,
            maxConcurrentActions: 2,
            maxConcurrentComponents: 6
        )
        #expect(index == 0)
    }

    @Test("Overall component cap blocks all scheduling")
    func overallCapBlocksEverything() {
        let pending = [false, true]
        let index = AutomationComponentFanOutRunner.nextEligibleIndex(
            pendingIsAction: pending,
            runningActions: 0,
            runningTotal: 6,
            maxConcurrentActions: 2,
            maxConcurrentComponents: 6
        )
        #expect(index == nil)
    }

    @Test("An action is eligible when below the action cap")
    func actionEligibleBelowCap() {
        let pending = [true, true]
        let index = AutomationComponentFanOutRunner.nextEligibleIndex(
            pendingIsAction: pending,
            runningActions: 1,
            runningTotal: 1,
            maxConcurrentActions: 2,
            maxConcurrentComponents: 6
        )
        #expect(index == 0)
    }

    // MARK: - Batch prompt device budget

    @Test("Large registry is capped and keeps clause-relevant devices")
    func batchPromptDeviceBudget() {
        let resolver = BatchedConditionClauseResolver(
            singleResolver: AutomationConditionClauseResolutionWorkerSession(foundationModelAvailability: { false }),
            foundationModelAvailability: { false }
        )

        // 200 filler devices plus the two clause-relevant ones.
        var devices: [HomeCandidateRecord] = (0..<200).map { i in
            HomeCandidateRecord(
                id: "filler_\(i)",
                displayName: "Gadget \(i)",
                deviceType: "switch",
                room: "misc",
                capabilities: ["switch"],
                supportedCommands: ["switch": ["on", "off"]],
                currentState: ["switch": "off"]
            )
        }
        let frontDoor = HomeCandidateRecord(
            id: "front_door_lock",
            displayName: "Front Door Lock",
            deviceType: "lock",
            room: "hallway",
            capabilities: ["lock"],
            supportedCommands: ["lock": ["lock", "unlock"]],
            currentState: ["lock": "locked"]
        )
        let motion = HomeCandidateRecord(
            id: "motion_sensor",
            displayName: "Hallway Motion Sensor",
            deviceType: "motionSensor",
            room: "hallway",
            capabilities: ["motionSensor"],
            supportedCommands: [:],
            currentState: ["motion": "inactive"]
        )
        devices.append(frontDoor)
        devices.append(motion)

        let inputs = [
            AutomationConditionClauseResolutionInput(
                component: AutomationConditionComponent(id: "cond_1", rawText: "front door is locked", order: 0),
                fullUserText: "lock front door and check motion",
                availableDevices: devices,
                triggerPolicy: .never
            ),
            AutomationConditionClauseResolutionInput(
                component: AutomationConditionComponent(id: "cond_2", rawText: "hallway motion sensor is inactive", order: 1),
                fullUserText: "lock front door and check motion",
                availableDevices: devices,
                triggerPolicy: .never
            ),
        ]

        let budgeted = resolver.budgetedDevices(devices, for: inputs)

        // Capped.
        #expect(budgeted.count <= BatchedConditionClauseResolver.maxBatchPromptDevices)
        // Clause-relevant devices are retained despite the large registry.
        #expect(budgeted.contains { $0.id == "front_door_lock" })
        #expect(budgeted.contains { $0.id == "motion_sensor" })
    }

    @Test("Small registry passes through unchanged")
    func smallRegistryUnchanged() {
        let resolver = BatchedConditionClauseResolver(
            singleResolver: AutomationConditionClauseResolutionWorkerSession(foundationModelAvailability: { false }),
            foundationModelAvailability: { false }
        )
        let devices = (0..<5).map { i in
            HomeCandidateRecord(
                id: "d\(i)",
                displayName: "Device \(i)",
                deviceType: "switch",
                room: "misc",
                capabilities: ["switch"],
                supportedCommands: ["switch": ["on", "off"]],
                currentState: ["switch": "off"]
            )
        }
        let inputs = [
            AutomationConditionClauseResolutionInput(
                component: AutomationConditionComponent(id: "c", rawText: "device 1 is on", order: 0),
                fullUserText: "x",
                availableDevices: devices,
                triggerPolicy: .never
            )
        ]
        #expect(resolver.budgetedDevices(devices, for: inputs).count == devices.count)
    }
}
