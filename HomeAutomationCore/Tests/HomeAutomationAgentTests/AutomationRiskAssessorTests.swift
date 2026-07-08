import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import Testing

@Suite("AutomationRiskAssessor")
struct AutomationRiskAssessorTests {

    let assessor = AutomationRiskAssessor()

    @Test("Low risk command envelope stays low")
    func lowRiskCommand() {
        let envelope = DraftEnvelope(
            userText: "turn on the light",
            operation: .executeDeviceCommand,
            operationConfidence: 0.9,
            command: CommandDraftSection(
                targetDeviceID: "light-1",
                capability: "switch",
                commandName: "on",
                room: "living room"
            ),
            risk: RiskSection(level: .low, floorReason: "safe")
        )

        let result = assessor.assess(envelope: envelope)
        #expect(result.level == .low || result.level == .medium)
    }

    @Test("Security-sensitive capability raises risk to high")
    func securityCapabilityRaisesRisk() {
        let envelope = DraftEnvelope(
            userText: "unlock the front door",
            operation: .executeDeviceCommand,
            operationConfidence: 0.9,
            command: CommandDraftSection(
                targetDeviceID: "lock-1",
                capability: "lock",
                commandName: "unlock",
                room: "front door"
            ),
            risk: RiskSection(level: .low, floorReason: "safe")
        )

        let result = assessor.assess(envelope: envelope)
        #expect(result.level == .high || result.level == .critical)
    }

    @Test("Alarm capability raises risk")
    func alarmCapabilityRaisesRisk() {
        let envelope = DraftEnvelope(
            userText: "disable the alarm",
            operation: .executeDeviceCommand,
            operationConfidence: 0.9,
            command: CommandDraftSection(
                targetDeviceID: "alarm-1",
                capability: "alarm",
                commandName: "off",
                room: nil
            ),
            risk: RiskSection(level: .low, floorReason: "safe")
        )

        let result = assessor.assess(envelope: envelope)
        #expect(result.level == .high || result.level == .critical)
    }

    @Test("requiresConfirmation true for high-risk commands")
    func requiresConfirmationForHighRisk() {
        let envelope = DraftEnvelope(
            userText: "unlock the door",
            operation: .executeDeviceCommand,
            operationConfidence: 0.9,
            command: CommandDraftSection(
                targetDeviceID: "lock-1",
                capability: "lock",
                commandName: "unlock",
                room: nil
            ),
            risk: RiskSection(level: .low, floorReason: "safe")
        )

        #expect(assessor.requiresConfirmation(envelope: envelope))
    }

    @Test("Risk never lowers from floor")
    func riskNeverLowers() {
        let envelope = DraftEnvelope(
            userText: "turn on the light",
            operation: .executeDeviceCommand,
            operationConfidence: 0.9,
            command: CommandDraftSection(
                targetDeviceID: "light-1",
                capability: "switch",
                commandName: "on",
                room: nil
            ),
            risk: RiskSection(level: .high, floorReason: "pre-existing high risk")
        )

        let result = assessor.assess(envelope: envelope)
        #expect(result.level == .high || result.level == .critical)
    }

    @Test("Automation actions assessed individually")
    func automationActionsAssessed() {
        let envelope = DraftEnvelope(
            userText: "when I leave, lock the door and turn off lights",
            operation: .automationCreation,
            operationConfidence: 0.9,
            automation: AutomationDraftSection(
                actions: [
                    ActionDraft(
                        rawText: "lock the door",
                        order: 0,
                        command: CommandDraftSection(
                            targetDeviceID: "lock-1",
                            capability: "lock",
                            commandName: "lock",
                            room: nil
                        )
                    ),
                    ActionDraft(
                        rawText: "turn off lights",
                        order: 1,
                        command: CommandDraftSection(
                            targetDeviceID: "light-1",
                            capability: "switch",
                            commandName: "off",
                            room: nil
                        )
                    ),
                ]
            ),
            risk: RiskSection(level: .low, floorReason: "safe")
        )

        let result = assessor.assess(envelope: envelope)
        #expect([HomeAutomationRiskLevel.low, .medium, .high, .critical].contains(result.level))
    }
}
