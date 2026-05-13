import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public enum GraphValidationError: Error, Sendable, Hashable, CustomStringConvertible {
    case duplicateNodeID(String)
    case missingEdgeEndpoint(edge: GraphEdge, missingNodeID: String)
    case duplicateEdge(GraphEdge)
    case cycleDetected
    case missingEntryNode(String)
    case unreachableNode(String)
    case optionalSafetyGateNode(String)

    public var description: String {
        switch self {
        case .duplicateNodeID(let id):
            return "Duplicate graph node ID: \(id)"
        case .missingEdgeEndpoint(let edge, let missingNodeID):
            return "Edge \(edge.from) -> \(edge.to) references missing node: \(missingNodeID)"
        case .duplicateEdge(let edge):
            return "Duplicate graph edge: \(edge.from) -> \(edge.to)"
        case .cycleDetected:
            return "Graph contains a cycle"
        case .missingEntryNode(let id):
            return "Graph entry node does not exist: \(id)"
        case .unreachableNode(let id):
            return "Graph node is unreachable from entry nodes: \(id)"
        case .optionalSafetyGateNode(let id):
            return "Graph safety gate cannot be optional: \(id)"
        }
    }
}

public struct GraphValidator: Sendable {
    public init() {}

    public func validate(
        _ graph: OrchestrationGraph,
        registry: AgentRegistry? = nil
    ) -> [GraphValidationError] {
        var errors: [GraphValidationError] = []
        let nodeIDs = graph.nodes.map(\.id)
        let nodeIDSet = Set(nodeIDs)

        errors.append(contentsOf: duplicateNodeErrors(nodeIDs))
        errors.append(contentsOf: missingEndpointErrors(graph.edges, nodeIDs: nodeIDSet))
        errors.append(contentsOf: duplicateEdgeErrors(graph.edges))

        if containsCycle(graph.nodes, edges: graph.edges, nodeIDs: nodeIDSet) {
            errors.append(.cycleDetected)
        }

        let entryNodeIDs = graph.entryNodeIDs.isEmpty ? inferredEntryNodeIDs(graph) : graph.entryNodeIDs
        for id in entryNodeIDs where !nodeIDSet.contains(id) {
            errors.append(.missingEntryNode(id))
        }

        if !entryNodeIDs.isEmpty {
            let reachable = reachableNodeIDs(from: entryNodeIDs.intersection(nodeIDSet), edges: graph.edges)
            for id in nodeIDs where !reachable.contains(id) {
                errors.append(.unreachableNode(id))
            }
        }

        if let registry {
            errors.append(contentsOf: optionalSafetyGateErrors(graph.nodes, registry: registry, goal: graph.goal))
        }

        return stableUnique(errors)
    }

    public func validateOrThrow(
        _ graph: OrchestrationGraph,
        registry: AgentRegistry? = nil
    ) throws {
        let errors = validate(graph, registry: registry)
        if let first = errors.first {
            throw first
        }
    }

    private func duplicateNodeErrors(_ nodeIDs: [String]) -> [GraphValidationError] {
        var seen = Set<String>()
        var duplicates: [GraphValidationError] = []
        for id in nodeIDs {
            if seen.contains(id) {
                duplicates.append(.duplicateNodeID(id))
            } else {
                seen.insert(id)
            }
        }
        return duplicates
    }

    private func missingEndpointErrors(
        _ edges: [GraphEdge],
        nodeIDs: Set<String>
    ) -> [GraphValidationError] {
        edges.flatMap { edge -> [GraphValidationError] in
            var errors: [GraphValidationError] = []
            if !nodeIDs.contains(edge.from) {
                errors.append(.missingEdgeEndpoint(edge: edge, missingNodeID: edge.from))
            }
            if !nodeIDs.contains(edge.to) {
                errors.append(.missingEdgeEndpoint(edge: edge, missingNodeID: edge.to))
            }
            return errors
        }
    }

    private func duplicateEdgeErrors(_ edges: [GraphEdge]) -> [GraphValidationError] {
        var seen = Set<GraphEdge>()
        var duplicates: [GraphValidationError] = []
        for edge in edges {
            if seen.contains(edge) {
                duplicates.append(.duplicateEdge(edge))
            } else {
                seen.insert(edge)
            }
        }
        return duplicates
    }

    private func containsCycle(
        _ nodes: [GraphNode],
        edges: [GraphEdge],
        nodeIDs: Set<String>
    ) -> Bool {
        var incomingCounts: [String: Int] = [:]
        for node in nodes {
            incomingCounts[node.id] = 0
        }
        var outgoing: [String: [String]] = [:]
        for edge in edges where nodeIDs.contains(edge.from) && nodeIDs.contains(edge.to) {
            outgoing[edge.from, default: []].append(edge.to)
            incomingCounts[edge.to, default: 0] += 1
        }

        var queue = incomingCounts
            .filter { $0.value == 0 }
            .map(\.key)
        var visited = 0

        while let current = queue.popLast() {
            visited += 1
            for next in outgoing[current, default: []] {
                incomingCounts[next, default: 0] -= 1
                if incomingCounts[next] == 0 {
                    queue.append(next)
                }
            }
        }

        return visited != incomingCounts.count
    }

    private func optionalSafetyGateErrors(
        _ nodes: [GraphNode],
        registry: AgentRegistry,
        goal: OrchestrationGoal
    ) -> [GraphValidationError] {
        nodes.compactMap { node in
            guard node.executionPolicy == .optional else {
                return nil
            }
            let manifests = manifests(for: node.requirement, registry: registry, goal: goal)
            guard manifests.contains(where: { $0.safetyRole != .none }) else {
                return nil
            }
            return .optionalSafetyGateNode(node.id)
        }
    }

    private func manifests(
        for requirement: AgentRequirement,
        registry: AgentRegistry,
        goal: OrchestrationGoal
    ) -> [AgentManifest] {
        switch requirement {
        case .byID(let id):
            return registry.manifest(for: id).map { [$0] } ?? []
        case .byCapability(let capability):
            guard let operation = operationKind(for: goal) else {
                return registry.agents(for: capability).map(\.manifest)
            }
            return registry.agents(for: capability, operation: operation).map(\.manifest)
        }
    }

    private func operationKind(for goal: OrchestrationGoal) -> HomeAutomationOperationKind? {
        switch goal {
        case .executeDeviceCommand:
            return .executeDeviceCommand
        case .automationCreation:
            return .automationCreation
        case .unsupported:
            return nil
        }
    }

    private func inferredEntryNodeIDs(_ graph: OrchestrationGraph) -> Set<String> {
        let destinations = Set(graph.edges.map(\.to))
        return Set(graph.nodes.map(\.id).filter { !destinations.contains($0) })
    }

    private func reachableNodeIDs(
        from entryNodeIDs: Set<String>,
        edges: [GraphEdge]
    ) -> Set<String> {
        var outgoing: [String: [String]] = [:]
        for edge in edges {
            outgoing[edge.from, default: []].append(edge.to)
        }

        var visited = Set<String>()
        var stack = Array(entryNodeIDs)
        while let current = stack.popLast() {
            guard !visited.contains(current) else { continue }
            visited.insert(current)
            stack.append(contentsOf: outgoing[current, default: []])
        }
        return visited
    }

    private func stableUnique(_ errors: [GraphValidationError]) -> [GraphValidationError] {
        var seen = Set<GraphValidationError>()
        var result: [GraphValidationError] = []
        for error in errors where !seen.contains(error) {
            seen.insert(error)
            result.append(error)
        }
        return result
    }
}
