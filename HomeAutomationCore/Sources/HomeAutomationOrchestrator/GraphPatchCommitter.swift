import Foundation
import HomeAutomationAgents
import HomeAutomationCore

extension GraphScheduler {
    func measuredApply(
        _ patch: ResolutionContextPatch,
        contextStore: ResolutionContextStore,
        graph: OrchestrationGraph,
        runID: UUID,
        metrics: GraphRunMetricsRecorder,
        stage: String
    ) async {
        let start = Date()
        await contextStore.apply(patch)
        let duration = Date().timeIntervalSince(start)
        await metrics.recordApply(duration: duration)
        await HomeAutomationTelemetry.shared.log(
            "context.apply",
            context: HomeAutomationTelemetryScope.current?.merging(
                runID: runID.uuidString,
                operation: graph.goal.rawValue,
                graphID: graph.id,
                stage: stage,
                graphNodeID: stage,
                agentID: patch.agentID.rawValue
            ),
            status: "completed",
            durationMs: duration * 1_000,
            payload: [
                "updateCount": String(patch.updates.count),
                "scopedUpdateCount": String(patch.scopedUpdates.values.reduce(0) { $0 + $1.count }),
                "hasTransitionRequest": String(patch.transitionRequest != nil)
            ]
        )
    }
}
