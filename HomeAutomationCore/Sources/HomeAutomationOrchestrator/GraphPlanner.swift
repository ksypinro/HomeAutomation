import Foundation
import HomeAutomationAgents
import OSLog

public struct GraphExecutionPlan: Sendable, Hashable {
    public let graph: OrchestrationGraph
    public let isFallbackOnly: Bool

    public init(graph: OrchestrationGraph, isFallbackOnly: Bool = false) {
        self.graph = graph
        self.isFallbackOnly = isFallbackOnly
    }
}

public struct GraphPlanner: Sendable {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "GraphPlanner")
    private let policy: OrchestratorPolicyEngine

    public init(policy: OrchestratorPolicyEngine) {
        self.policy = policy
    }

    public func plan(for text: String, context: ResolutionContext) -> GraphExecutionPlan {
        logger.debug("Generating graph plan for text: '\(text, privacy: .private)'")

        guard policy.shouldUseModels() else {
            logger.warning("Models unavailable. Planning fallback graph.")
            return GraphExecutionPlan(graph: Self.fallbackGraph(), isFallbackOnly: true)
        }

        return GraphExecutionPlan(graph: Self.directCommandGraph())
    }

    public static func directCommandGraph() -> OrchestrationGraph {
        let phaseOne: [AgentID] = [
            .language,
            .domain,
            .intentFamily,
            .deviceType,
            .slotExtraction,
            .riskClassification
        ]
        let phaseTwo: [AgentID] = [
            .capabilityKnowledge,
            .bixbyKnowledge,
            .commandExample,
            .candidateRetrieval
        ]
        let sequential: [AgentID] = [
            .retrievalJudge,
            .candidateRanking,
            .candidateHydration,
            .instructionComposer,
            .draftGeneration,
            .safetyValidation,
            .parameterValidation,
            .confirmationPolicy,
            .executionPlanning
        ]

        let allAgents = phaseOne + phaseTwo + sequential
        let nodes = allAgents.map { id in
            GraphNode(
                id: id.rawValue,
                requirement: .byID(id),
                executionPolicy: executionPolicy(for: id)
            )
        }

        var edges: [GraphEdge] = []
        for first in phaseOne {
            for second in phaseTwo {
                edges.append(GraphEdge(from: first.rawValue, to: second.rawValue))
            }
        }
        for second in phaseTwo {
            edges.append(GraphEdge(from: second.rawValue, to: AgentID.retrievalJudge.rawValue))
        }
        for pair in zip(sequential, sequential.dropFirst()) {
            edges.append(GraphEdge(from: pair.0.rawValue, to: pair.1.rawValue))
        }

        return OrchestrationGraph(
            id: "direct-command-graph",
            goal: .executeDeviceCommand,
            nodes: nodes,
            edges: edges,
            entryNodeIDs: Set(phaseOne.map(\.rawValue))
        )
    }

    public static func fallbackGraph() -> OrchestrationGraph {
        let fallbackAgents: [AgentID] = [
            .ruleFallback,
            .bixbyFallback,
            .unsupportedCommand
        ]
        return OrchestrationGraph(
            id: "direct-command-fallback-graph",
            goal: .executeDeviceCommand,
            nodes: fallbackAgents.map { id in
                GraphNode(id: id.rawValue, requirement: .byID(id))
            },
            edges: [
                GraphEdge(from: AgentID.ruleFallback.rawValue, to: AgentID.bixbyFallback.rawValue),
                GraphEdge(from: AgentID.bixbyFallback.rawValue, to: AgentID.unsupportedCommand.rawValue)
            ],
            entryNodeIDs: [AgentID.ruleFallback.rawValue]
        )
    }

    private static func executionPolicy(for id: AgentID) -> NodeExecutionPolicy {
        switch id {
        case .safetyValidation, .parameterValidation, .confirmationPolicy:
            return .safetyGate
        default:
            return .required
        }
    }
}
