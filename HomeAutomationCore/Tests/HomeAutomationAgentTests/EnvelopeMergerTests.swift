import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import Testing

@Suite("EnvelopeMerger")
struct EnvelopeMergerTests {

    private func makeCommandEnvelope() -> DraftEnvelope {
        DraftEnvelope(
            userText: "turn on the bedroom light",
            operation: .executeDeviceCommand,
            operationConfidence: 0.9,
            command: CommandDraftSection(
                targetDeviceID: "lamp-1",
                candidateTable: [
                    CompactCandidate(id: "lamp-1", name: "Bedroom Light", room: "Bedroom", deviceType: "light")
                ],
                capability: "switch",
                commandName: "on",
                room: "bedroom"
            ),
            risk: RiskSection(level: .low, floorReason: "safe"),
            provenance: [.command(.targetDeviceID): .rules],
            fieldConfidence: [.command(.targetDeviceID): 0.8]
        )
    }

    private func makeAutomationEnvelope() -> DraftEnvelope {
        DraftEnvelope(
            userText: "every day at 7am turn on the light and close the blinds",
            operation: .automationCreation,
            operationConfidence: 0.9,
            automation: AutomationDraftSection(
                trigger: TriggerDraft(type: .schedule, confidence: 0.8),
                conditionLeaves: [
                    ConditionLeafDraft(
                        id: "cond-0",
                        rawText: "temperature is above 75",
                        target: "thermo-1",
                        capability: "temperatureMeasurement",
                        attribute: "temperature",
                        operatorName: .greaterThan,
                        value: "75",
                        confidence: 0.7
                    )
                ],
                actions: [
                    ActionDraft(
                        rawText: "turn on the light",
                        order: 0,
                        command: CommandDraftSection(
                            targetDeviceID: "light-1",
                            capability: "switch",
                            commandName: "on",
                            room: nil
                        )
                    ),
                    ActionDraft(
                        rawText: "close the blinds",
                        order: 1,
                        command: CommandDraftSection(
                            targetDeviceID: "blinds-1",
                            capability: "windowShade",
                            commandName: "close",
                            room: nil
                        )
                    ),
                ]
            ),
            risk: RiskSection(level: .low, floorReason: "safe")
        )
    }

    // MARK: - Operation merge

    @Test("Operation merge updates operation and confidence")
    func mergeOperation() {
        let envelope = makeCommandEnvelope()
        let result = RepairResult.operation(
            HomeOperationDetectionResult(
                domain: .homeAutomation,
                operation: .automationCreation,
                confidence: 0.95,
                reason: "user wants automation"
            )
        )

        let merged = EnvelopeMerger.apply(result, to: envelope, iteration: 1)

        #expect(merged.operation == .automationCreation)
        #expect(merged.operationConfidence == 0.95)
        #expect(merged.provenance[.operation] == .repaired(iteration: 1))
        #expect(merged.fieldConfidence[.operation] == 0.95)
    }

    // MARK: - Target merge

    @Test("Command target merge updates targetDeviceID")
    func mergeCommandTarget() {
        let envelope = makeCommandEnvelope()
        let targetResult = ActionTargetResult(
            selectedDeviceID: "lamp-2",
            candidateTable: [
                CompactCandidate(id: "lamp-2", name: "Other Light", room: "Bedroom", deviceType: "light")
            ],
            confidence: 0.92,
            isAmbiguous: false
        )
        let result = RepairResult.target(fieldID: .command(.targetDeviceID), targetResult)

        let merged = EnvelopeMerger.apply(result, to: envelope, iteration: 2)

        #expect(merged.command?.targetDeviceID == "lamp-2")
        #expect(merged.command?.candidateTable.count == 1)
        #expect(merged.command?.candidateTable.first?.id == "lamp-2")
        #expect(merged.provenance[.command(.targetDeviceID)] == .repaired(iteration: 2))
        #expect(merged.fieldConfidence[.command(.targetDeviceID)] == 0.92)
    }

    @Test("Automation action target merge updates action device")
    func mergeAutomationActionTarget() {
        let envelope = makeAutomationEnvelope()
        let targetResult = ActionTargetResult(
            selectedDeviceID: "light-99",
            candidateTable: [
                CompactCandidate(id: "light-99", name: "New Light", room: nil, deviceType: "light")
            ],
            confidence: 0.88,
            isAmbiguous: false
        )
        let fieldID = FieldID.action(0, .targetDeviceID)
        let result = RepairResult.target(fieldID: fieldID, targetResult)

        let merged = EnvelopeMerger.apply(result, to: envelope, iteration: 1)

        #expect(merged.automation?.actions[0].command.targetDeviceID == "light-99")
        #expect(merged.provenance[fieldID] == .repaired(iteration: 1))
    }

    @Test("Ambiguous target preserves clarification")
    func ambiguousTargetPreservesClarification() {
        let envelope = DraftEnvelope(
            userText: "turn on the light",
            operation: .executeDeviceCommand,
            operationConfidence: 0.9,
            command: CommandDraftSection(
                targetDeviceID: nil,
                capability: "switch",
                commandName: "on",
                room: nil
            ),
            risk: RiskSection(level: .low, floorReason: "safe"),
            clarification: ClarificationSection(
                question: "Which light?",
                ambiguousFieldIDs: [.command(.targetDeviceID)]
            )
        )

        let targetResult = ActionTargetResult(
            selectedDeviceID: nil,
            candidateTable: [],
            confidence: 0.1,
            isAmbiguous: true
        )
        let result = RepairResult.target(fieldID: .command(.targetDeviceID), targetResult)
        let merged = EnvelopeMerger.apply(result, to: envelope, iteration: 1)

        #expect(merged.clarification != nil)
    }

    // MARK: - Capability merge

    @Test("Capability merge updates command capability and commandName")
    func mergeCapability() {
        let envelope = makeCommandEnvelope()
        let decision = HomeCapabilityDecision(
            selectedCapability: "dimmer",
            selectedCommand: "setLevel",
            targetDeviceID: nil,
            alternatives: [],
            evidence: ["dimmer is correct"],
            confidence: 0.9
        )
        let result = RepairResult.capability(fieldID: .command(.capability), decision)

        let merged = EnvelopeMerger.apply(result, to: envelope, iteration: 1)

        #expect(merged.command?.capability == "dimmer")
        #expect(merged.command?.commandName == "setLevel")
        #expect(merged.provenance[.command(.capability)] == .repaired(iteration: 1))
        #expect(merged.provenance[.command(.commandName)] == .repaired(iteration: 1))
    }

    @Test("Capability merge on automation action updates correct action")
    func mergeAutomationActionCapability() {
        let envelope = makeAutomationEnvelope()
        let decision = HomeCapabilityDecision(
            selectedCapability: "dimmer",
            selectedCommand: "setLevel",
            targetDeviceID: nil,
            alternatives: [],
            evidence: [],
            confidence: 0.85
        )
        let fieldID = FieldID.action(1, .capability)
        let result = RepairResult.capability(fieldID: fieldID, decision)

        let merged = EnvelopeMerger.apply(result, to: envelope, iteration: 2)

        #expect(merged.automation?.actions[1].command.capability == "dimmer")
        #expect(merged.automation?.actions[1].command.commandName == "setLevel")
        #expect(merged.automation?.actions[0].command.capability == "switch")
    }

    // MARK: - Risk raise

    @Test("Risk raise increases risk level, never lowers")
    func mergeRiskRaise() {
        let envelope = makeCommandEnvelope()
        let riskResult = HomeRiskClassificationResult(
            riskLevel: .high,
            requiresConfirmation: true,
            reason: "unlocking door",
            confidence: 0.95
        )
        let result = RepairResult.riskRaise(riskResult)

        let merged = EnvelopeMerger.apply(result, to: envelope, iteration: 1)

        #expect(merged.risk.level == .high)
        #expect(merged.risk.floorReason == "unlocking door")
        #expect(merged.provenance[.riskLevel] == .repaired(iteration: 1))
    }

    @Test("Risk raise does not lower existing high risk")
    func riskNeverLowers() {
        let envelope = DraftEnvelope(
            userText: "test",
            operation: .executeDeviceCommand,
            operationConfidence: 0.9,
            command: CommandDraftSection(
                targetDeviceID: "dev-1",
                capability: "switch",
                commandName: "on",
                room: nil
            ),
            risk: RiskSection(level: .high, floorReason: "pre-existing")
        )

        let riskResult = HomeRiskClassificationResult(
            riskLevel: .low,
            requiresConfirmation: false,
            reason: "seems safe",
            confidence: 0.8
        )
        let result = RepairResult.riskRaise(riskResult)
        let merged = EnvelopeMerger.apply(result, to: envelope, iteration: 1)

        #expect(merged.risk.level == .high)
        #expect(merged.risk.floorReason == "pre-existing")
    }

    // MARK: - Condition clause merge

    @Test("Condition clause merge updates leaf fields")
    func mergeConditionClause() {
        let envelope = makeAutomationEnvelope()
        let clauseResult = AutomationConditionClauseResolutionResult(
            id: "cond-0",
            rawText: "temperature is above 80",
            condition: .comparison(
                HomeAutomationComparisonCondition(
                    left: .deviceAttribute(
                        description: "temperature sensor",
                        deviceID: "thermo-2",
                        capability: "temperatureMeasurement",
                        attribute: "temperature"
                    ),
                    operatorName: .greaterThan,
                    right: .literalNumber(80.0, unit: "F")
                )
            ),
            records: [],
            confidence: 0.9
        )
        let result = RepairResult.conditionClause(index: 0, clauseResult)

        let merged = EnvelopeMerger.apply(result, to: envelope, iteration: 1)

        #expect(merged.automation?.conditionLeaves[0].target == "thermo-2")
        #expect(merged.automation?.conditionLeaves[0].capability == "temperatureMeasurement")
        #expect(merged.automation?.conditionLeaves[0].attribute == "temperature")
        #expect(merged.automation?.conditionLeaves[0].operatorName == .greaterThan)
        #expect(merged.automation?.conditionLeaves[0].value == "80.0 F")
        #expect(merged.automation?.conditionLeaves[0].confidence == 0.9)
        #expect(merged.provenance[.conditionLeaf(0, .target)] == .repaired(iteration: 1))
    }

    @Test("Condition clause with nil condition preserves existing leaf values")
    func conditionClauseNilConditionPreserves() {
        let envelope = makeAutomationEnvelope()
        let clauseResult = AutomationConditionClauseResolutionResult(
            id: "cond-0",
            rawText: "temperature is above 75",
            condition: nil,
            records: [],
            confidence: 0.5
        )
        let result = RepairResult.conditionClause(index: 0, clauseResult)

        let merged = EnvelopeMerger.apply(result, to: envelope, iteration: 1)

        #expect(merged.automation?.conditionLeaves[0].capability == "temperatureMeasurement")
        #expect(merged.automation?.conditionLeaves[0].value == "75")
    }

    // MARK: - Provenance tracking

    @Test("Iteration number tracked in provenance")
    func iterationTracked() {
        let envelope = makeCommandEnvelope()
        let result = RepairResult.operation(
            HomeOperationDetectionResult(
                domain: .homeAutomation,
                operation: .executeDeviceCommand,
                confidence: 0.9,
                reason: "correct"
            )
        )

        let merged3 = EnvelopeMerger.apply(result, to: envelope, iteration: 3)
        #expect(merged3.provenance[.operation] == .repaired(iteration: 3))
    }

    // MARK: - Unchanged fields preserved

    @Test("Merge preserves unrelated fields")
    func preservesUnrelatedFields() {
        let envelope = makeCommandEnvelope()
        let result = RepairResult.operation(
            HomeOperationDetectionResult(
                domain: .homeAutomation,
                operation: .executeDeviceCommand,
                confidence: 0.95,
                reason: "confirmed"
            )
        )

        let merged = EnvelopeMerger.apply(result, to: envelope, iteration: 1)

        #expect(merged.userText == envelope.userText)
        #expect(merged.command == envelope.command)
        #expect(merged.risk == envelope.risk)
    }
}
