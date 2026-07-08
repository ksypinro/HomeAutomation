import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import Testing

@Suite("RepairPlanner")
struct RepairPlannerTests {

    let planner = RepairPlanner()

    private func makeEnvelope(operation: HomeAutomationOperationKind = .executeDeviceCommand) -> DraftEnvelope {
        DraftEnvelope(
            userText: "turn on the living room light",
            operation: operation,
            operationConfidence: 0.9,
            command: CommandDraftSection(
                targetDeviceID: "lamp1",
                capability: "switch",
                commandName: "on",
                room: "living room"
            ),
            risk: RiskSection(level: .low, floorReason: "safe")
        )
    }

    // MARK: - Specialist routing

    @Test("Operation dispute routes to operationDetection")
    func operationRouting() {
        let disputes = [
            DraftDispute(fieldID: "operation", kind: .wrongOperation, evidence: "should be automation")
        ]
        let plan = planner.plan(
            disputes: disputes,
            envelope: makeEnvelope(),
            latchedFieldIDs: [],
            maxRepairCalls: 5
        )

        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].specialist == .operationDetection)
    }

    @Test("Target dispute routes to target specialist")
    func targetRouting() {
        let disputes = [
            DraftDispute(fieldID: "command.targetDeviceID", kind: .wrongTarget, evidence: "wrong device")
        ]
        let plan = planner.plan(
            disputes: disputes,
            envelope: makeEnvelope(),
            latchedFieldIDs: [],
            maxRepairCalls: 5
        )

        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].specialist == .target)
    }

    @Test("Capability dispute routes to capability specialist")
    func capabilityRouting() {
        let disputes = [
            DraftDispute(fieldID: "command.capability", kind: .wrongValue, evidence: "wrong cap")
        ]
        let plan = planner.plan(
            disputes: disputes,
            envelope: makeEnvelope(),
            latchedFieldIDs: [],
            maxRepairCalls: 5
        )

        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].specialist == .capability)
    }

    @Test("Risk dispute routes to riskRaise")
    func riskRouting() {
        let disputes = [
            DraftDispute(fieldID: "risk.level", kind: .wrongValue, evidence: "understated risk")
        ]
        let plan = planner.plan(
            disputes: disputes,
            envelope: makeEnvelope(),
            latchedFieldIDs: [],
            maxRepairCalls: 5
        )

        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].specialist == .riskRaise)
    }

    @Test("Trigger dispute routes to trigger specialist")
    func triggerRouting() {
        let disputes = [
            DraftDispute(fieldID: "automation.trigger.type", kind: .wrongValue, evidence: "wrong type")
        ]
        let plan = planner.plan(
            disputes: disputes,
            envelope: makeEnvelope(operation: .automationCreation),
            latchedFieldIDs: [],
            maxRepairCalls: 5
        )

        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].specialist == .trigger)
    }

    @Test("Condition leaf routes to conditionClause specialist")
    func conditionClauseRouting() {
        let disputes = [
            DraftDispute(fieldID: "automation.conditionLeaves[0].capability", kind: .wrongValue, evidence: "wrong condition")
        ]
        let plan = planner.plan(
            disputes: disputes,
            envelope: makeEnvelope(operation: .automationCreation),
            latchedFieldIDs: [],
            maxRepairCalls: 5
        )

        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].specialist == .conditionClause)
    }

    @Test("WrongGrouping routes to segmentation")
    func segmentationRouting() {
        let disputes = [
            DraftDispute(fieldID: "automation.actions[0].capability", kind: .wrongGrouping, evidence: "action split wrong")
        ]
        let plan = planner.plan(
            disputes: disputes,
            envelope: makeEnvelope(operation: .automationCreation),
            latchedFieldIDs: [],
            maxRepairCalls: 5
        )

        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].specialist == .segmentation)
    }

    // MARK: - Priority ordering

    @Test("Steps ordered by priority: operation before target before capability")
    func priorityOrdering() {
        let disputes = [
            DraftDispute(fieldID: "command.capability", kind: .wrongValue, evidence: "cap"),
            DraftDispute(fieldID: "operation", kind: .wrongOperation, evidence: "op"),
            DraftDispute(fieldID: "command.targetDeviceID", kind: .wrongTarget, evidence: "target"),
        ]
        let plan = planner.plan(
            disputes: disputes,
            envelope: makeEnvelope(),
            latchedFieldIDs: [],
            maxRepairCalls: 5
        )

        #expect(plan.steps.count == 3)
        #expect(plan.steps[0].specialist == .operationDetection)
        #expect(plan.steps[1].specialist == .target)
        #expect(plan.steps[2].specialist == .capability)
    }

    // MARK: - Budget capping

    @Test("maxRepairCalls caps non-riskRaise steps")
    func budgetCapping() {
        let disputes = [
            DraftDispute(fieldID: "operation", kind: .wrongOperation, evidence: "op"),
            DraftDispute(fieldID: "command.targetDeviceID", kind: .wrongTarget, evidence: "target"),
            DraftDispute(fieldID: "command.capability", kind: .wrongValue, evidence: "cap"),
            DraftDispute(fieldID: "risk.level", kind: .wrongValue, evidence: "risk"),
        ]
        let plan = planner.plan(
            disputes: disputes,
            envelope: makeEnvelope(),
            latchedFieldIDs: [],
            maxRepairCalls: 2
        )

        let nonRisk = plan.steps.filter { $0.specialist != .riskRaise }
        #expect(nonRisk.count == 2)
        #expect(plan.steps.contains { $0.specialist == .riskRaise })
        #expect(plan.deferred.count == 1)
    }

    @Test("riskRaise is always scheduled regardless of budget")
    func riskAlwaysScheduled() {
        let disputes = [
            DraftDispute(fieldID: "operation", kind: .wrongOperation, evidence: "op"),
            DraftDispute(fieldID: "command.targetDeviceID", kind: .wrongTarget, evidence: "target"),
            DraftDispute(fieldID: "risk.level", kind: .wrongValue, evidence: "risk"),
        ]
        let plan = planner.plan(
            disputes: disputes,
            envelope: makeEnvelope(),
            latchedFieldIDs: [],
            maxRepairCalls: 1
        )

        #expect(plan.steps.contains { $0.specialist == .riskRaise })
        #expect(plan.steps.contains { $0.specialist == .operationDetection })
        #expect(!plan.steps.contains { $0.specialist == .target })
    }

    // MARK: - Latched fields

    @Test("Latched fields go to deferred")
    func latchedFieldsDeferred() {
        let disputes = [
            DraftDispute(fieldID: "command.targetDeviceID", kind: .wrongTarget, evidence: "target"),
            DraftDispute(fieldID: "command.capability", kind: .wrongValue, evidence: "cap"),
        ]
        let latched: Set<FieldID> = [.command(.targetDeviceID)]
        let plan = planner.plan(
            disputes: disputes,
            envelope: makeEnvelope(),
            latchedFieldIDs: latched,
            maxRepairCalls: 5
        )

        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].specialist == .capability)
        #expect(plan.deferred.count == 1)
        #expect(plan.deferred[0].fieldID == "command.targetDeviceID")
    }

    // MARK: - Empty disputes

    @Test("Empty disputes produces empty plan")
    func emptyDisputes() {
        let plan = planner.plan(
            disputes: [],
            envelope: makeEnvelope(),
            latchedFieldIDs: [],
            maxRepairCalls: 5
        )

        #expect(plan.steps.isEmpty)
        #expect(plan.deferred.isEmpty)
    }
}
