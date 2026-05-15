import Foundation
import HomeAutomationAgents

public enum OrchestratorRuntimeMode: String, Sendable, Hashable, Codable {
    case legacy
    case graph
}

public struct OrchestratorRuntimeConfiguration: Sendable, Hashable, Codable {
    public static let environmentVariableName = "HOME_AUTOMATION_ORCHESTRATOR_RUNTIME"
    public static let graphDefault = OrchestratorRuntimeConfiguration(runtimeMode: .graph)
    public static let legacyRollback = OrchestratorRuntimeConfiguration(runtimeMode: .legacy)

    public let runtimeMode: OrchestratorRuntimeMode

    public init(runtimeMode: OrchestratorRuntimeMode = .graph) {
        self.runtimeMode = runtimeMode
    }

    public static func resolving(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> OrchestratorRuntimeConfiguration {
        guard let rawValue = environment[environmentVariableName]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              let runtimeMode = OrchestratorRuntimeMode(rawValue: rawValue) else {
            return graphDefault
        }
        return OrchestratorRuntimeConfiguration(runtimeMode: runtimeMode)
    }
}

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

    public init(
        graphID: String,
        goal: OrchestrationGoal,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        nodeStatuses: [String: GraphNodeRunStatus] = [:],
        selectedAgents: [String: String] = [:],
        skippedNodeIDs: [String] = [],
        nodeDurations: [String: Double] = [:]
    ) {
        self.graphID = graphID
        self.goal = goal.rawValue
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.nodeStatuses = nodeStatuses
        self.selectedAgents = selectedAgents
        self.skippedNodeIDs = skippedNodeIDs
        self.nodeDurations = nodeDurations
    }
}

public struct GraphSchedulerResult: Sendable {
    public let exit: AgentRunResult?
    public let metrics: GraphRunMetrics

    public init(exit: AgentRunResult?, metrics: GraphRunMetrics) {
        self.exit = exit
        self.metrics = metrics
    }
}
