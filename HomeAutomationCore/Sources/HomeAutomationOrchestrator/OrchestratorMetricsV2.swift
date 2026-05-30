import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public struct AgentAttemptMetrics: Sendable, Codable, Equatable, Hashable {
    public let agentID: String
    public let invocationID: String
    public let status: String
    public let durationMs: Double
    public let retryCount: Int
    public let timeoutCount: Int
}

public struct ModelCallMetrics: Sendable, Codable, Equatable, Hashable {
    public let modelCallCount: Int
    public let skippedModelCallCount: Int
    public let contextWindowFailuresByAgent: [String: Int]
}

public struct ToolCallMetrics: Sendable, Codable, Equatable, Hashable {
    public let toolCount: Int
    public let estimatedToolOutputCharacterCount: Int
    public let selectedToolNames: [String]
}

public struct AutomationFanOutMetrics: Sendable, Codable, Equatable, Hashable {
    public let componentCount: Int
    public let triggerCount: Int
    public let actionCount: Int
    public let conditionCount: Int
    public let maxConcurrentComponents: Int
    public let componentStartSpreadMs: Double
    public let componentFanOutDurationMs: Double
    public let failedComponentIDs: [String]
}

public struct CandidateDecisionMetrics: Sendable, Codable, Equatable, Hashable {
    public let retrievedCandidateCount: Int
    public let hydratedCandidateCount: Int
    public let selectedCandidateIDs: [String]
    public let needsClarification: Bool
}

public struct GraphMetricsV2: Sendable, Codable, Equatable, Hashable {
    public let graphID: String
    public let statusByNodeID: [String: String]
    public let durationMsByNodeID: [String: Double]
    public let queueMsByNodeID: [String: Double]
    public let runnableBatchSizes: [Int]
    public let contextSnapshotMs: [Double]
    public let contextApplyMs: [Double]
    public let criticalPathDurationMs: Double
}

public struct RunMetricsV2: Sendable, Codable, Equatable, Hashable {
    public let source: String
    public let totalDurationMs: Double
    public let criticalPathDurationMs: Double
    public let retryCount: Int
    public let timeoutCount: Int
    public let cancellationCount: Int
    public let circuitBreakerOpenCount: Int
    public let graph: GraphMetricsV2?
    public let agentAttempts: [AgentAttemptMetrics]
    public let modelCalls: ModelCallMetrics
    public let toolCalls: ToolCallMetrics
    public let automationFanOut: AutomationFanOutMetrics?
    public let candidateDecision: CandidateDecisionMetrics

    public static func derive(from metrics: OrchestratorMetrics) -> RunMetricsV2 {
        let graph = metrics.graphRun.map(GraphMetricsV2.derive(from:))
        let attempts = metrics.agentTraces.map { trace in
            AgentAttemptMetrics(
                agentID: trace.agentID.rawValue,
                invocationID: "\(trace.agentID.rawValue)-\(Int(trace.startedAt.timeIntervalSince1970 * 1_000))",
                status: trace.result.rawValue,
                durationMs: trace.durationSeconds * 1_000,
                retryCount: trace.result == .retryableFailure ? 1 : 0,
                timeoutCount: trace.result == .retryableFailure ? 1 : 0
            )
        }
        let fanOut = metrics.automationMetrics.automationActionCount + metrics.automationMetrics.automationConditionCount > 0
            ? AutomationFanOutMetrics(
                componentCount: metrics.automationMetrics.automationActionCount + metrics.automationMetrics.automationConditionCount,
                triggerCount: metrics.automationMetrics.operation == nil ? 0 : 1,
                actionCount: metrics.automationMetrics.automationActionCount,
                conditionCount: metrics.automationMetrics.automationConditionCount,
                maxConcurrentComponents: metrics.graphRun?.runnableBatchSizes.max() ?? 0,
                componentStartSpreadMs: metrics.graphRun?.nodeQueueDurations.values.max() ?? 0,
                componentFanOutDurationMs: metrics.graphRun?.nodeDurations[AgentID.automationComponentFanOut.rawValue].map { $0 * 1_000 } ?? 0,
                failedComponentIDs: []
            )
            : nil
        return RunMetricsV2(
            source: "span-derived-v2",
            totalDurationMs: (metrics.totalDuration ?? metrics.finishedAt?.timeIntervalSince(metrics.startedAt) ?? 0) * 1_000,
            criticalPathDurationMs: graph?.criticalPathDurationMs ?? 0,
            retryCount: attempts.map(\.retryCount).reduce(0, +),
            timeoutCount: attempts.map(\.timeoutCount).reduce(0, +),
            cancellationCount: 0,
            circuitBreakerOpenCount: metrics.circuitStates.values.filter { $0.localizedCaseInsensitiveContains("open") }.count,
            graph: graph,
            agentAttempts: attempts,
            modelCalls: ModelCallMetrics(
                modelCallCount: metrics.foundationModelUsage.modelCallCount,
                skippedModelCallCount: metrics.foundationModelUsage.skippedModelCallCount,
                contextWindowFailuresByAgent: metrics.foundationModelUsage.contextWindowFailures == 0 ? [:] : ["unknown": metrics.foundationModelUsage.contextWindowFailures]
            ),
            toolCalls: ToolCallMetrics(
                toolCount: metrics.foundationModelUsage.toolCount,
                estimatedToolOutputCharacterCount: metrics.foundationModelUsage.estimatedToolOutputCharacterCount,
                selectedToolNames: metrics.foundationModelUsage.selectedToolNames
            ),
            automationFanOut: fanOut,
            candidateDecision: CandidateDecisionMetrics(
                retrievedCandidateCount: metrics.candidateMetrics.retrievedCandidateCount,
                hydratedCandidateCount: metrics.candidateMetrics.hydratedCandidateCount,
                selectedCandidateIDs: metrics.candidateMetrics.selectedCandidateIDs,
                needsClarification: metrics.candidateMetrics.needsClarification
            )
        )
    }
}

public extension GraphMetricsV2 {
    static func derive(from graphRun: GraphRunMetrics) -> GraphMetricsV2 {
        let durationValues = graphRun.nodeDurations.values.map { $0 * 1_000 }
        return GraphMetricsV2(
            graphID: graphRun.graphID,
            statusByNodeID: graphRun.nodeStatuses.mapValues(\.rawValue),
            durationMsByNodeID: graphRun.nodeDurations.mapValues { $0 * 1_000 },
            queueMsByNodeID: graphRun.nodeQueueDurations.mapValues { $0 * 1_000 },
            runnableBatchSizes: graphRun.runnableBatchSizes,
            contextSnapshotMs: graphRun.contextSnapshotDurations.map { $0 * 1_000 },
            contextApplyMs: graphRun.contextApplyDurations.map { $0 * 1_000 },
            criticalPathDurationMs: durationValues.max() ?? 0
        )
    }
}
