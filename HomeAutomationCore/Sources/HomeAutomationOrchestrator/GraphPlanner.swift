import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import OSLog

public struct GraphExecutionPlan: Sendable, Hashable {
    public let graph: OrchestrationGraph
    public let isFallbackOnly: Bool
    public let compilationReport: GraphCompilationReport?
    public let criticalPath: GraphCriticalPathMetadata?

    public init(
        graph: OrchestrationGraph,
        isFallbackOnly: Bool = false,
        compilationReport: GraphCompilationReport? = nil,
        criticalPath: GraphCriticalPathMetadata? = nil
    ) {
        self.graph = graph
        self.isFallbackOnly = isFallbackOnly
        self.compilationReport = compilationReport
        self.criticalPath = criticalPath
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

    public func planRootRouting(for text: String, context: ResolutionContext) -> GraphExecutionPlan {
        logger.debug("Generating root routing graph for text: '\(text, privacy: .private)'")
        return GraphExecutionPlan(graph: Self.rootRoutingGraph())
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
            .semanticNLU,
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
            .capabilityResolution,
            .instructionComposer,
            .draftGeneration,
            .safetyValidation,
            .parameterValidation,
            .confirmationPolicy,
            .executionPlanning,
            .mockExecution
        ]

        let allAgents = phaseOne + phaseTwo + sequential
        let nodes = allAgents.map { id in
            GraphNode(
                id: id.rawValue,
                requirement: .byID(id),
                executionPolicy: executionPolicy(for: id),
                guardCondition: guardCondition(for: id),
                interrupt: interrupt(for: id)
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

    public static func rootRoutingGraph() -> OrchestrationGraph {
        OrchestrationGraph(
            id: "root-command-graph",
            goal: .rootRouting,
            nodes: [
                GraphNode(
                    id: AgentID.operationDetection.rawValue,
                    requirement: .byID(.operationDetection),
                    executionPolicy: .required
                )
            ],
            edges: [],
            entryNodeIDs: [AgentID.operationDetection.rawValue]
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
            (.automationComponentSegmentation, .required),
            (.automationComponentFanOut, .required),
            (.automationDraftAssembly, .required),
            (.automationValidation, .safetyGate),
            (.smartThingsCompilation, .required),
            (.smartThingsRuleCreation, .required),
            (.automationResultAssembly, .required)
        ]

        return OrchestrationGraph(
            id: "automation-creation-graph",
            goal: .automationCreation,
            nodes: stages.map { stage in
                GraphNode(
                    id: stage.id.rawValue,
                    requirement: .byID(stage.id),
                    executionPolicy: stage.policy,
                    interrupt: interrupt(for: stage.id)
                )
            },
            edges: [
                GraphEdge(from: AgentID.automationComponentSegmentation.rawValue, to: AgentID.automationComponentFanOut.rawValue),
                GraphEdge(from: AgentID.automationComponentFanOut.rawValue, to: AgentID.automationDraftAssembly.rawValue),
                GraphEdge(from: AgentID.automationDraftAssembly.rawValue, to: AgentID.automationValidation.rawValue),
                GraphEdge(from: AgentID.automationValidation.rawValue, to: AgentID.smartThingsCompilation.rawValue),
                GraphEdge(from: AgentID.smartThingsCompilation.rawValue, to: AgentID.smartThingsRuleCreation.rawValue),
                GraphEdge(from: AgentID.smartThingsRuleCreation.rawValue, to: AgentID.automationResultAssembly.rawValue)
            ],
            entryNodeIDs: [AgentID.automationComponentSegmentation.rawValue]
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
        case .automationValidation, .safetyValidation, .parameterValidation, .confirmationPolicy, .mockExecution:
            return .safetyGate
        default:
            return .required
        }
    }

    private static func guardCondition(for id: AgentID) -> GraphGuard? {
        switch id {
        case .mockExecution:
            return .canExecuteCommand
        default:
            return nil
        }
    }

    private static func interrupt(for id: AgentID) -> GraphInterrupt? {
        switch id {
        case .confirmationPolicy:
            return GraphInterrupt(
                kind: .confirmation,
                reason: "Pause before confirmation policy when a caller requests human approval checkpoints."
            )
        case .smartThingsRuleCreation:
            return GraphInterrupt(
                kind: .externalMutationApproval,
                reason: "Pause before external SmartThings rule creation when a caller requests mutation approval."
            )
        default:
            return nil
        }
    }
}
