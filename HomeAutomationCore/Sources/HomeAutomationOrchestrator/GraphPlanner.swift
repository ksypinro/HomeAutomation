import Foundation
import HomeAutomationAgents
import HomeAutomationCore
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
    private let catalog: OperationGraphCatalog

    public init(policy: OrchestratorPolicyEngine) {
        self.init(catalog: .defaultCatalog(policy: policy))
    }

    public init(catalog: OperationGraphCatalog) {
        self.catalog = catalog
    }

    public func plan(for text: String, context: ResolutionContext) -> GraphExecutionPlan {
        logger.debug("Generating graph plan for text: '\(text, privacy: .private)'")
        return catalog.plan(for: .executeDeviceCommand, context: context)
    }

    public func plan(
        for text: String,
        context: ResolutionContext,
        operation: HomeAutomationOperationKind
    ) -> GraphExecutionPlan {
        logger.debug("Generating graph plan for operation: \(operation.rawValue, privacy: .public)")
        return catalog.plan(for: operation, context: context)
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

    public static func automationCreationGraph() -> OrchestrationGraph {
        let stages: [(id: AgentID, policy: NodeExecutionPolicy)] = [
            (.operationDetection, .required),
            (.automationDraft, .required),
            (.automationConditionOperandResolution, .required),
            (.automationActionResolution, .required),
            (.automationValidation, .safetyGate),
            (.smartThingsCompilation, .required),
            (.automationResultAssembly, .required)
        ]

        return OrchestrationGraph(
            id: "automation-creation-graph",
            goal: .automationCreation,
            nodes: stages.map { stage in
                GraphNode(
                    id: stage.id.rawValue,
                    requirement: .byID(stage.id),
                    executionPolicy: stage.policy
                )
            },
            edges: zip(stages, stages.dropFirst()).map { lhs, rhs in
                GraphEdge(from: lhs.id.rawValue, to: rhs.id.rawValue)
            },
            entryNodeIDs: [AgentID.operationDetection.rawValue]
        )
    }

    public static func unsupportedGraph() -> OrchestrationGraph {
        OrchestrationGraph(
            id: "unsupported-graph",
            goal: .unsupported,
            nodes: [
                GraphNode(
                    id: AgentID.unsupportedCommand.rawValue,
                    requirement: .byID(.unsupportedCommand),
                    executionPolicy: .required
                )
            ],
            edges: [],
            entryNodeIDs: [AgentID.unsupportedCommand.rawValue]
        )
    }

    private static func executionPolicy(for id: AgentID) -> NodeExecutionPolicy {
        switch id {
        case .automationValidation, .safetyValidation, .parameterValidation, .confirmationPolicy:
            return .safetyGate
        default:
            return .required
        }
    }
}
