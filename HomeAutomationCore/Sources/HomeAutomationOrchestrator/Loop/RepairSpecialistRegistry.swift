import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public struct RepairSpecialistRegistry: Sendable {
    public let execute: @Sendable (RepairPlanner.RepairStep, DraftEnvelope) async -> RepairResult?

    public init(
        execute: @escaping @Sendable (RepairPlanner.RepairStep, DraftEnvelope) async -> RepairResult?
    ) {
        self.execute = execute
    }

    public init(
        fragmentNLU: FragmentNLUWorkerSession,
        targetResolver: ActionTargetResolver,
        riskAssessor: AutomationRiskAssessor,
        capabilityWorker: CapabilityResolutionWorker? = nil,
        triggerWorker: AutomationTriggerResolutionWorkerSession? = nil,
        conditionClauseWorker: AutomationConditionClauseResolutionWorkerSession? = nil,
        batchedConditionResolver: BatchedConditionClauseResolver? = nil,
        segmentationWorker: AutomationComponentSegmentationWorkerSession? = nil,
        deviceRegistry: (any DeviceRegistryProtocol)? = nil,
        operationDetection: @escaping @Sendable (String) async -> HomeOperationDetectionResult?
    ) {
        self.execute = { @Sendable step, envelope in
            switch step.specialist {
            case .operationDetection:
                guard let result = await operationDetection(envelope.userText) else { return nil }
                return .operation(result)

            case .fragmentNLU:
                let actionIndex = step.fieldIDs.first.flatMap { fieldID -> Int? in
                    guard let match = fieldID.rawValue.firstMatch(of: /automation\.actions\[(\d+)\]/) else { return nil }
                    return Int(match.output.1)
                }
                let text: String
                if let idx = actionIndex, let auto = envelope.automation, idx < auto.actions.count {
                    text = auto.actions[idx].rawText
                } else {
                    text = envelope.userText
                }
                guard let output = try? await fragmentNLU.analyze(text) else { return nil }
                return .fragmentNLU(actionIndex: actionIndex, output)

            case .target:
                guard let fieldID = step.fieldIDs.first else { return nil }
                let hint = step.disputes.first?.suggestedValue
                let candidates: [CompactCandidate]
                let fragmentText: String

                if fieldID.rawValue.hasPrefix("command.") {
                    candidates = envelope.command?.candidateTable ?? []
                    fragmentText = envelope.userText
                } else if let match = fieldID.rawValue.firstMatch(of: /automation\.actions\[(\d+)\]/),
                          let idx = Int(match.output.1),
                          let auto = envelope.automation, idx < auto.actions.count {
                    candidates = auto.actions[idx].command.candidateTable
                    fragmentText = auto.actions[idx].rawText
                } else {
                    return nil
                }

                let result = await targetResolver.resolve(
                    fragmentText: fragmentText,
                    candidates: candidates,
                    hint: hint
                )
                return .target(fieldID: fieldID, result)

            case .capability:
                guard let capabilityWorker, let fieldID = step.fieldIDs.first else { return nil }

                let fragmentText: String
                let candidates: [CompactCandidate]
                let targetDeviceID: String?

                if fieldID.rawValue.hasPrefix("command.") {
                    fragmentText = envelope.userText
                    candidates = envelope.command?.candidateTable ?? []
                    targetDeviceID = envelope.command?.targetDeviceID
                } else if let match = fieldID.rawValue.firstMatch(of: /automation\.actions\[(\d+)\]/),
                          let idx = Int(match.output.1),
                          let auto = envelope.automation, idx < auto.actions.count {
                    fragmentText = auto.actions[idx].rawText
                    candidates = auto.actions[idx].command.candidateTable
                    targetDeviceID = auto.actions[idx].command.targetDeviceID
                } else {
                    return nil
                }

                let records = candidates.map { compact in
                    HomeCandidateRecord(
                        id: compact.id,
                        displayName: compact.name,
                        deviceType: compact.deviceType,
                        room: compact.room,
                        capabilities: [],
                        supportedCommands: [:]
                    )
                }
                let input = CapabilityResolutionInput(
                    rawText: fragmentText,
                    resolutionState: AgentTextParser.deterministicState(for: fragmentText),
                    hydratedCandidates: records,
                    aggregation: HomeCandidateAggregationResult(
                        finalCandidateIDs: targetDeviceID.map { [$0] } ?? [],
                        needsClarification: false,
                        confidence: targetDeviceID != nil ? 0.9 : 0.3
                    ),
                    knowledgeSnippets: []
                )
                guard let decision = try? await capabilityWorker.resolve(input) else { return nil }
                return .capability(fieldID: fieldID, decision)

            case .riskRaise:
                let risk = riskAssessor.assess(envelope: envelope)
                let result = HomeRiskClassificationResult(
                    riskLevel: risk.level,
                    requiresConfirmation: risk.level == .high || risk.level == .critical,
                    reason: risk.floorReason,
                    confidence: 0.9
                )
                return .riskRaise(result)

            case .trigger:
                guard let triggerWorker else { return nil }
                return await repairTrigger(
                    envelope: envelope,
                    triggerWorker: triggerWorker,
                    conditionClauseWorker: conditionClauseWorker,
                    deviceRegistry: deviceRegistry
                )

            case .conditionClause:
                guard let conditionClauseWorker, let deviceRegistry else { return nil }
                return await repairConditionClauses(
                    step: step,
                    envelope: envelope,
                    conditionClauseWorker: conditionClauseWorker,
                    batchedConditionResolver: batchedConditionResolver,
                    deviceRegistry: deviceRegistry
                )

            case .segmentation:
                guard let segmentationWorker else { return nil }
                guard let plan = try? await segmentationWorker.segment(envelope.userText) else { return nil }
                return .segmentation(plan)

            case .holisticDraft:
                // Intentionally unsupported: no holistic-draft specialist exists
                // by design. A dispute that reaches here means the deterministic
                // draft is structurally unrecoverable field-by-field, so the loop
                // escalates to the legacy graph path (which owns whole-draft
                // regeneration). See GapClosureImplementationPlan.md §"Explicitly
                // out of scope".
                return nil
            }
        }
    }
}

// MARK: - Automation repair specialists (H6)

/// Re-resolves the automation trigger from its segmented fragment (or, absent a
/// retained fragment, by re-segmenting the full command). For device triggers
/// the condition operands are resolved so the merged trigger is compilable.
private func repairTrigger(
    envelope: DraftEnvelope,
    triggerWorker: AutomationTriggerResolutionWorkerSession,
    conditionClauseWorker: AutomationConditionClauseResolutionWorkerSession?,
    deviceRegistry: (any DeviceRegistryProtocol)?
) async -> RepairResult? {
    let component: AutomationTriggerComponent
    if let rawText = envelope.automation?.trigger?.rawText, !rawText.isEmpty {
        let kindHint: AutomationTriggerKindHint =
            envelope.automation?.trigger?.type == .device ? .device : .schedule
        component = AutomationTriggerComponent(id: "t1", rawText: rawText, kindHint: kindHint)
    } else if let fromPlan = AutomationPatternParserHintTool.fallbackPlan(for: envelope.userText)?.trigger {
        component = fromPlan
    } else {
        return nil
    }

    let input = AutomationTriggerResolutionInput(
        component: component,
        fullUserText: envelope.userText
    )
    guard let output = try? await triggerWorker.resolve(input), let trigger = output.trigger else {
        return nil
    }

    guard case .device(let deviceTrigger) = trigger else {
        return .trigger(output)
    }

    // Resolve the device-trigger condition operands (deviceID/capability/
    // attribute) so the merged trigger compiles.
    let devices = await (deviceRegistry?.allDevices() ?? [])
    let resolvedCondition = await resolveDeviceTriggerCondition(
        component: component,
        fallback: deviceTrigger.condition,
        devices: devices,
        conditionClauseWorker: conditionClauseWorker
    )
    return .trigger(
        AutomationTriggerResolutionOutput(
            id: output.id,
            trigger: .device(
                HomeAutomationDeviceTrigger(
                    description: deviceTrigger.description,
                    condition: resolvedCondition
                )
            ),
            confidence: output.confidence,
            unsupportedFragments: output.unsupportedFragments
        )
    )
}

private func resolveDeviceTriggerCondition(
    component: AutomationTriggerComponent,
    fallback: HomeAutomationCondition,
    devices: [HomeCandidateRecord],
    conditionClauseWorker: AutomationConditionClauseResolutionWorkerSession?
) async -> HomeAutomationCondition {
    guard let conditionClauseWorker, !devices.isEmpty else { return fallback }
    let input = AutomationConditionClauseResolutionInput(
        component: AutomationConditionComponent(
            id: component.id,
            rawText: component.rawText,
            order: 0
        ),
        fullUserText: component.rawText,
        availableDevices: devices,
        triggerPolicy: .always
    )
    if let result = try? await conditionClauseWorker.resolve(input), let condition = result.condition {
        return condition
    }
    return fallback
}

/// Re-resolves the disputed condition leaves. Uses the batched resolver when two
/// or more leaves are disputed (reusing Phase III batching), otherwise the
/// single-clause worker. Merges are applied per leaf.
private func repairConditionClauses(
    step: RepairPlanner.RepairStep,
    envelope: DraftEnvelope,
    conditionClauseWorker: AutomationConditionClauseResolutionWorkerSession,
    batchedConditionResolver: BatchedConditionClauseResolver?,
    deviceRegistry: any DeviceRegistryProtocol
) async -> RepairResult? {
    guard let auto = envelope.automation else { return nil }
    let indices = disputedConditionLeafIndices(step.fieldIDs)
        .filter { $0 < auto.conditionLeaves.count }
    guard !indices.isEmpty else { return nil }

    let devices = await deviceRegistry.allDevices()
    let triggerPolicy: HomeAutomationConditionTriggerPolicy =
        auto.trigger?.type == .device ? .always : .never

    let inputs: [(index: Int, input: AutomationConditionClauseResolutionInput)] = indices.map { idx in
        let leaf = auto.conditionLeaves[idx]
        return (
            idx,
            AutomationConditionClauseResolutionInput(
                component: AutomationConditionComponent(id: leaf.id, rawText: leaf.rawText, order: idx),
                fullUserText: envelope.userText,
                availableDevices: devices,
                triggerPolicy: triggerPolicy
            )
        )
    }

    if inputs.count >= 2, let batchedConditionResolver {
        let results = await batchedConditionResolver.resolveAll(inputs.map(\.input))
        let merged = zip(inputs.map(\.index), results).map { (index: $0, result: $1) }
        return .conditionClauses(merged)
    }

    let first = inputs[0]
    guard let result = try? await conditionClauseWorker.resolve(first.input) else { return nil }
    return .conditionClause(index: first.index, result)
}

private func disputedConditionLeafIndices(_ fieldIDs: [FieldID]) -> [Int] {
    var seen = Set<Int>()
    var ordered: [Int] = []
    for fieldID in fieldIDs {
        guard let match = fieldID.rawValue.firstMatch(of: /automation\.conditionLeaves\[(\d+)\]/),
              let index = Int(match.output.1),
              !seen.contains(index) else { continue }
        seen.insert(index)
        ordered.append(index)
    }
    return ordered.sorted()
}
