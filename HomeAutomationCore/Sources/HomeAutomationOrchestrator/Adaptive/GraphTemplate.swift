import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public enum GraphTemplateID: String, Sendable, Hashable, Codable, CaseIterable {
    case rootRouting
    case directCommand
    case fallback
    case automationCreation
    case unsupported
    case finalization
    case escalation
}

public struct GraphTemplateVersion: Sendable, Hashable, Codable, Comparable {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public static func < (lhs: GraphTemplateVersion, rhs: GraphTemplateVersion) -> Bool {
        lhs.value < rhs.value
    }
}

public struct GraphTemplate: Sendable, Hashable {
    public let templateID: GraphTemplateID
    public let version: GraphTemplateVersion
    public let graph: OrchestrationGraph
    public let mandatoryNodeIDs: Set<String>
    public let intentionalEdges: Set<GraphEdge>

    public init(
        templateID: GraphTemplateID,
        version: GraphTemplateVersion = GraphTemplateVersion(1),
        graph: OrchestrationGraph,
        mandatoryNodeIDs: Set<String> = [],
        intentionalEdges: Set<GraphEdge> = []
    ) {
        self.templateID = templateID
        self.version = version
        self.graph = graph
        self.mandatoryNodeIDs = mandatoryNodeIDs
        self.intentionalEdges = intentionalEdges
    }

    public func staticPlan(isFallbackOnly: Bool = false) -> GraphExecutionPlan {
        GraphExecutionPlan(
            graph: graph,
            isFallbackOnly: isFallbackOnly,
            compilationReport: GraphCompilationReport.staticTemplate(template: self),
            criticalPath: CriticalPathAnalyzer().analyze(graph)
        )
    }
}

public enum GraphTemplateCatalog {
    public static func rootRouting() -> GraphTemplate {
        GraphTemplate(
            templateID: .rootRouting,
            graph: GraphPlanner.rootRoutingGraph(),
            mandatoryNodeIDs: [AgentID.operationDetection.rawValue]
        )
    }

    public static func directCommand() -> GraphTemplate {
        let graph = GraphPlanner.directCommandGraph()
        return GraphTemplate(
            templateID: .directCommand,
            graph: graph,
            mandatoryNodeIDs: nonPrunableNodeIDs(in: graph)
        )
    }

    public static func fallback() -> GraphTemplate {
        let graph = GraphPlanner.fallbackGraph()
        return GraphTemplate(
            templateID: .fallback,
            graph: graph,
            mandatoryNodeIDs: Set(graph.nodes.map(\.id)),
            intentionalEdges: Set(graph.edges)
        )
    }

    public static func automationCreation() -> GraphTemplate {
        let graph = GraphPlanner.automationCreationGraph()
        return GraphTemplate(
            templateID: .automationCreation,
            graph: graph,
            mandatoryNodeIDs: nonPrunableNodeIDs(in: graph),
            intentionalEdges: Set(graph.edges)
        )
    }

    public static func unsupported() -> GraphTemplate {
        let graph = GraphPlanner.unsupportedGraph()
        return GraphTemplate(
            templateID: .unsupported,
            graph: graph,
            mandatoryNodeIDs: Set(graph.nodes.map(\.id))
        )
    }

    public static func finalization(_ graph: OrchestrationGraph) -> GraphTemplate {
        GraphTemplate(
            templateID: .finalization,
            graph: graph,
            mandatoryNodeIDs: Set(graph.nodes.map(\.id)),
            intentionalEdges: Set(graph.edges)
        )
    }

    public static func directCommandFinalization() -> GraphTemplate {
        finalization(FinalizationGraphFactory.directCommandFinalizationGraph())
    }

    public static func automationFinalization() -> GraphTemplate {
        finalization(FinalizationGraphFactory.automationFinalizationGraph())
    }

    public static func escalation(_ graph: OrchestrationGraph) -> GraphTemplate {
        GraphTemplate(
            templateID: .escalation,
            graph: graph,
            mandatoryNodeIDs: nonPrunableNodeIDs(in: graph),
            intentionalEdges: Set(graph.edges)
        )
    }

    public static func template(for operation: HomeAutomationOperationKind) -> GraphTemplate {
        switch operation {
        case .executeDeviceCommand:
            return directCommand()
        case .automationCreation:
            return automationCreation()
        case .unsupported,
             .automationUpdate,
             .automationDeletion,
             .automationQuery,
             .sceneCreation,
             .routineExecution:
            return unsupported()
        }
    }

    private static func nonPrunableNodeIDs(in graph: OrchestrationGraph) -> Set<String> {
        Set(graph.nodes.compactMap { node in
            if node.executionPolicy == .safetyGate || node.interrupt != nil {
                return node.id
            }
            return nil
        })
    }
}
