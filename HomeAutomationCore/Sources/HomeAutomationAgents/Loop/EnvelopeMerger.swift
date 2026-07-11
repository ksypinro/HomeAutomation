import Foundation
import HomeAutomationCore

// MARK: - RepairResult

public enum RepairResult: Sendable {
    case fragmentNLU(actionIndex: Int?, FragmentNLUOutput)
    case target(fieldID: FieldID, ActionTargetResult)
    case capability(fieldID: FieldID, HomeCapabilityDecision)
    case trigger(AutomationTriggerResolutionOutput)
    case conditionClause(index: Int, AutomationConditionClauseResolutionResult)
    /// Multiple disputed condition leaves repaired in a single batched pass
    /// (Phase III batching reused by the `.conditionClause` repair specialist).
    case conditionClauses([(index: Int, result: AutomationConditionClauseResolutionResult)])
    case segmentation(AutomationComponentPlan)
    case riskRaise(HomeRiskClassificationResult)
    case operation(HomeOperationDetectionResult)
}

// MARK: - EnvelopeMerger

public enum EnvelopeMerger {

    public static func apply(
        _ result: RepairResult,
        to envelope: DraftEnvelope,
        iteration: Int
    ) -> DraftEnvelope {
        switch result {
        case .operation(let detectionResult):
            return mergeOperation(detectionResult, into: envelope, iteration: iteration)

        case .target(let fieldID, let targetResult):
            return mergeTarget(fieldID, result: targetResult, into: envelope, iteration: iteration)

        case .capability(let fieldID, let capDecision):
            return mergeCapability(fieldID, decision: capDecision, into: envelope, iteration: iteration)

        case .fragmentNLU(_, let nluOutput):
            return mergeFragmentNLU(nluOutput, into: envelope, iteration: iteration)

        case .trigger(let triggerOutput):
            return mergeTrigger(triggerOutput, into: envelope, iteration: iteration)

        case .conditionClause(let index, let clauseResult):
            return mergeConditionClause(index, result: clauseResult, into: envelope, iteration: iteration)

        case .conditionClauses(let clauseResults):
            return clauseResults.reduce(envelope) { partial, entry in
                mergeConditionClause(entry.index, result: entry.result, into: partial, iteration: iteration)
            }

        case .segmentation(let componentPlan):
            return mergeSegmentation(componentPlan, into: envelope, iteration: iteration)

        case .riskRaise(let riskResult):
            return mergeRiskRaise(riskResult, into: envelope, iteration: iteration)
        }
    }

    // MARK: - Operation

    private static func mergeOperation(
        _ result: HomeOperationDetectionResult,
        into envelope: DraftEnvelope,
        iteration: Int
    ) -> DraftEnvelope {
        DraftEnvelope(
            userText: envelope.userText,
            operation: result.operation,
            operationConfidence: result.confidence,
            command: envelope.command,
            automation: envelope.automation,
            risk: envelope.risk,
            clarification: envelope.clarification,
            provenance: envelope.provenance.merging(
                [.operation: .repaired(iteration: iteration)]
            ) { _, new in new },
            fieldConfidence: envelope.fieldConfidence.merging(
                [.operation: result.confidence]
            ) { _, new in new }
        )
    }

    // MARK: - Target

    private static func mergeTarget(
        _ fieldID: FieldID,
        result: ActionTargetResult,
        into envelope: DraftEnvelope,
        iteration: Int
    ) -> DraftEnvelope {
        var provenance = envelope.provenance
        var confidence = envelope.fieldConfidence
        provenance[fieldID] = .repaired(iteration: iteration)
        confidence[fieldID] = result.confidence

        if fieldID.rawValue.hasPrefix("command.") {
            guard let cmd = envelope.command else { return envelope }
            let updatedCmd = CommandDraftSection(
                targetDeviceID: result.selectedDeviceID ?? cmd.targetDeviceID,
                candidateTable: result.candidateTable.isEmpty ? cmd.candidateTable : result.candidateTable,
                capability: cmd.capability,
                commandName: cmd.commandName,
                parameters: cmd.parameters,
                room: cmd.room
            )
            return DraftEnvelope(
                userText: envelope.userText,
                operation: envelope.operation,
                operationConfidence: envelope.operationConfidence,
                command: updatedCmd,
                automation: envelope.automation,
                risk: envelope.risk,
                clarification: result.isAmbiguous ? envelope.clarification : nil,
                provenance: provenance,
                fieldConfidence: confidence
            )
        }

        guard let auto = envelope.automation,
              let match = fieldID.rawValue.firstMatch(of: /automation\.actions\[(\d+)\]\.targetDeviceID/),
              let index = Int(match.output.1),
              index < auto.actions.count else {
            return envelope
        }

        var actions = auto.actions
        let action = actions[index]
        let updatedCmd = CommandDraftSection(
            targetDeviceID: result.selectedDeviceID ?? action.command.targetDeviceID,
            candidateTable: result.candidateTable.isEmpty ? action.command.candidateTable : result.candidateTable,
            capability: action.command.capability,
            commandName: action.command.commandName,
            parameters: action.command.parameters,
            room: action.command.room
        )
        actions[index] = ActionDraft(rawText: action.rawText, order: action.order, command: updatedCmd)

        let updatedAuto = AutomationDraftSection(
            trigger: auto.trigger,
            conditionTree: auto.conditionTree,
            conditionLeaves: auto.conditionLeaves,
            actions: actions,
            unsupportedFragments: auto.unsupportedFragments,
            precedenceAmbiguous: auto.precedenceAmbiguous
        )

        return DraftEnvelope(
            userText: envelope.userText,
            operation: envelope.operation,
            operationConfidence: envelope.operationConfidence,
            automation: updatedAuto,
            risk: envelope.risk,
            clarification: envelope.clarification,
            provenance: provenance,
            fieldConfidence: confidence
        )
    }

    // MARK: - Capability

    private static func mergeCapability(
        _ fieldID: FieldID,
        decision: HomeCapabilityDecision,
        into envelope: DraftEnvelope,
        iteration: Int
    ) -> DraftEnvelope {
        var provenance = envelope.provenance
        var confidence = envelope.fieldConfidence

        if fieldID.rawValue.hasPrefix("command.") {
            guard let cmd = envelope.command else { return envelope }
            let updatedCmd = CommandDraftSection(
                targetDeviceID: decision.targetDeviceID ?? cmd.targetDeviceID,
                candidateTable: cmd.candidateTable,
                capability: decision.selectedCapability ?? cmd.capability,
                commandName: decision.selectedCommand ?? cmd.commandName,
                parameters: cmd.parameters,
                room: cmd.room
            )

            provenance[.command(.capability)] = .repaired(iteration: iteration)
            provenance[.command(.commandName)] = .repaired(iteration: iteration)
            confidence[.command(.capability)] = decision.confidence
            confidence[.command(.commandName)] = decision.confidence

            return DraftEnvelope(
                userText: envelope.userText,
                operation: envelope.operation,
                operationConfidence: envelope.operationConfidence,
                command: updatedCmd,
                automation: envelope.automation,
                risk: envelope.risk,
                clarification: envelope.clarification,
                provenance: provenance,
                fieldConfidence: confidence
            )
        }

        guard let auto = envelope.automation,
              let match = fieldID.rawValue.firstMatch(of: /automation\.actions\[(\d+)\]\./),
              let index = Int(match.output.1),
              index < auto.actions.count else {
            return envelope
        }

        var actions = auto.actions
        let action = actions[index]
        let updatedCmd = CommandDraftSection(
            targetDeviceID: decision.targetDeviceID ?? action.command.targetDeviceID,
            candidateTable: action.command.candidateTable,
            capability: decision.selectedCapability ?? action.command.capability,
            commandName: decision.selectedCommand ?? action.command.commandName,
            parameters: action.command.parameters,
            room: action.command.room
        )
        actions[index] = ActionDraft(rawText: action.rawText, order: action.order, command: updatedCmd)

        provenance[.action(index, .capability)] = .repaired(iteration: iteration)
        provenance[.action(index, .commandName)] = .repaired(iteration: iteration)
        confidence[.action(index, .capability)] = decision.confidence
        confidence[.action(index, .commandName)] = decision.confidence

        let updatedAuto = AutomationDraftSection(
            trigger: auto.trigger,
            conditionTree: auto.conditionTree,
            conditionLeaves: auto.conditionLeaves,
            actions: actions,
            unsupportedFragments: auto.unsupportedFragments,
            precedenceAmbiguous: auto.precedenceAmbiguous
        )

        return DraftEnvelope(
            userText: envelope.userText,
            operation: envelope.operation,
            operationConfidence: envelope.operationConfidence,
            automation: updatedAuto,
            risk: envelope.risk,
            clarification: envelope.clarification,
            provenance: provenance,
            fieldConfidence: confidence
        )
    }

    // MARK: - Fragment NLU

    private static func mergeFragmentNLU(
        _ output: FragmentNLUOutput,
        into envelope: DraftEnvelope,
        iteration: Int
    ) -> DraftEnvelope {
        envelope
    }

    // MARK: - Trigger

    private static func mergeTrigger(
        _ output: AutomationTriggerResolutionOutput,
        into envelope: DraftEnvelope,
        iteration: Int
    ) -> DraftEnvelope {
        guard let auto = envelope.automation, let trigger = output.trigger else { return envelope }

        let existingRawText = auto.trigger?.rawText
        let triggerDraft: TriggerDraft
        switch trigger {
        case .schedule(let schedule):
            triggerDraft = TriggerDraft(
                type: .schedule,
                time: schedule.timeOfDay,
                repeatRule: schedule.repeatRule,
                timezoneIdentifier: schedule.timezoneIdentifier,
                rawText: existingRawText,
                confidence: output.confidence
            )
        case .device(let deviceTrigger):
            triggerDraft = TriggerDraft(
                type: .device,
                deviceDescription: deviceTrigger.description,
                rawText: existingRawText,
                deviceCondition: deviceTrigger.condition,
                confidence: output.confidence
            )
        }

        let updatedAuto = AutomationDraftSection(
            trigger: triggerDraft,
            conditionTree: auto.conditionTree,
            conditionLeaves: auto.conditionLeaves,
            actions: auto.actions,
            unsupportedFragments: auto.unsupportedFragments,
            precedenceAmbiguous: auto.precedenceAmbiguous
        )

        var provenance = envelope.provenance
        var confidence = envelope.fieldConfidence
        provenance[.triggerType] = .repaired(iteration: iteration)
        provenance[.triggerTime] = .repaired(iteration: iteration)
        provenance[.triggerRepeat] = .repaired(iteration: iteration)
        confidence[.triggerType] = output.confidence
        confidence[.triggerTime] = triggerDraft.time != nil ? output.confidence : 0.0
        confidence[.triggerRepeat] = triggerDraft.repeatRule != nil ? output.confidence : 0.0

        return DraftEnvelope(
            userText: envelope.userText,
            operation: envelope.operation,
            operationConfidence: envelope.operationConfidence,
            automation: updatedAuto,
            risk: envelope.risk,
            clarification: envelope.clarification,
            provenance: provenance,
            fieldConfidence: confidence
        )
    }

    // MARK: - Condition clause

    private static func mergeConditionClause(
        _ index: Int,
        result: AutomationConditionClauseResolutionResult,
        into envelope: DraftEnvelope,
        iteration: Int
    ) -> DraftEnvelope {
        guard let auto = envelope.automation, index < auto.conditionLeaves.count else { return envelope }

        var leaves = auto.conditionLeaves
        let existingLeaf = leaves[index]

        let extracted = extractConditionFields(result.condition)

        let targetID = extracted.deviceID ?? existingLeaf.target
        let cap = extracted.capability ?? existingLeaf.capability
        let attr = extracted.attribute ?? existingLeaf.attribute
        let op = extracted.operatorName ?? existingLeaf.operatorName
        let val = extracted.value ?? existingLeaf.value

        leaves[index] = ConditionLeafDraft(
            id: existingLeaf.id,
            rawText: existingLeaf.rawText,
            target: targetID ?? existingLeaf.target,
            candidateTable: existingLeaf.candidateTable,
            capability: cap,
            attribute: attr,
            operatorName: op,
            value: val,
            confidence: result.confidence
        )

        let updatedAuto = AutomationDraftSection(
            trigger: auto.trigger,
            conditionTree: auto.conditionTree,
            conditionLeaves: leaves,
            actions: auto.actions,
            unsupportedFragments: auto.unsupportedFragments,
            precedenceAmbiguous: auto.precedenceAmbiguous
        )

        var provenance = envelope.provenance
        var confidence = envelope.fieldConfidence
        for aspect: FieldID.ConditionLeafAspect in [.target, .capability, .attribute, .operatorName, .value] {
            provenance[.conditionLeaf(index, aspect)] = .repaired(iteration: iteration)
            confidence[.conditionLeaf(index, aspect)] = result.confidence
        }

        return DraftEnvelope(
            userText: envelope.userText,
            operation: envelope.operation,
            operationConfidence: envelope.operationConfidence,
            automation: updatedAuto,
            risk: envelope.risk,
            clarification: envelope.clarification,
            provenance: provenance,
            fieldConfidence: confidence
        )
    }

    // MARK: - Segmentation

    private static func mergeSegmentation(
        _ plan: AutomationComponentPlan,
        into envelope: DraftEnvelope,
        iteration: Int
    ) -> DraftEnvelope {
        guard let auto = envelope.automation else { return envelope }

        let existingActionsByText = Dictionary(
            auto.actions.map { ($0.rawText.agentNormalizedHomeTokenString, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var newActions: [ActionDraft] = []
        for (i, actionComp) in plan.actions.enumerated() {
            let normalizedText = actionComp.rawText.agentNormalizedHomeTokenString
            if let existing = existingActionsByText[normalizedText] {
                newActions.append(ActionDraft(rawText: existing.rawText, order: i, command: existing.command))
            } else {
                newActions.append(ActionDraft(
                    rawText: actionComp.rawText,
                    order: i,
                    command: CommandDraftSection(
                        targetDeviceID: nil, capability: nil, commandName: nil, parameters: [], room: nil
                    )
                ))
            }
        }

        let conditionTree = plan.conditionTree.map { ConditionTreeDraft(from: $0) }

        let updatedAuto = AutomationDraftSection(
            trigger: auto.trigger,
            conditionTree: conditionTree ?? auto.conditionTree,
            conditionLeaves: auto.conditionLeaves,
            actions: newActions,
            unsupportedFragments: plan.unsupportedFragments,
            precedenceAmbiguous: auto.precedenceAmbiguous
        )

        var provenance = envelope.provenance
        for i in newActions.indices {
            for field: FieldID.Command in [.targetDeviceID, .capability, .commandName, .parameters] {
                provenance[.action(i, field)] = .repaired(iteration: iteration)
            }
        }

        return DraftEnvelope(
            userText: envelope.userText,
            operation: envelope.operation,
            operationConfidence: envelope.operationConfidence,
            automation: updatedAuto,
            risk: envelope.risk,
            clarification: envelope.clarification,
            provenance: provenance,
            fieldConfidence: envelope.fieldConfidence
        )
    }

    // MARK: - Condition field extraction

    private struct ConditionFields {
        var deviceID: String?
        var capability: String?
        var attribute: String?
        var operatorName: HomeAutomationComparisonOperator?
        var value: String?
    }

    private static func extractConditionFields(_ condition: HomeAutomationCondition?) -> ConditionFields {
        guard let condition else { return ConditionFields() }

        switch condition {
        case .comparison(let comp):
            var fields = ConditionFields()
            fields.operatorName = comp.operatorName

            if case .deviceAttribute(_, let deviceID, let capability, let attribute) = comp.left {
                fields.deviceID = deviceID
                fields.capability = capability
                fields.attribute = attribute
            }

            switch comp.right {
            case .literalString(let s):
                fields.value = s
            case .literalNumber(let n, let unit):
                fields.value = unit.map { "\(n) \($0)" } ?? "\(n)"
            case .deviceAttribute(let desc, _, _, _):
                fields.value = desc
            default:
                break
            }

            return fields

        case .and(let children), .or(let children):
            return children.first.flatMap { extractConditionFields($0) } ?? ConditionFields()

        case .not(let child), .changes(let child):
            return extractConditionFields(child)
        }
    }

    // MARK: - Risk raise

    private static func mergeRiskRaise(
        _ result: HomeRiskClassificationResult,
        into envelope: DraftEnvelope,
        iteration: Int
    ) -> DraftEnvelope {
        var risk = envelope.risk
        risk.raise(to: result.riskLevel, reason: result.reason)

        var provenance = envelope.provenance
        var confidence = envelope.fieldConfidence
        provenance[.riskLevel] = .repaired(iteration: iteration)
        confidence[.riskLevel] = result.confidence

        return DraftEnvelope(
            userText: envelope.userText,
            operation: envelope.operation,
            operationConfidence: envelope.operationConfidence,
            command: envelope.command,
            automation: envelope.automation,
            risk: risk,
            clarification: envelope.clarification,
            provenance: provenance,
            fieldConfidence: confidence
        )
    }
}
