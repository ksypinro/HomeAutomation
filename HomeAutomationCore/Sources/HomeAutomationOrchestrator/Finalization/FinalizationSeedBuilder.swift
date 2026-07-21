import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public enum FinalizationSeedError: Error, Sendable, Hashable, CustomStringConvertible {
    case unsupportedOperation(HomeAutomationOperationKind)
    case missingCommandDraft
    case missingAutomationDraft

    public var description: String {
        switch self {
        case .unsupportedOperation(let operation):
            return "Cannot seed finalization for operation '\(operation.rawValue)'."
        case .missingCommandDraft:
            return "Cannot seed direct-command finalization without a command draft."
        case .missingAutomationDraft:
            return "Cannot seed automation finalization without an automation draft."
        }
    }
}

public struct FinalizationSeedBuilder: Sendable {
    private let deviceRegistry: any DeviceRegistryProtocol

    public init(deviceRegistry: any DeviceRegistryProtocol) {
        self.deviceRegistry = deviceRegistry
    }

    public func seed(
        envelope: DraftEnvelope,
        into store: ResolutionContextStore,
        operationHint: HomeOperationDetectionResult? = nil
    ) async throws {
        await store.setArtifact(envelope, for: ContextArtifactKeys.draftEnvelope())
        let operation = operationHint ?? operationResult(from: envelope)
        await store.setOperation(operation)
        let state = resolutionState(from: envelope, operation: operation)
        await store.setResolutionState(state)

        switch envelope.operation {
        case .executeDeviceCommand:
            try await seedDirectCommand(envelope: envelope, state: state, into: store)
        case .automationCreation:
            try await seedAutomation(envelope: envelope, state: state, into: store)
        case .automationUpdate,
             .automationDeletion,
             .automationQuery,
             .sceneCreation,
             .routineExecution,
             .unsupported:
            throw FinalizationSeedError.unsupportedOperation(envelope.operation)
        }
    }

    private func seedDirectCommand(
        envelope: DraftEnvelope,
        state: HomeResolutionState,
        into store: ResolutionContextStore
    ) async throws {
        guard let draft = StructuralDraftBuilder.commandDraft(from: envelope.command, risk: envelope.risk) else {
            throw FinalizationSeedError.missingCommandDraft
        }

        let candidates = await hydratedCandidates(from: candidateRecords(from: envelope))
        let selectedIDs = draft.targetDeviceID.map { [$0] } ?? []
        let aggregation = HomeCandidateAggregationResult(
            finalCandidateIDs: selectedIDs,
            needsClarification: draft.needsClarification,
            clarificationQuestion: draft.clarificationQuestion,
            confidence: draft.confidence
        )
        let capabilityDecision = HomeCapabilityDecision(
            selectedCapability: draft.capability,
            selectedCommand: draft.command,
            targetDeviceID: draft.targetDeviceID,
            alternatives: [],
            evidence: ["seeded-from-verifier-loop-envelope"],
            confidence: draft.confidence
        )

        await store.setDraft(draft)
        await store.setRetrievedCandidates(candidates)
        await store.setHydratedCandidates(candidates)
        await store.setSelectedCandidateIDs(selectedIDs)
        await store.setAggregation(aggregation)
        await store.setCapabilityDecision(capabilityDecision)
        await store.setRisk(state.risk)
        await store.setScopedValue(draft, for: ScopedContextKeys.commandDraft(in: .root))
        await store.setArtifact(draft, for: ContextArtifactKeys.commandDraft(in: .root))
    }

    private func seedAutomation(
        envelope: DraftEnvelope,
        state: HomeResolutionState,
        into store: ResolutionContextStore
    ) async throws {
        guard envelope.automation != nil else {
            throw FinalizationSeedError.missingAutomationDraft
        }

        let plan = StructuralDraftBuilder.automationCreationPlan(from: envelope)
        let candidates = await hydratedCandidates(from: candidateRecords(from: envelope))
        let selectedIDs = stableUnique(plan.resolvedActions.compactMap(\.draft.targetDeviceID))
        let aggregation = HomeCandidateAggregationResult(
            finalCandidateIDs: selectedIDs,
            needsClarification: plan.resolvedActions.contains { $0.draft.needsClarification },
            clarificationQuestion: plan.resolvedActions.compactMap(\.draft.clarificationQuestion).first,
            confidence: plan.resolvedActions.map(\.confidence).min() ?? envelope.operationConfidence
        )
        let records = conditionRecords(from: plan.ruleDraft)
        let actionAggregate = AutomationActionResolutionAggregate(
            actionDescriptions: plan.ruleDraft.actionDescriptions,
            results: plan.resolvedActions.map { action in
                let selected = action.draft.targetDeviceID.map { [$0] } ?? []
                return AutomationActionResolutionResult(
                    resolvedAction: action,
                    retrievedCandidates: action.device.map { [$0] } ?? [],
                    hydratedCandidates: action.device.map { [$0] } ?? [],
                    selectedCandidateIDs: selected,
                    draft: action.draft,
                    resolution: action.draft.needsClarification
                        ? .needsClarification(action.draft.clarificationQuestion ?? "Which device do you want to control?")
                        : .readyToExecute(
                            HomeAutomationExecutionPlan(
                                steps: [
                                    HomeAutomationExecutionStep(
                                        type: "command",
                                        deviceID: action.draft.targetDeviceID ?? "",
                                        deviceName: action.device?.displayName ?? action.draft.targetDeviceID ?? "",
                                        capability: action.draft.capability ?? "",
                                        command: action.draft.command ?? "",
                                        value: action.draft.parameters.first?.value
                                            ?? action.draft.parameters.first?.numericValue.map { String($0) },
                                        attribute: action.draft.parameters.first?.name
                                    )
                                ],
                                requiresConfirmation: action.draft.requiresConfirmation
                            )
                        ),
                    aggregation: HomeCandidateAggregationResult(
                        finalCandidateIDs: selected,
                        needsClarification: action.draft.needsClarification,
                        clarificationQuestion: action.draft.clarificationQuestion,
                        confidence: action.confidence
                    )
                )
            }
        )

        await store.setRetrievedCandidates(candidates)
        await store.setHydratedCandidates(candidates)
        await store.setSelectedCandidateIDs(selectedIDs)
        await store.setAggregation(aggregation)
        await store.setRisk(state.risk)
        await store.setScopedValue(plan.ruleDraft, for: ScopedContextKeys.automationRuleDraft())
        await store.setScopedValue(plan, for: ScopedContextKeys.automationPlan())
        await store.setScopedValue(actionAggregate, for: AutomationRuntimeContextKeys.actionResolutionAggregate)
        await store.setScopedValue(records, for: AutomationRuntimeContextKeys.conditionOperandResolutionRecords)
        await store.setArtifact(plan.ruleDraft, for: ContextArtifactKeys.automationRuleDraft())
        await store.setArtifact(plan, for: ContextArtifactKeys.automationPlan())
        await store.apply(
            ResolutionContextPatch(
                agentID: .deterministicDraftPipeline,
                scopedUpdates: [
                    .root: [
                        ResolutionContextPatchKey.automationResolvedActions.rawValue: AnySendableValue(plan.resolvedActions)
                    ]
                ]
            )
        )
    }

    private func operationResult(from envelope: DraftEnvelope) -> HomeOperationDetectionResult {
        HomeOperationDetectionResult(
            domain: .homeAutomation,
            operation: envelope.operation,
            confidence: envelope.operationConfidence,
            reason: "seeded from verifier-loop envelope"
        )
    }

    private func resolutionState(
        from envelope: DraftEnvelope,
        operation: HomeOperationDetectionResult
    ) -> HomeResolutionState {
        let baseline = HomeResolutionState.forOperation(text: envelope.userText, operation: operation)
        return HomeResolutionState(
            rawText: baseline.rawText,
            language: baseline.language,
            domain: baseline.domain,
            intent: baseline.intent,
            deviceType: baseline.deviceType,
            slots: baseline.slots,
            risk: HomeRiskClassificationResult(
                riskLevel: envelope.risk.level,
                requiresConfirmation: envelope.risk.level == .high || envelope.risk.level == .critical,
                reason: envelope.risk.floorReason,
                confidence: envelope.fieldConfidence[.riskLevel] ?? envelope.operationConfidence
            )
        )
    }

    private func candidateRecords(from envelope: DraftEnvelope) -> [HomeCandidateRecord] {
        let compactCandidates: [CompactCandidate]
        if let command = envelope.command {
            compactCandidates = command.candidateTable
        } else if let automation = envelope.automation {
            compactCandidates = automation.actions.flatMap(\.command.candidateTable)
                + automation.conditionLeaves.flatMap(\.candidateTable)
        } else {
            compactCandidates = []
        }

        return stableUnique(compactCandidates.map { compact in
            HomeCandidateRecord(
                id: compact.id,
                displayName: compact.name,
                deviceType: compact.deviceType,
                room: compact.room,
                capabilities: [],
                supportedCommands: [:]
            )
        })
    }

    private func hydratedCandidates(from candidates: [HomeCandidateRecord]) async -> [HomeCandidateRecord] {
        let devices = await deviceRegistry.allDevices()
        let byID = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
        return stableUnique(candidates.map { byID[$0.id] ?? $0 })
    }

    private func conditionRecords(from ruleDraft: HomeAutomationRuleDraft) -> [AutomationConditionOperandResolutionRecord] {
        var records: [AutomationConditionOperandResolutionRecord] = []
        if case .device(let trigger)? = ruleDraft.trigger {
            collectConditionRecords(trigger.condition, path: "trigger.condition", records: &records)
        }
        if let condition = ruleDraft.condition {
            collectConditionRecords(condition, path: "condition", records: &records)
        }
        return records
    }

    private func collectConditionRecords(
        _ condition: HomeAutomationCondition,
        path: String,
        records: inout [AutomationConditionOperandResolutionRecord]
    ) {
        switch condition {
        case .comparison(let comparison):
            appendRecord(comparison.left, path: "\(path).left", records: &records)
            appendRecord(comparison.right, path: "\(path).right", records: &records)
        case .and(let children), .or(let children):
            for (index, child) in children.enumerated() {
                collectConditionRecords(child, path: "\(path).\(index)", records: &records)
            }
        case .not(let child), .changes(let child):
            collectConditionRecords(child, path: "\(path).child", records: &records)
        }
    }

    private func appendRecord(
        _ operand: HomeAutomationConditionOperand,
        path: String,
        records: inout [AutomationConditionOperandResolutionRecord]
    ) {
        let order = records.count
        records.append(
            AutomationConditionOperandResolutionRecord(
                id: "seeded-c\(order + 1)",
                order: order,
                path: path,
                description: String(describing: operand),
                input: operand,
                output: operand
            )
        )
    }

    private func stableUnique(_ candidates: [HomeCandidateRecord]) -> [HomeCandidateRecord] {
        var seen = Set<String>()
        var result: [HomeCandidateRecord] = []
        for candidate in candidates where !seen.contains(candidate.id) {
            seen.insert(candidate.id)
            result.append(candidate)
        }
        return result
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
