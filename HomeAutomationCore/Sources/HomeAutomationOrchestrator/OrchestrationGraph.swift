import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public struct OrchestrationGraph: Sendable, Hashable {
    public let id: String
    public let goal: OrchestrationGoal
    public let nodes: [GraphNode]
    public let edges: [GraphEdge]
    public let entryNodeIDs: Set<String>

    public init(
        id: String,
        goal: OrchestrationGoal,
        nodes: [GraphNode],
        edges: [GraphEdge],
        entryNodeIDs: Set<String> = []
    ) {
        self.id = id
        self.goal = goal
        self.nodes = nodes
        self.edges = edges
        self.entryNodeIDs = entryNodeIDs
    }
}

public enum OrchestrationGoal: String, Sendable, Hashable, Codable {
    case executeDeviceCommand
    case automationCreation
    case unsupported
}

public struct GraphNode: Sendable, Hashable, Identifiable {
    public let id: String
    public let requirement: AgentRequirement
    public let executionPolicy: NodeExecutionPolicy
    public let guardCondition: GraphGuard?

    public init(
        id: String,
        requirement: AgentRequirement,
        executionPolicy: NodeExecutionPolicy = .required,
        guardCondition: GraphGuard? = nil
    ) {
        self.id = id
        self.requirement = requirement
        self.executionPolicy = executionPolicy
        self.guardCondition = guardCondition
    }
}

public enum AgentRequirement: Sendable, Hashable {
    case byID(AgentID)
    case byCapability(AgentCapability)
}

public struct GraphEdge: Sendable, Hashable {
    public let from: String
    public let to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

public enum NodeExecutionPolicy: Sendable, Hashable {
    case required
    case optional
    case safetyGate
}

public enum GraphGuard: Sendable, Hashable {
    case contextKeyPresent(String)
    case contextKeyAbsent(String)
    case operationType(HomeAutomationOperationKind)
}
