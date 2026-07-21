import Foundation
import HomeAutomationAgents
import HomeAutomationCore

extension GraphScheduler {
    func measuredSnapshot(
        contextStore: ResolutionContextStore,
        graph: OrchestrationGraph,
        runID: UUID,
        metrics: GraphRunMetricsRecorder,
        stage: String
    ) async -> ResolutionContext {
        let start = Date()
        let context = await contextStore.snapshot()
        let duration = Date().timeIntervalSince(start)
        await metrics.recordSnapshot(duration: duration, contextKeyCount: context.contextKeyCount)
        await HomeAutomationTelemetry.shared.log(
            "context.snapshot",
            context: HomeAutomationTelemetryScope.current?.merging(
                spanKind: .event,
                runID: runID.uuidString,
                operation: graph.goal.rawValue,
                graphID: graph.id,
                stage: stage
            ),
            status: .completed,
            durationMs: duration * 1_000,
            payload: TelemetryPayload(values: [
                "contextKeyCount": .int(context.contextKeyCount)
            ])
        )
        return context
    }

    func resumeNodeIDs(
        from checkpoint: GraphCheckpointRecord?,
        graph: OrchestrationGraph,
        runID: UUID
    ) -> Set<String> {
        guard let checkpoint,
              checkpoint.runID == runID.uuidString,
              checkpoint.graphID == graph.id else {
            return []
        }
        return Set(checkpoint.completedNodeIDs)
    }

    func saveCheckpoint(
        options: GraphSchedulerExecutionOptions,
        graph: OrchestrationGraph,
        runID: UUID,
        dependencies: GraphDependencyTracker,
        context: ResolutionContext,
        lastCompletedNodeID: String?
    ) async {
        guard let checkpointStore = options.checkpointStore else { return }
        let checkpoint = await makeCheckpoint(
            graph: graph,
            runID: runID,
            dependencies: dependencies,
            context: context,
            lastCompletedNodeID: lastCompletedNodeID
        )
        await checkpointStore.save(checkpoint)
    }

    func makeCheckpoint(
        graph: OrchestrationGraph,
        runID: UUID,
        dependencies: GraphDependencyTracker,
        context: ResolutionContext,
        lastCompletedNodeID: String?,
        interruptedBeforeNodeID: String? = nil,
        interrupt: GraphInterrupt? = nil
    ) async -> GraphCheckpointRecord {
        GraphCheckpointRecord(
            runID: runID.uuidString,
            graphID: graph.id,
            goal: graph.goal.rawValue,
            completedNodeIDs: Array(dependencies.completedNodeIDs),
            pendingNodeIDs: Array(dependencies.pendingNodeIDs),
            lastCompletedNodeID: lastCompletedNodeID,
            interruptedBeforeNodeID: interruptedBeforeNodeID,
            interrupt: interrupt,
            contextKeys: contextKeys(in: context)
        )
    }

    func contextKeys(in context: ResolutionContext) -> [String] {
        var keys: [String] = ["request.text", "request.executeLowRiskCommands"]
        if context.operation != nil { keys.append(ResolutionContextPatchKey.operation.rawValue) }
        if context.language != nil { keys.append(ResolutionContextPatchKey.language.rawValue) }
        if context.domain != nil { keys.append(ResolutionContextPatchKey.domain.rawValue) }
        if context.intent != nil { keys.append(ResolutionContextPatchKey.intent.rawValue) }
        if context.deviceType != nil { keys.append(ResolutionContextPatchKey.deviceType.rawValue) }
        if context.slots != nil { keys.append(ResolutionContextPatchKey.slots.rawValue) }
        if context.risk != nil { keys.append(ResolutionContextPatchKey.risk.rawValue) }
        if context.resolutionState != nil { keys.append(ResolutionContextPatchKey.resolutionState.rawValue) }
        if !context.retrievedCandidates.isEmpty { keys.append(ResolutionContextPatchKey.retrievedCandidates.rawValue) }
        if !context.selectedCandidateIDs.isEmpty { keys.append(ResolutionContextPatchKey.selectedCandidateIDs.rawValue) }
        if context.aggregation != nil { keys.append(ResolutionContextPatchKey.aggregation.rawValue) }
        if !context.hydratedCandidates.isEmpty { keys.append(ResolutionContextPatchKey.hydratedCandidates.rawValue) }
        if context.capabilityDecision != nil { keys.append(ResolutionContextPatchKey.capabilityDecision.rawValue) }
        if !context.knowledgeSnippets.isEmpty { keys.append(ResolutionContextPatchKey.knowledgeSnippets.rawValue) }
        if !context.retrievalReports.isEmpty { keys.append(ResolutionContextPatchKey.retrievalReports.rawValue) }
        if !context.memoryHints.isEmpty { keys.append("memoryHints") }
        if context.instructionPackage != nil { keys.append(ResolutionContextPatchKey.instructionPackage.rawValue) }
        if context.draft != nil { keys.append(ResolutionContextPatchKey.draft.rawValue) }
        if context.executionPlan != nil { keys.append(ResolutionContextPatchKey.executionPlan.rawValue) }
        if context.resolution != nil { keys.append(ResolutionContextPatchKey.resolution.rawValue) }
        for (scope, values) in context.scopedValues {
            for key in values.keys {
                keys.append("scope.\(scope.description).\(key)")
            }
        }
        return keys
    }
}
