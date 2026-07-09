import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import Testing

@Suite("StructuralDraftBuilder")
struct StructuralDraftBuilderTests {

    @Test("Builds command draft from complete section")
    func buildsFromCompleteSection() {
        let section = CommandDraftSection(
            targetDeviceID: "lamp-1",
            capability: "switch",
            commandName: "on",
            room: "bedroom"
        )
        let risk = RiskSection(level: .low, floorReason: "safe")

        let draft = StructuralDraftBuilder.commandDraft(from: section, risk: risk)

        #expect(draft != nil)
        #expect(draft?.intent == .turnOn)
        #expect(draft?.targetDeviceID == "lamp-1")
        #expect(draft?.capability == "switch")
        #expect(draft?.command == "on")
        #expect(draft?.needsClarification == false)
        #expect(draft?.requiresConfirmation == false)
    }

    @Test("Returns nil when capability missing")
    func nilWhenCapabilityMissing() {
        let section = CommandDraftSection(
            targetDeviceID: "lamp-1",
            capability: nil,
            commandName: "on",
            room: "bedroom"
        )
        let risk = RiskSection(level: .low, floorReason: "safe")

        let draft = StructuralDraftBuilder.commandDraft(from: section, risk: risk)
        #expect(draft == nil)
    }

    @Test("Returns nil when commandName missing")
    func nilWhenCommandNameMissing() {
        let section = CommandDraftSection(
            targetDeviceID: "lamp-1",
            capability: "switch",
            commandName: nil,
            room: "bedroom"
        )
        let risk = RiskSection(level: .low, floorReason: "safe")

        let draft = StructuralDraftBuilder.commandDraft(from: section, risk: risk)
        #expect(draft == nil)
    }

    @Test("Sets needsClarification when targetDeviceID is nil")
    func needsClarificationWhenNoTarget() {
        let section = CommandDraftSection(
            targetDeviceID: nil,
            capability: "switch",
            commandName: "on",
            room: nil
        )
        let risk = RiskSection(level: .low, floorReason: "safe")

        let draft = StructuralDraftBuilder.commandDraft(from: section, risk: risk)

        #expect(draft != nil)
        #expect(draft?.needsClarification == true)
        #expect(draft?.clarificationQuestion != nil)
    }

    @Test("High risk sets requiresConfirmation")
    func highRiskRequiresConfirmation() {
        let section = CommandDraftSection(
            targetDeviceID: "lock-1",
            capability: "lock",
            commandName: "unlock",
            room: "front door"
        )
        let risk = RiskSection(level: .high, floorReason: "unlocking door")

        let draft = StructuralDraftBuilder.commandDraft(from: section, risk: risk)

        #expect(draft != nil)
        #expect(draft?.requiresConfirmation == true)
    }

    @Test("Infers correct intents from command names")
    func intentInference() {
        let risk = RiskSection(level: .low, floorReason: "safe")

        let cases: [(String, String, HomeAutomationIntent)] = [
            ("on", "switch", .turnOn),
            ("off", "switch", .turnOff),
            ("open", "windowShade", .open),
            ("close", "windowShade", .close),
            ("lock", "lock", .lock),
            ("unlock", "lock", .unlock),
            ("setLevel", "dimmer", .setValue),
        ]

        for (commandName, capability, expectedIntent) in cases {
            let section = CommandDraftSection(
                targetDeviceID: "dev-1",
                capability: capability,
                commandName: commandName,
                room: nil
            )
            let draft = StructuralDraftBuilder.commandDraft(from: section, risk: risk)
            #expect(draft?.intent == expectedIntent, "Expected \(expectedIntent) for \(commandName)")
        }
    }

    // MARK: - H2: Automation creation plan

    @Test("Schedule automation envelope compiles to SmartThings JSON")
    func scheduleAutomationCompilesToJSON() async {
        let pipeline = DeterministicDraftPipeline(registry: MockHomeDeviceRegistry())
        let envelope = await pipeline.makeAutomationEnvelope(
            text: "turn on the bedroom lamp every day at 7 PM"
        )

        let plan = StructuralDraftBuilder.automationCreationPlan(from: envelope)

        #expect(plan.smartThingsRuleJSON != nil)
        #expect(plan.unsupportedCompilationReason == nil)
        #expect(!plan.resolvedActions.isEmpty)
        #expect(plan.ruleDraft.trigger != nil)
        // JSON should reference the resolved device and an every-schedule action.
        let json = plan.smartThingsRuleJSON ?? ""
        #expect(json.contains("bedroom_lamp"))
        #expect(json.contains("every"))
    }

    @Test("High-risk automation envelope flags confirmation")
    func highRiskAutomationRequiresConfirmation() {
        let action = ActionDraft(
            rawText: "unlock the front door",
            order: 0,
            command: CommandDraftSection(
                targetDeviceID: "front_door_lock",
                candidateTable: [
                    CompactCandidate(id: "front_door_lock", name: "Front Door", room: nil, deviceType: "lock"),
                ],
                capability: "lock",
                commandName: "unlock",
                room: nil
            )
        )
        let envelope = DraftEnvelope(
            userText: "unlock the front door every day at 8 AM",
            operation: .automationCreation,
            operationConfidence: 0.9,
            automation: AutomationDraftSection(
                trigger: TriggerDraft(type: .schedule, time: HomeAutomationTimeOfDay(hour: 8, minute: 0), repeatRule: .everyDay, confidence: 0.9),
                actions: [action]
            ),
            risk: RiskSection(level: .high, floorReason: "unlocking a door")
        )

        let plan = StructuralDraftBuilder.automationCreationPlan(from: envelope)

        #expect(plan.requiresConfirmation)
        #expect(plan.smartThingsRuleJSON != nil)
    }

    @Test("Device-trigger envelope surfaces an unsupported compilation reason")
    func deviceTriggerEnvelopeIsUnsupported() {
        let action = ActionDraft(
            rawText: "turn on the porch light",
            order: 0,
            command: CommandDraftSection(
                targetDeviceID: "porch_light",
                candidateTable: [
                    CompactCandidate(id: "porch_light", name: "Porch Light", room: nil, deviceType: "light"),
                ],
                capability: "switch",
                commandName: "on",
                room: nil
            )
        )
        let envelope = DraftEnvelope(
            userText: "when the front door opens turn on the porch light",
            operation: .automationCreation,
            operationConfidence: 0.9,
            automation: AutomationDraftSection(
                trigger: TriggerDraft(type: .device, deviceDescription: "front door opens", confidence: 0.8),
                actions: [action]
            ),
            risk: RiskSection(level: .low, floorReason: "safe")
        )

        let plan = StructuralDraftBuilder.automationCreationPlan(from: envelope)

        #expect(plan.smartThingsRuleJSON == nil)
        #expect(plan.unsupportedCompilationReason != nil)
    }
}
