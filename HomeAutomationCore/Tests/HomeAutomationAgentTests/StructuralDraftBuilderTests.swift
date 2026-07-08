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
}
