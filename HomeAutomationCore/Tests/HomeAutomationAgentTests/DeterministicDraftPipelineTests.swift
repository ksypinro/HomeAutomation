import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import Testing

@Suite("DeterministicDraftPipeline")
struct DeterministicDraftPipelineTests {

    private func makePipeline() -> DeterministicDraftPipeline {
        DeterministicDraftPipeline(registry: MockHomeDeviceRegistry())
    }

    // MARK: - B3: Direct command envelopes

    @Test("Simple power-on command produces a full envelope with high confidence")
    func simpleCommandEnvelope() async {
        let pipeline = makePipeline()
        let envelope = await pipeline.makeCommandEnvelope(text: "turn on the bedroom lamp")

        #expect(envelope.version == DraftEnvelope.currentVersion)
        #expect(envelope.userText == "turn on the bedroom lamp")
        #expect(envelope.operation == .executeDeviceCommand)
        #expect(envelope.command != nil)
        #expect(envelope.automation == nil)
        #expect(envelope.command?.targetDeviceID == "bedroom_lamp")
        #expect(envelope.command?.capability == "switch")
        #expect(envelope.command?.commandName == "on")
        #expect(envelope.command?.room == "bedroom")
        #expect(!envelope.command!.candidateTable.isEmpty)
        #expect(envelope.risk.level == .low)
        #expect(envelope.provenance[.command(.targetDeviceID)] == .rules)
        #expect(envelope.fieldConfidence[.command(.targetDeviceID)]! > 0.5)
        #expect(envelope.fieldConfidence[.command(.capability)]! > 0.0)
        #expect(envelope.clarification == nil)
    }

    @Test("Power-off command for blinds resolves windowShade capability")
    func blindsCommandEnvelope() async {
        let pipeline = makePipeline()
        let envelope = await pipeline.makeCommandEnvelope(text: "turn off the living room blinds")

        #expect(envelope.command?.targetDeviceID == "living_room_blinds")
        #expect(envelope.command?.capability == "windowShade")
        #expect(envelope.command?.commandName == "close")
    }

    @Test("Thermostat command includes temperature parameters")
    func thermostatCommandEnvelope() async {
        let pipeline = makePipeline()
        let envelope = await pipeline.makeCommandEnvelope(text: "set the hallway thermostat to 22 degrees")

        #expect(envelope.command?.targetDeviceID == "hallway_thermostat")
        #expect(envelope.command?.parameters.contains(where: { $0.name == "value" }) == true)
        #expect(envelope.fieldConfidence[.command(.parameters)]! > 0.0)
    }

    @Test("Unresolvable command produces zero-confidence target and clarification")
    func unresolvableCommandEnvelope() async {
        let pipeline = makePipeline()
        let envelope = await pipeline.makeCommandEnvelope(text: "do something weird with the gizmo")

        #expect(envelope.fieldConfidence[.command(.targetDeviceID)] == 0.0)
        #expect(envelope.clarification != nil)
        #expect(envelope.clarification?.ambiguousFieldIDs.contains(.command(.targetDeviceID)) == true)
    }

    @Test("All provenance entries are .rules for deterministic pipeline")
    func allProvenanceIsRules() async {
        let pipeline = makePipeline()
        let envelope = await pipeline.makeCommandEnvelope(text: "turn on the bedroom lamp")

        for (_, prov) in envelope.provenance {
            #expect(prov == .rules)
        }
    }

    @Test("Lock command resolves to a lock capability device")
    func lockCommandEnvelope() async {
        let pipeline = makePipeline()
        let envelope = await pipeline.makeCommandEnvelope(text: "lock the front door")

        #expect(envelope.command?.targetDeviceID != nil)
        #expect(envelope.command?.capability == "lock")
        #expect(envelope.command?.commandName == "lock")
    }

    @Test("Device without a room omits room from field confidence")
    func roomlessDeviceOmitsRoomConfidence() async {
        let roomlessLamp = HomeCandidateRecord(
            id: "desk_lamp",
            displayName: "Desk Lamp",
            deviceType: "light",
            room: nil,
            capabilities: ["switch"],
            supportedCommands: ["switch": ["on", "off"]]
        )
        let pipeline = DeterministicDraftPipeline(
            registry: MockHomeDeviceRegistry(devices: [roomlessLamp])
        )
        let envelope = await pipeline.makeCommandEnvelope(text: "turn on the desk lamp")

        #expect(envelope.command?.targetDeviceID == "desk_lamp")
        #expect(envelope.command?.room == nil)
        // No room ⇒ no room confidence entry, so τ-gates and zero-confidence
        // pre-repair don't treat the missing room as an unresolved field.
        #expect(envelope.fieldConfidence[.command(.room)] == nil)
        let zeroConfidenceFields = envelope.fieldConfidence.filter { $0.value == 0.0 }
        #expect(zeroConfidenceFields.isEmpty)
    }

    // MARK: - B4: Automation envelopes

    @Test("Simple schedule automation produces trigger and action")
    func simpleAutomationEnvelope() async {
        let pipeline = makePipeline()
        let envelope = await pipeline.makeAutomationEnvelope(
            text: "turn on the bedroom lamp every day at 7 PM"
        )

        #expect(envelope.operation == .automationCreation)
        #expect(envelope.automation != nil)
        #expect(envelope.command == nil)

        let auto = envelope.automation!
        #expect(auto.trigger?.type == .schedule)
        #expect(auto.trigger?.time?.hour == 19)
        #expect(auto.trigger?.time?.minute == 0)
        #expect(auto.actions.count == 1)
        #expect(auto.actions[0].command.targetDeviceID == "bedroom_lamp")
        #expect(auto.actions[0].command.capability == "switch")
        #expect(auto.actions[0].command.commandName == "on")
        #expect(auto.precedenceAmbiguous == false)
        #expect(envelope.fieldConfidence[.triggerType]! > 0.0)
        #expect(envelope.fieldConfidence[.triggerTime]! > 0.0)
    }

    @Test("Multi-action automation with conditions produces correct structure")
    func multiActionAutomationEnvelope() async {
        let pipeline = makePipeline()
        let envelope = await pipeline.makeAutomationEnvelope(
            text: "turn on the bedroom lamp and turn off the living room blinds every day at 7 PM if the living room TV is off"
        )

        let auto = envelope.automation!
        #expect(auto.actions.count == 2)
        #expect(auto.trigger?.type == .schedule)

        let action0DeviceID = auto.actions[0].command.targetDeviceID
        let action1DeviceID = auto.actions[1].command.targetDeviceID
        let deviceIDs = [action0DeviceID, action1DeviceID].compactMap { $0 }
        #expect(deviceIDs.contains("bedroom_lamp"))
        #expect(deviceIDs.contains("living_room_blinds"))

        #expect(envelope.fieldConfidence[.action(0, .targetDeviceID)] != nil)
        #expect(envelope.fieldConfidence[.action(1, .targetDeviceID)] != nil)
    }

    @Test("Stress example with mixed AND/OR conditions flags precedence ambiguity")
    func stressExamplePrecedenceAmbiguity() async {
        let pipeline = makePipeline()
        let envelope = await pipeline.makeAutomationEnvelope(
            text: "turn on the bedroom AC and turn off the living room blinds every day at 7 PM if the living room ceiling light is on and the bedroom AC is off or the living room TV is off"
        )

        let auto = envelope.automation!
        #expect(auto.precedenceAmbiguous == true)
        #expect(auto.trigger?.type == .schedule)
        #expect(auto.trigger?.time?.hour == 19)
        #expect(auto.actions.count >= 2)
    }

    @Test("Unparseable automation produces empty automation section with medium risk")
    func unparseableAutomationEnvelope() async {
        let pipeline = makePipeline()
        let envelope = await pipeline.makeAutomationEnvelope(text: "hello world")

        #expect(envelope.automation != nil)
        #expect(envelope.automation?.actions.isEmpty == true)
        #expect(envelope.risk.level == .medium)
    }

    @Test("Automation envelope actions are mapped to action-indexed FieldIDs")
    func automationFieldIDMapping() async {
        let pipeline = makePipeline()
        let envelope = await pipeline.makeAutomationEnvelope(
            text: "turn on the bedroom lamp every day at 8 AM"
        )

        let ids = envelope.disputableFieldIDs()
        #expect(ids.contains(.action(0, .targetDeviceID)))
        #expect(ids.contains(.action(0, .capability)))
        #expect(ids.contains(.operation))
        #expect(ids.contains(.riskLevel))
        #expect(ids.contains(.triggerType))
    }

    @Test("Condition leaves parse state values for simple conditions")
    func conditionLeafStateParsing() async {
        let pipeline = makePipeline()
        let envelope = await pipeline.makeAutomationEnvelope(
            text: "turn on the bedroom lamp every day at 7 PM if the bedroom lamp is on"
        )

        let auto = envelope.automation!
        #expect(!auto.conditionLeaves.isEmpty)
        let leaf = auto.conditionLeaves[0]
        #expect(leaf.capability == "switch")
        #expect(leaf.attribute == "switch")
        #expect(leaf.operatorName == .equals)
        #expect(leaf.value == "on")
    }
}
