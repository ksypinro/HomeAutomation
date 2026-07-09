import Foundation
import HomeAutomationCore

public struct DeterministicDraftPipeline: Sendable {
    private let registry: any DeviceRegistryProtocol

    public init(registry: any DeviceRegistryProtocol) {
        self.registry = registry
    }

    // MARK: - Direct command envelope (B3)

    public func makeCommandEnvelope(
        text: String,
        memoryHints: [MemoryHint] = []
    ) async -> DraftEnvelope {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let operationResult = HomeOperationDetectionService().analyzeSemantics(trimmed)
        let state = AgentTextParser.deterministicState(for: trimmed)
        let devices = await registry.allDevices()
        let normalized = trimmed.agentNormalizedHomeTokenString

        let semanticHints = AgentSemanticHints(
            preferredDeviceIDs: Set(memoryHints.compactMap(\.deviceID)),
            preferredCapabilityIDs: Set(memoryHints.compactMap(\.capability))
        )

        guard let ruleIntent = AgentRuleIntent(normalized: normalized) else {
            return unresolvableCommandEnvelope(
                text: trimmed,
                operation: operationResult,
                state: state,
                devices: devices
            )
        }

        let ranking = RuleCandidateScorer.rank(
            devices: devices,
            intent: ruleIntent,
            normalized: normalized,
            semanticHints: semanticHints
        )

        guard let selected = ranking.selected else {
            return unresolvableCommandEnvelope(
                text: trimmed,
                operation: operationResult,
                state: state,
                devices: devices
            )
        }

        let candidateTable = ranking.scored.prefix(8).map { CompactCandidate(from: $0.device) }
        let capDecision = resolveCapability(
            text: trimmed,
            state: state,
            device: selected.device,
            aggregationConfidence: ranking.confidence
        )

        let provenance: [FieldID: FieldProvenance] = [
            .operation: .rules,
            .command(.targetDeviceID): .rules,
            .command(.capability): .rules,
            .command(.commandName): .rules,
            .command(.room): .rules,
            .command(.parameters): .rules,
            .riskLevel: .rules,
        ]

        var fieldConfidence: [FieldID: Double] = [
            .operation: operationResult.confidence,
            .command(.targetDeviceID): ranking.confidence,
            .command(.capability): capDecision.confidence,
            .command(.commandName): capDecision.confidence,
            .command(.parameters): parametersConfidence(selected.draftIntent.parameters),
            .riskLevel: state.risk.confidence,
        ]
        // A device without a room has nothing to repair there; omitting the
        // field keeps τ-gates and zero-confidence pre-repair from treating
        // "no room" as an unresolved field.
        if selected.device.room != nil {
            fieldConfidence[.command(.room)] = ranking.confidence
        }

        var clarification: ClarificationSection? = nil
        if ranking.isAmbiguous {
            clarification = ClarificationSection(
                question: "Which \(selected.device.deviceType) do you mean?",
                ambiguousFieldIDs: [.command(.targetDeviceID)]
            )
            fieldConfidence[.command(.targetDeviceID)] = 0.4
        }

        let risk = RiskSection(
            level: state.risk.riskLevel,
            floorReason: state.risk.reason
        )

        let commandSection = CommandDraftSection(
            targetDeviceID: selected.device.id,
            candidateTable: candidateTable,
            capability: capDecision.selectedCapability ?? selected.draftIntent.capability,
            commandName: capDecision.selectedCommand ?? selected.draftIntent.command,
            parameters: selected.draftIntent.parameters,
            room: selected.device.room
        )

        return DraftEnvelope(
            userText: trimmed,
            operation: operationResult.operation,
            operationConfidence: operationResult.confidence,
            command: commandSection,
            risk: risk,
            clarification: clarification,
            provenance: provenance,
            fieldConfidence: fieldConfidence
        )
    }

    // MARK: - Automation envelope (B4)

    public func makeAutomationEnvelope(text: String) async -> DraftEnvelope {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let operationResult = HomeOperationDetectionService().analyzeSemantics(trimmed)

        guard let parsed = AutomationPatternParser().parse(trimmed) else {
            return emptyAutomationEnvelope(text: trimmed, operation: operationResult)
        }

        let componentPlan = AutomationPatternParserHintTool.componentPlan(
            from: parsed,
            sourceText: trimmed
        )

        let triggerDraft = await resolveTriggerDeterministically(componentPlan.trigger)
        let devices = await registry.allDevices()

        var actions: [ActionDraft] = []
        var actionProvenance: [FieldID: FieldProvenance] = [:]
        var actionConfidence: [FieldID: Double] = [:]

        for (i, actionComp) in componentPlan.actions.enumerated() {
            let actionEnvelope = await makeCommandEnvelope(text: actionComp.rawText)
            let cmdSection = actionEnvelope.command ?? CommandDraftSection(
                targetDeviceID: nil, capability: nil, commandName: nil, parameters: [], room: nil
            )
            actions.append(ActionDraft(rawText: actionComp.rawText, order: i, command: cmdSection))

            for (fieldID, prov) in actionEnvelope.provenance {
                if let remapped = remapCommandField(fieldID, toActionIndex: i) {
                    actionProvenance[remapped] = prov
                }
            }
            for (fieldID, conf) in actionEnvelope.fieldConfidence {
                if let remapped = remapCommandField(fieldID, toActionIndex: i) {
                    actionConfidence[remapped] = conf
                }
            }
        }

        let conditionLeaves = conditionLeafDrafts(
            from: componentPlan.conditions,
            devices: devices,
            normalized: trimmed.agentNormalizedHomeTokenString
        )

        let conditionTree = componentPlan.conditionTree.map { ConditionTreeDraft(from: $0) }
        let precedenceAmbiguous = hasPrecedenceAmbiguity(trimmed)

        var provenance: [FieldID: FieldProvenance] = [
            .operation: .rules,
            .riskLevel: .rules,
        ]
        provenance.merge(actionProvenance) { _, new in new }

        if triggerDraft != nil {
            provenance[.triggerType] = .rules
            provenance[.triggerTime] = .rules
            provenance[.triggerRepeat] = .rules
        }

        for (i, _) in conditionLeaves.enumerated() {
            provenance[.conditionLeaf(i, .target)] = .rules
            provenance[.conditionLeaf(i, .capability)] = .rules
            provenance[.conditionLeaf(i, .attribute)] = .rules
            provenance[.conditionLeaf(i, .operatorName)] = .rules
            provenance[.conditionLeaf(i, .value)] = .rules
        }

        var fieldConfidence: [FieldID: Double] = [
            .operation: operationResult.confidence,
            .riskLevel: parsed.confidence,
        ]
        fieldConfidence.merge(actionConfidence) { _, new in new }

        if let trig = triggerDraft {
            fieldConfidence[.triggerType] = trig.confidence
            fieldConfidence[.triggerTime] = trig.time != nil ? trig.confidence : 0.0
            fieldConfidence[.triggerRepeat] = trig.repeatRule != nil ? trig.confidence : 0.0
        }

        for (i, leaf) in conditionLeaves.enumerated() {
            fieldConfidence[.conditionLeaf(i, .target)] = leaf.target != nil ? leaf.confidence : 0.0
            fieldConfidence[.conditionLeaf(i, .capability)] = leaf.capability != nil ? leaf.confidence : 0.0
            fieldConfidence[.conditionLeaf(i, .attribute)] = leaf.attribute != nil ? leaf.confidence : 0.0
            fieldConfidence[.conditionLeaf(i, .operatorName)] = leaf.operatorName != nil ? leaf.confidence : 0.0
            fieldConfidence[.conditionLeaf(i, .value)] = leaf.value != nil ? leaf.confidence : 0.0
        }

        if let conditionTree {
            let groupCount = countGroups(conditionTree)
            for i in 0..<groupCount {
                provenance[.conditionTreeGroup(i)] = .rules
                fieldConfidence[.conditionTreeGroup(i)] = precedenceAmbiguous ? 0.5 : parsed.confidence
            }
        }

        let maxActionRisk = actions.compactMap { action -> HomeAutomationRiskLevel? in
            let state = AgentTextParser.deterministicState(for: action.rawText)
            return state.risk.riskLevel
        }.max(by: { $0.numericOrder < $1.numericOrder })

        var risk = RiskSection(
            level: maxActionRisk ?? .low,
            floorReason: "Deterministic automation risk floor"
        )
        if parsed.confidence < 0.7 {
            risk.raise(to: .medium, reason: "Low-confidence automation parse")
        }

        let automationSection = AutomationDraftSection(
            trigger: triggerDraft,
            conditionTree: conditionTree,
            conditionLeaves: conditionLeaves,
            actions: actions,
            unsupportedFragments: componentPlan.unsupportedFragments,
            precedenceAmbiguous: precedenceAmbiguous
        )

        return DraftEnvelope(
            userText: trimmed,
            operation: operationResult.operation,
            operationConfidence: operationResult.confidence,
            automation: automationSection,
            risk: risk,
            provenance: provenance,
            fieldConfidence: fieldConfidence
        )
    }

    // MARK: - Private helpers

    private func resolveCapability(
        text: String,
        state: HomeResolutionState,
        device: HomeCandidateRecord,
        aggregationConfidence: Double
    ) -> HomeCapabilityDecision {
        let input = CapabilityResolutionInput(
            rawText: text,
            resolutionState: state,
            hydratedCandidates: [device],
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: [device.id],
                needsClarification: false,
                confidence: aggregationConfidence
            ),
            knowledgeSnippets: []
        )
        return CapabilityResolutionAgent.resolveDeterministically(input)
    }

    private func parametersConfidence(_ params: [HomeResolvedParameter]) -> Double {
        guard !params.isEmpty else { return 1.0 }
        return params.map(\.confidence).min() ?? 0.0
    }

    private func unresolvableCommandEnvelope(
        text: String,
        operation: HomeOperationDetectionResult,
        state: HomeResolutionState,
        devices: [HomeCandidateRecord]
    ) -> DraftEnvelope {
        let candidateTable = devices.prefix(8).map { CompactCandidate(from: $0) }
        let commandSection = CommandDraftSection(
            targetDeviceID: nil,
            candidateTable: candidateTable,
            capability: nil,
            commandName: nil,
            parameters: [],
            room: nil
        )
        return DraftEnvelope(
            userText: text,
            operation: operation.operation,
            operationConfidence: operation.confidence,
            command: commandSection,
            risk: RiskSection(level: state.risk.riskLevel, floorReason: state.risk.reason),
            clarification: ClarificationSection(
                question: "Which device do you want to control?",
                ambiguousFieldIDs: [.command(.targetDeviceID)]
            ),
            provenance: [
                .operation: .rules,
                .command(.targetDeviceID): .rules,
                .riskLevel: .rules,
            ],
            fieldConfidence: [
                .operation: operation.confidence,
                .command(.targetDeviceID): 0.0,
                .command(.capability): 0.0,
                .command(.commandName): 0.0,
                .riskLevel: state.risk.confidence,
            ]
        )
    }

    private func emptyAutomationEnvelope(
        text: String,
        operation: HomeOperationDetectionResult
    ) -> DraftEnvelope {
        DraftEnvelope(
            userText: text,
            operation: operation.operation,
            operationConfidence: operation.confidence,
            automation: AutomationDraftSection(),
            risk: RiskSection(level: .medium, floorReason: "Unable to parse automation structure"),
            provenance: [.operation: .rules, .riskLevel: .rules],
            fieldConfidence: [.operation: operation.confidence, .riskLevel: 0.3]
        )
    }

    private func resolveTriggerDeterministically(
        _ component: AutomationTriggerComponent?
    ) async -> TriggerDraft? {
        guard let component else { return nil }
        let worker = AutomationTriggerResolutionWorkerSession(
            foundationModelAvailability: { false }
        )
        let input = AutomationTriggerResolutionInput(
            component: component,
            fullUserText: component.rawText
        )
        guard let output = try? await worker.resolve(input),
              let trigger = output.trigger else {
            return TriggerDraft(type: .schedule, confidence: 0.0)
        }

        switch trigger {
        case .schedule(let schedule):
            return TriggerDraft(
                type: .schedule,
                time: schedule.timeOfDay,
                repeatRule: schedule.repeatRule,
                timezoneIdentifier: schedule.timezoneIdentifier,
                confidence: output.confidence
            )
        case .device(let deviceTrigger):
            return TriggerDraft(
                type: .device,
                deviceDescription: deviceTrigger.description,
                confidence: output.confidence
            )
        }
    }

    private func conditionLeafDrafts(
        from components: [AutomationConditionComponent],
        devices: [HomeCandidateRecord],
        normalized: String
    ) -> [ConditionLeafDraft] {
        components.map { component in
            let leafNormalized = component.rawText.agentNormalizedHomeTokenString
            let stateValue = parseConditionStateValue(leafNormalized)
            let ruleIntent = AgentRuleIntent(normalized: leafNormalized)

            var candidateTable: [CompactCandidate] = []
            var target: String? = nil
            var confidence: Double = 0.3

            if let ruleIntent {
                let ranking = RuleCandidateScorer.rank(
                    devices: devices,
                    intent: ruleIntent,
                    normalized: leafNormalized
                )
                candidateTable = ranking.scored.prefix(5).map { CompactCandidate(from: $0.device) }
                if let sel = ranking.selected, !ranking.isAmbiguous {
                    target = sel.device.id
                    confidence = ranking.confidence
                }
            }

            return ConditionLeafDraft(
                id: component.id,
                rawText: component.rawText,
                target: target,
                candidateTable: candidateTable,
                capability: stateValue?.capability,
                attribute: stateValue?.attribute,
                operatorName: stateValue?.operatorName,
                value: stateValue?.value,
                confidence: confidence
            )
        }
    }

    private struct ConditionStateValue {
        let capability: String?
        let attribute: String?
        let operatorName: HomeAutomationComparisonOperator?
        let value: String?
    }

    private func parseConditionStateValue(_ normalized: String) -> ConditionStateValue? {
        if normalized.contains(" is on") || normalized.contains(" is off") {
            let value = normalized.contains(" is on") ? "on" : "off"
            return ConditionStateValue(
                capability: "switch",
                attribute: "switch",
                operatorName: .equals,
                value: value
            )
        }
        if normalized.contains(" is open") || normalized.contains(" is closed") {
            let value = normalized.contains(" is open") ? "open" : "closed"
            return ConditionStateValue(
                capability: "contactSensor",
                attribute: "contact",
                operatorName: .equals,
                value: value
            )
        }
        if normalized.contains(" is locked") || normalized.contains(" is unlocked") {
            let value = normalized.contains(" is locked") ? "locked" : "unlocked"
            return ConditionStateValue(
                capability: "lock",
                attribute: "lock",
                operatorName: .equals,
                value: value
            )
        }
        return nil
    }

    private func hasPrecedenceAmbiguity(_ text: String) -> Bool {
        let normalized = AutomationPatternParser.normalized(text)
        let split = AutomationPatternParser.splitCondition(from: text)
        let conditionText = split.conditionText ?? normalized
        let condNormalized = AutomationPatternParser.normalized(conditionText)
        return condNormalized.contains(" and ") && condNormalized.contains(" or ")
    }

    private func remapCommandField(_ field: FieldID, toActionIndex i: Int) -> FieldID? {
        switch field.rawValue {
        case "command.targetDeviceID": return .action(i, .targetDeviceID)
        case "command.capability": return .action(i, .capability)
        case "command.commandName": return .action(i, .commandName)
        case "command.room": return .action(i, .room)
        case "command.parameters": return .action(i, .parameters)
        default: return nil
        }
    }

    private func countGroups(_ tree: ConditionTreeDraft) -> Int {
        switch tree {
        case .leaf:
            return 0
        case .and(let children), .or(let children):
            return 1 + children.map { countGroups($0) }.reduce(0, +)
        case .not(let child):
            return countGroups(child)
        }
    }
}
