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
    public var nodeStatuses: [String: GraphNodeRunStatus]
    public var selectedAgents: [String: String]
    public var skippedNodeIDs: [String]
    public var nodeDurations: [String: Double]
    public var subgraphRuns: [HomeAutomationSubgraphRunSummary]

    public init(
        graphID: String,
        goal: OrchestrationGoal,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        nodeStatuses: [String: GraphNodeRunStatus] = [:],
        selectedAgents: [String: String] = [:],
        skippedNodeIDs: [String] = [],
        nodeDurations: [String: Double] = [:],
        subgraphRuns: [HomeAutomationSubgraphRunSummary] = []
    ) {
        self.graphID = graphID
        self.goal = goal.rawValue
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.nodeStatuses = nodeStatuses
        self.selectedAgents = selectedAgents
        self.skippedNodeIDs = skippedNodeIDs
        self.nodeDurations = nodeDurations
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
