import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public struct GraphSubgraphDescriptor: Sendable, Hashable {
    public let id: String
    public let parentNodeID: String
    public let scopeID: String
    public let inputSummary: String

    public init(
        id: String,
        parentNodeID: String,
        scopeID: String,
        inputSummary: String
    ) {
        self.id = id
        self.parentNodeID = parentNodeID
        self.scopeID = scopeID
        self.inputSummary = inputSummary
    }
}

public struct GraphSubgraphSchedulerResult: Sendable {
    public let descriptor: GraphSubgraphDescriptor
    public let schedulerResult: GraphSchedulerResult
    public let summary: HomeAutomationSubgraphRunSummary

    public init(
        descriptor: GraphSubgraphDescriptor,
        schedulerResult: GraphSchedulerResult,
        summary: HomeAutomationSubgraphRunSummary
    ) {
        self.descriptor = descriptor
        self.schedulerResult = schedulerResult
        self.summary = summary
    }
}

public struct GraphSubgraphRunner: Sendable {
    public init() {}

    public func execute(
        descriptor: GraphSubgraphDescriptor,
        graph: OrchestrationGraph,
        registry: AgentRegistry,
        contextStore: ResolutionContextStore,
        eventBus: AgentEventBus,
        policy: OrchestratorPolicyEngine,
        circuitBreakers: CircuitBreakerRegistry,
        runID: UUID
    ) async -> GraphSubgraphSchedulerResult {
        let result = await GraphScheduler().execute(
            graph,
            registry: registry,
            contextStore: contextStore,
            eventBus: eventBus,
            policy: policy,
            circuitBreakers: circuitBreakers,
            runID: runID
        )
        return GraphSubgraphSchedulerResult(
            descriptor: descriptor,
            schedulerResult: result,
            summary: Self.summary(
                from: result.metrics,
                descriptor: descriptor
            )
        )
    }

    public static func summary(
        from metrics: GraphRunMetrics,
        descriptor: GraphSubgraphDescriptor
    ) -> HomeAutomationSubgraphRunSummary {
        HomeAutomationSubgraphRunSummary(
            id: descriptor.id,
            parentNodeID: descriptor.parentNodeID,
            scopeID: descriptor.scopeID,
            graphID: metrics.graphID,
            goal: metrics.goal,
            nodeStatuses: metrics.nodeStatuses.mapValues(\.rawValue),
            selectedAgents: metrics.selectedAgents,
            skippedNodeIDs: metrics.skippedNodeIDs,
            nodeDurations: metrics.nodeDurations
        )
    }
}
