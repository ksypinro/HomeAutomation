import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import Testing

@Suite("VerifierPromptBuilder")
struct VerifierPromptBuilderTests {

    // MARK: - Initial prompt for command envelope

    @Test("Initial prompt for a command envelope includes all key sections")
    func commandEnvelopeInitialPrompt() {
        let envelope = makeCommandEnvelope()
        let builder = VerifierPromptBuilder()
        let prompt = builder.makeInitialPrompt(envelope: envelope)

        #expect(prompt.text.contains("turn on the bedroom lamp"))
        #expect(prompt.text.contains("command.targetDeviceID"))
        #expect(prompt.text.contains("command.capability"))
        #expect(prompt.text.contains("bedroom_lamp"))
        #expect(prompt.text.contains("switch"))
        #expect(prompt.text.contains("Risk:"))
        #expect(prompt.text.contains("Disputable fields:"))
        #expect(prompt.characterCount == prompt.text.count)
        #expect(prompt.characterCount > 0)
    }

    // MARK: - Initial prompt for automation envelope

    @Test("Initial prompt for an automation envelope includes trigger, actions, conditions, and interpretation")
    func automationEnvelopeInitialPrompt() {
        let envelope = makeAutomationEnvelope()
        let builder = VerifierPromptBuilder()
        let prompt = builder.makeInitialPrompt(envelope: envelope)

        #expect(prompt.text.contains("Automation:"))
        #expect(prompt.text.contains("Trigger:"))
        #expect(prompt.text.contains("schedule"))
        #expect(prompt.text.contains("19:00"))
        #expect(prompt.text.contains("Action[0]"))
        #expect(prompt.text.contains("bedroom_lamp"))
        #expect(prompt.text.contains("Conditions:"))
        #expect(prompt.text.contains("Interpretation:"))
        #expect(prompt.text.contains("AND"))
        #expect(prompt.text.contains("automation.trigger.type"))
        #expect(prompt.text.contains("automation.actions[0].targetDeviceID"))
    }

    // MARK: - Low confidence flagging

    @Test("Low-confidence fields are flagged with ⚠ marker")
    func lowConfidenceFieldsFlagged() {
        let envelope = DraftEnvelope(
            userText: "test",
            operation: .executeDeviceCommand,
            operationConfidence: 0.9,
            command: CommandDraftSection(
                targetDeviceID: "lamp", capability: "switch", commandName: "on", parameters: [], room: "bedroom"
            ),
            risk: RiskSection(level: .low, floorReason: "test"),
            fieldConfidence: [
                .operation: 0.9,
                .command(.targetDeviceID): 0.3,
                .command(.capability): 0.8,
            ]
        )

        let builder = VerifierPromptBuilder()
        let prompt = builder.makeInitialPrompt(envelope: envelope)

        #expect(prompt.text.contains("command.targetDeviceID ⚠"))
    }

    // MARK: - Budget enforcement

    @Test("Large candidate table is truncated when over budget")
    func budgetEnforcementTruncatesCandidates() {
        let candidates = (0..<40).map { i in
            CompactCandidate(id: "device_\(i)", name: "Device \(i)", room: "room_\(i % 5)", deviceType: "light")
        }
        let envelope = DraftEnvelope(
            userText: "turn on a lamp",
            operation: .executeDeviceCommand,
            operationConfidence: 0.9,
            command: CommandDraftSection(
                targetDeviceID: "device_0",
                candidateTable: candidates,
                capability: "switch",
                commandName: "on",
                parameters: [],
                room: "room_0"
            ),
            risk: RiskSection(level: .low, floorReason: "test"),
            fieldConfidence: [.operation: 0.9, .command(.targetDeviceID): 0.8]
        )

        let builder = VerifierPromptBuilder(characterBudget: 800)
        let prompt = builder.makeInitialPrompt(envelope: envelope)

        let pipeCount = prompt.text.components(separatedBy: "|").count - 1
        #expect(pipeCount <= 3 * 4 + 4)
    }

    // MARK: - Delta prompt

    @Test("Delta prompt includes repaired fields and previous dispute evidence")
    func deltaPromptContent() {
        let envelope = makeCommandEnvelope()
        let disputes = [
            DraftDispute(fieldID: "command.targetDeviceID", kind: .wrongTarget, evidence: "User said kitchen, not bedroom")
        ]
        let repairedFields: [FieldID] = [.command(.targetDeviceID)]

        let builder = VerifierPromptBuilder()
        let prompt = builder.makeDeltaPrompt(
            envelope: envelope,
            previousDisputes: disputes,
            repairedFields: repairedFields
        )

        #expect(prompt.text.contains("repaired"))
        #expect(prompt.text.contains("command.targetDeviceID"))
        #expect(prompt.text.contains("bedroom_lamp"))
        #expect(prompt.text.contains("User said kitchen, not bedroom"))
    }

    // MARK: - Precedence ambiguity flag

    @Test("Precedence ambiguity is shown in automation prompts")
    func precedenceAmbiguityFlag() {
        let envelope = DraftEnvelope(
            userText: "test",
            operation: .automationCreation,
            operationConfidence: 0.9,
            automation: AutomationDraftSection(
                trigger: TriggerDraft(type: .schedule, confidence: 0.8),
                actions: [],
                precedenceAmbiguous: true
            ),
            risk: RiskSection(level: .low, floorReason: "test")
        )

        let builder = VerifierPromptBuilder()
        let prompt = builder.makeInitialPrompt(envelope: envelope)

        #expect(prompt.text.contains("Precedence ambiguity"))
    }

    // MARK: - Helpers

    private func makeCommandEnvelope() -> DraftEnvelope {
        DraftEnvelope(
            userText: "turn on the bedroom lamp",
            operation: .executeDeviceCommand,
            operationConfidence: 0.92,
            command: CommandDraftSection(
                targetDeviceID: "bedroom_lamp",
                candidateTable: [
                    CompactCandidate(id: "bedroom_lamp", name: "Bedroom Lamp", room: "bedroom", deviceType: "light"),
                    CompactCandidate(id: "living_room_lamp", name: "Living Room Lamp", room: "living room", deviceType: "light"),
                ],
                capability: "switch",
                commandName: "on",
                parameters: [],
                room: "bedroom"
            ),
            risk: RiskSection(level: .low, floorReason: "Deterministic rule"),
            provenance: [
                .operation: .rules,
                .command(.targetDeviceID): .rules,
                .command(.capability): .rules,
            ],
            fieldConfidence: [
                .operation: 0.92,
                .command(.targetDeviceID): 0.88,
                .command(.capability): 0.85,
            ]
        )
    }

    private func makeAutomationEnvelope() -> DraftEnvelope {
        DraftEnvelope(
            userText: "turn on the lamp every day at 7 PM if the light is on and the fan is off",
            operation: .automationCreation,
            operationConfidence: 0.90,
            automation: AutomationDraftSection(
                trigger: TriggerDraft(
                    type: .schedule,
                    time: HomeAutomationTimeOfDay(hour: 19, minute: 0),
                    repeatRule: .everyDay,
                    confidence: 0.85
                ),
                conditionTree: .and([.leaf("c1"), .leaf("c2")]),
                conditionLeaves: [
                    ConditionLeafDraft(id: "c1", rawText: "the light is on", capability: "switch", attribute: "switch", operatorName: .equals, value: "on", confidence: 0.8),
                    ConditionLeafDraft(id: "c2", rawText: "the fan is off", capability: "switch", attribute: "switch", operatorName: .equals, value: "off", confidence: 0.7),
                ],
                actions: [
                    ActionDraft(rawText: "turn on the lamp", order: 0, command: CommandDraftSection(
                        targetDeviceID: "bedroom_lamp",
                        candidateTable: [CompactCandidate(id: "bedroom_lamp", name: "Bedroom Lamp", room: "bedroom", deviceType: "light")],
                        capability: "switch",
                        commandName: "on",
                        parameters: [],
                        room: "bedroom"
                    ))
                ],
                precedenceAmbiguous: false
            ),
            risk: RiskSection(level: .low, floorReason: "test"),
            fieldConfidence: [
                .operation: 0.9,
                .triggerType: 0.85,
                .triggerTime: 0.85,
                .action(0, .targetDeviceID): 0.8,
            ]
        )
    }
}
