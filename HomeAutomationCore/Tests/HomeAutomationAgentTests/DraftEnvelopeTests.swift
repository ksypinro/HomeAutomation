import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import Testing

@Suite("DraftEnvelope Types")
struct DraftEnvelopeTests {

    // MARK: - Codable round-trip

    @Test("DraftEnvelope round-trips through JSON")
    func envelopeCodableRoundTrip() throws {
        let envelope = DraftEnvelope(
            userText: "turn on the bedroom lamp",
            operation: .executeDeviceCommand,
            operationConfidence: 0.92,
            command: CommandDraftSection(
                targetDeviceID: "bedroom_lamp",
                candidateTable: [
                    CompactCandidate(id: "bedroom_lamp", name: "Bedroom Lamp", room: "bedroom", deviceType: "light")
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
                .command(.capability): .model,
                .riskLevel: .repaired(iteration: 1),
            ],
            fieldConfidence: [
                .operation: 0.92,
                .command(.targetDeviceID): 0.88,
                .command(.capability): 0.75,
            ]
        )

        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(DraftEnvelope.self, from: data)

        #expect(decoded == envelope)
        #expect(decoded.version == 1)
        #expect(decoded.userText == "turn on the bedroom lamp")
        #expect(decoded.operation == .executeDeviceCommand)
        #expect(decoded.command?.targetDeviceID == "bedroom_lamp")
        #expect(decoded.command?.capability == "switch")
        #expect(decoded.command?.candidateTable.count == 1)
        #expect(decoded.risk.level == .low)
        #expect(decoded.provenance[.command(.capability)] == .model)
        #expect(decoded.fieldConfidence[.command(.targetDeviceID)] == 0.88)
    }

    @Test("AutomationDraftSection round-trips through JSON")
    func automationSectionCodableRoundTrip() throws {
        let envelope = DraftEnvelope(
            userText: "turn on the lamp every day at 7 PM",
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
                        targetDeviceID: "bedroom_lamp", capability: "switch", commandName: "on", parameters: [], room: "bedroom"
                    ))
                ],
                precedenceAmbiguous: true
            ),
            risk: RiskSection(level: .low, floorReason: "test")
        )

        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(DraftEnvelope.self, from: data)
        #expect(decoded == envelope)
        #expect(decoded.automation?.trigger?.type == .schedule)
        #expect(decoded.automation?.trigger?.time?.hour == 19)
        #expect(decoded.automation?.conditionLeaves.count == 2)
        #expect(decoded.automation?.actions.count == 1)
        #expect(decoded.automation?.precedenceAmbiguous == true)
    }

    // MARK: - FieldID builders

    @Test("FieldID builders produce expected dotted paths")
    func fieldIDBuilders() {
        #expect(FieldID.command(.targetDeviceID).rawValue == "command.targetDeviceID")
        #expect(FieldID.command(.capability).rawValue == "command.capability")
        #expect(FieldID.action(0, .targetDeviceID).rawValue == "automation.actions[0].targetDeviceID")
        #expect(FieldID.action(2, .commandName).rawValue == "automation.actions[2].commandName")
        #expect(FieldID.conditionLeaf(1, .target).rawValue == "automation.conditionLeaves[1].target")
        #expect(FieldID.conditionLeaf(0, .value).rawValue == "automation.conditionLeaves[0].value")
        #expect(FieldID.conditionTreeGroup(0).rawValue == "automation.conditionTree.group[0]")
        #expect(FieldID.triggerType.rawValue == "automation.trigger.type")
        #expect(FieldID.riskLevel.rawValue == "risk.level")
    }

    // MARK: - disputableFieldIDs

    @Test("disputableFieldIDs for a command envelope")
    func disputableFieldIDsCommand() {
        let envelope = DraftEnvelope(
            userText: "turn on lamp",
            operation: .executeDeviceCommand,
            operationConfidence: 0.9,
            command: CommandDraftSection(
                targetDeviceID: "lamp", capability: "switch", commandName: "on", parameters: [], room: "bedroom"
            ),
            risk: RiskSection(level: .low, floorReason: "test")
        )

        let ids = envelope.disputableFieldIDs()
        #expect(ids.contains(.operation))
        #expect(ids.contains(.command(.targetDeviceID)))
        #expect(ids.contains(.command(.capability)))
        #expect(ids.contains(.command(.commandName)))
        #expect(ids.contains(.command(.room)))
        #expect(ids.contains(.command(.parameters)))
        #expect(ids.contains(.riskLevel))
        #expect(!ids.contains(.triggerType))
        #expect(!ids.contains(FieldID.action(0, .targetDeviceID)))
    }

    @Test("disputableFieldIDs for an automation envelope with 2 actions and 3 conditions")
    func disputableFieldIDsAutomation() {
        let envelope = DraftEnvelope(
            userText: "test",
            operation: .automationCreation,
            operationConfidence: 0.9,
            automation: AutomationDraftSection(
                trigger: TriggerDraft(type: .schedule, confidence: 0.8),
                conditionTree: .or([.and([.leaf("c1"), .leaf("c2")]), .leaf("c3")]),
                conditionLeaves: [
                    ConditionLeafDraft(id: "c1", rawText: "a", confidence: 0.5),
                    ConditionLeafDraft(id: "c2", rawText: "b", confidence: 0.5),
                    ConditionLeafDraft(id: "c3", rawText: "c", confidence: 0.5),
                ],
                actions: [
                    ActionDraft(rawText: "x", order: 0, command: CommandDraftSection(
                        targetDeviceID: nil, capability: nil, commandName: nil, parameters: [], room: nil
                    )),
                    ActionDraft(rawText: "y", order: 1, command: CommandDraftSection(
                        targetDeviceID: nil, capability: nil, commandName: nil, parameters: [], room: nil
                    )),
                ]
            ),
            risk: RiskSection(level: .low, floorReason: "test")
        )

        let ids = envelope.disputableFieldIDs()

        #expect(ids.contains(.operation))
        #expect(ids.contains(.triggerType))
        #expect(ids.contains(.triggerTime))
        #expect(ids.contains(.triggerRepeat))

        #expect(ids.contains(.action(0, .targetDeviceID)))
        #expect(ids.contains(.action(0, .capability)))
        #expect(ids.contains(.action(1, .targetDeviceID)))
        #expect(ids.contains(.action(1, .commandName)))

        #expect(ids.contains(.conditionLeaf(0, .target)))
        #expect(ids.contains(.conditionLeaf(1, .value)))
        #expect(ids.contains(.conditionLeaf(2, .operatorName)))

        #expect(ids.contains(.conditionTreeGroup(0)))
        #expect(ids.contains(.conditionTreeGroup(1)))

        #expect(ids.contains(.riskLevel))
        #expect(!ids.contains(.command(.targetDeviceID)))
    }

    // MARK: - RiskSection floor

    @Test("RiskSection.raise cannot lower the level")
    func riskRaiseCannotLower() {
        var risk = RiskSection(level: .high, floorReason: "initial")

        risk.raise(to: .low, reason: "attempt to lower")
        #expect(risk.level == .high)
        #expect(risk.floorReason == "initial")

        risk.raise(to: .critical, reason: "escalated")
        #expect(risk.level == .critical)
        #expect(risk.floorReason == "escalated")

        risk.raise(to: .high, reason: "lower again")
        #expect(risk.level == .critical)
    }

    // MARK: - lowConfidenceFieldIDs

    @Test("lowConfidenceFieldIDs filters fields below threshold")
    func lowConfidenceFieldIDs() {
        let envelope = DraftEnvelope(
            userText: "test",
            operation: .executeDeviceCommand,
            operationConfidence: 0.9,
            command: CommandDraftSection(
                targetDeviceID: "x", capability: "switch", commandName: "on", parameters: [], room: nil
            ),
            risk: RiskSection(level: .low, floorReason: "test"),
            fieldConfidence: [
                .operation: 0.9,
                .command(.targetDeviceID): 0.8,
                .command(.capability): 0.3,
                .command(.commandName): 0.0,
            ]
        )

        let low = envelope.lowConfidenceFieldIDs(threshold: 0.5)
        #expect(low.contains(.command(.capability)))
        #expect(low.contains(.command(.commandName)))
        #expect(!low.contains(.operation))
        #expect(!low.contains(.command(.targetDeviceID)))
    }

    // MARK: - ConditionTreeDraft ↔ AutomationConditionTreeDescriptor

    @Test("ConditionTreeDraft converts to and from AutomationConditionTreeDescriptor")
    func conditionTreeConversion() {
        let descriptor = AutomationConditionTreeDescriptor.or([
            .and([.leaf("c1"), .leaf("c2")]),
            .leaf("c3")
        ])

        let draft = ConditionTreeDraft(from: descriptor)
        let roundTripped = draft.toDescriptor()
        #expect(roundTripped == descriptor)
    }

    // MARK: - CompactCandidate from HomeCandidateRecord

    @Test("CompactCandidate initializes from HomeCandidateRecord")
    func compactCandidateFromRecord() {
        let record = HomeCandidateRecord(
            id: "test_device",
            displayName: "Test Device",
            deviceType: "light",
            room: "bedroom",
            capabilities: ["switch"],
            supportedCommands: [:]
        )
        let compact = CompactCandidate(from: record)
        #expect(compact.id == "test_device")
        #expect(compact.name == "Test Device")
        #expect(compact.room == "bedroom")
        #expect(compact.deviceType == "light")
    }

    // MARK: - Provenance / confidence update helpers

    @Test("withUpdatedProvenance merges without losing existing entries")
    func withUpdatedProvenance() {
        let envelope = DraftEnvelope(
            userText: "test",
            operation: .executeDeviceCommand,
            operationConfidence: 0.9,
            risk: RiskSection(level: .low, floorReason: "test"),
            provenance: [.operation: .rules, .command(.capability): .rules]
        )
        let updated = envelope.withUpdatedProvenance([.command(.capability): .repaired(iteration: 1)])
        #expect(updated.provenance[.operation] == .rules)
        #expect(updated.provenance[.command(.capability)] == .repaired(iteration: 1))
    }
}
