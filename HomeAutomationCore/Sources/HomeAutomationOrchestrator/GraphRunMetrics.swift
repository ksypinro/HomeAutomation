import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public enum GraphNodeRunStatus: String, Sendable, Hashable, Codable {
    case pending
    case running
    case completed
    case failed
    case skipped
}

public struct GraphRunMetrics: Sendable, Hashable, Codable {
    public let graphID: String
    public let goal: String
    public let startedAt: Date
    public var finishedAt: Date?
    public var compilationReport: GraphCompilationReport?
    public var criticalPath: GraphCriticalPathMetadata?
    public var nodeStatuses: [String: GraphNodeRunStatus]
    public var selectedAgents: [String: String]
    public var skippedNodeIDs: [String]
    public var nodeDurations: [String: Double]
    public var nodeQueueDurations: [String: Double]
    public var contextSnapshotDurations: [Double]
    public var contextApplyDurations: [Double]
    public var runnableBatchSizes: [Int]
    public var contextKeyCounts: [Int]
    public var transitionDecisions: [String]
    public var subgraphRuns: [HomeAutomationSubgraphRunSummary]

    public init(
        graphID: String,
        goal: OrchestrationGoal,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        compilationReport: GraphCompilationReport? = nil,
        criticalPath: GraphCriticalPathMetadata? = nil,
        nodeStatuses: [String: GraphNodeRunStatus] = [:],
        selectedAgents: [String: String] = [:],
        skippedNodeIDs: [String] = [],
        nodeDurations: [String: Double] = [:],
        nodeQueueDurations: [String: Double] = [:],
        contextSnapshotDurations: [Double] = [],
        contextApplyDurations: [Double] = [],
        runnableBatchSizes: [Int] = [],
        contextKeyCounts: [Int] = [],
        transitionDecisions: [String] = [],
        subgraphRuns: [HomeAutomationSubgraphRunSummary] = []
    ) {
        self.graphID = graphID
        self.goal = goal.rawValue
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.compilationReport = compilationReport
        self.criticalPath = criticalPath
        self.nodeStatuses = nodeStatuses
        self.selectedAgents = selectedAgents
        self.skippedNodeIDs = skippedNodeIDs
        self.nodeDurations = nodeDurations
        self.nodeQueueDurations = nodeQueueDurations
        self.contextSnapshotDurations = contextSnapshotDurations
        self.contextApplyDurations = contextApplyDurations
        self.runnableBatchSizes = runnableBatchSizes
        self.contextKeyCounts = contextKeyCounts
        self.transitionDecisions = transitionDecisions
        self.subgraphRuns = subgraphRuns
    }
}

public struct GraphSchedulerResult: Sendable {
    public let exit: AgentRunResult?
    public let metrics: GraphRunMetrics
    public let interruption: GraphCheckpointRecord?

    public init(
        exit: AgentRunResult?,
        metrics: GraphRunMetrics,
        interruption: GraphCheckpointRecord? = nil
    ) {
        self.exit = exit
        self.metrics = metrics
        self.interruption = interruption
    }
}
