import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public enum LoopResultBridge {

    public static func bridgeToResult(
        exit: LoopExit,
        operationHint: HomeOperationDetectionResult?
    ) -> HomeAutomationResolverResult {
        switch exit {
        case .accepted(let envelope, _):
            return buildResult(from: envelope, operationHint: operationHint)

        case .clarification(let envelope, let question, _):
            let state = makeResolutionState(from: envelope, operationHint: operationHint)
            return HomeAutomationResolverResult(
                state: state,
                retrievedCandidates: candidateRecords(from: envelope),
                aggregation: makeAggregation(from: envelope),
                hydratedCandidates: candidateRecords(from: envelope),
                draft: nil,
                resolution: .needsClarification(question)
            )

        case .escalated(let envelope, _):
            return buildResult(from: envelope, operationHint: operationHint)
        }
    }

    public static func seedContext(
        _ envelope: DraftEnvelope,
        into store: ResolutionContextStore
    ) async {
        await store.setArtifact(envelope, for: ContextArtifactKeys.draftEnvelope())

        if let cmd = envelope.command {
            let draft = StructuralDraftBuilder.commandDraft(from: cmd, risk: envelope.risk)
            if let draft {
                await store.setScopedValue(draft, for: ScopedContextKeys.commandDraft(in: .root))
            }
        }
    }

    // MARK: - Private

    private static func buildResult(
        from envelope: DraftEnvelope,
        operationHint: HomeOperationDetectionResult?
    ) -> HomeAutomationResolverResult {
        let state = makeResolutionState(from: envelope, operationHint: operationHint)
        let candidates = candidateRecords(from: envelope)
        let aggregation = makeAggregation(from: envelope)

        if envelope.operation == .automationCreation {
            return makeAutomationResult(
                state: state,
                envelope: envelope,
                candidates: candidates,
                aggregation: aggregation
            )
        }

        let draft: HomeCommandDraft?
        if let cmd = envelope.command {
            draft = StructuralDraftBuilder.commandDraft(from: cmd, risk: envelope.risk)
        } else {
            draft = nil
        }

        let resolution: HomeCommandResolution
        if let draft {
            if draft.requiresConfirmation {
                resolution = .requiresConfirmation(draft)
            } else if draft.needsClarification, let question = draft.clarificationQuestion {
                resolution = .needsClarification(question)
            } else {
                let firstParam = draft.parameters.first
                let plan = HomeAutomationExecutionPlan(
                    steps: [
                        HomeAutomationExecutionStep(
                            type: "command",
                            deviceID: draft.targetDeviceID ?? "",
                            deviceName: draft.targetDeviceID ?? "",
                            capability: draft.capability ?? "",
                            command: draft.command ?? "",
                            value: firstParam?.value ?? firstParam?.numericValue.map { String($0) },
                            attribute: firstParam?.name
                        )
                    ],
                    requiresConfirmation: false
                )
                resolution = .readyToExecute(plan)
            }
        } else {
            resolution = .unsupported("Could not build a command draft from the envelope.")
        }

        return HomeAutomationResolverResult(
            state: state,
            retrievedCandidates: candidates,
            aggregation: aggregation,
            hydratedCandidates: candidates,
            draft: draft,
            resolution: resolution
        )
    }

    private static func makeAutomationResult(
        state: HomeResolutionState,
        envelope: DraftEnvelope,
        candidates: [HomeCandidateRecord],
        aggregation: HomeCandidateAggregationResult
    ) -> HomeAutomationResolverResult {
        let plan = StructuralDraftBuilder.automationCreationPlan(from: envelope)

        let resolution: HomeCommandResolution
        if let reason = plan.unsupportedCompilationReason, plan.smartThingsRuleJSON == nil {
            // The envelope couldn't be expressed as a SmartThings rule. Device
            // triggers are now compiled structurally (Phase 1), so this path is
            // reached only when a field is genuinely unresolvable — e.g. an
            // ambiguous device the deterministic parser and the `.trigger`/
            // `.conditionClause` repair specialists both left unresolved.
            resolution = .unsupported(reason)
        } else if plan.requiresConfirmation {
            resolution = .automationRequiresConfirmation(plan)
        } else {
            resolution = .automationDrafted(plan)
        }

        return HomeAutomationResolverResult(
            state: state,
            retrievedCandidates: candidates,
            aggregation: aggregation,
            hydratedCandidates: candidates,
            draft: nil,
            resolution: resolution
        )
    }

    private static func makeResolutionState(
        from envelope: DraftEnvelope,
        operationHint: HomeOperationDetectionResult?
    ) -> HomeResolutionState {
        let operation = operationHint ?? HomeOperationDetectionResult(
            domain: .homeAutomation,
            operation: envelope.operation,
            confidence: envelope.operationConfidence,
            reason: "from envelope"
        )
        return HomeResolutionState.forOperation(
            text: envelope.userText,
            operation: operation
        )
    }

    private static func candidateRecords(from envelope: DraftEnvelope) -> [HomeCandidateRecord] {
        let candidates: [CompactCandidate]
        if let cmd = envelope.command {
            candidates = cmd.candidateTable
        } else if let auto = envelope.automation {
            candidates = auto.actions.flatMap(\.command.candidateTable)
        } else {
            candidates = []
        }

        var seen = Set<String>()
        return candidates.compactMap { compact -> HomeCandidateRecord? in
            guard !seen.contains(compact.id) else { return nil }
            seen.insert(compact.id)
            return HomeCandidateRecord(
                id: compact.id,
                displayName: compact.name,
                deviceType: compact.deviceType,
                room: compact.room,
                capabilities: [],
                supportedCommands: [:]
            )
        }
    }

    private static func makeAggregation(from envelope: DraftEnvelope) -> HomeCandidateAggregationResult {
        let targetID = envelope.command?.targetDeviceID
        let needsClarification = targetID == nil && envelope.command != nil
        return HomeCandidateAggregationResult(
            finalCandidateIDs: targetID.map { [$0] } ?? [],
            needsClarification: needsClarification,
            clarificationQuestion: needsClarification ? envelope.clarification?.question : nil,
            confidence: envelope.command.map { cmd in
                cmd.targetDeviceID != nil ? 0.9 : 0.3
            } ?? 0.5
        )
    }
}
