import Foundation
import HomeAutomationAgents

public struct GraphNodeCriticalPathMetadata: Sendable, Hashable, Codable {
    public let downstreamNodeIDs: [String]
    public let topologicalLevel: Int
    public let estimatedServiceMs: Double
    public let estimatedRemainingServiceMs: Double

    public init(
        downstreamNodeIDs: [String],
        topologicalLevel: Int,
        estimatedServiceMs: Double,
        estimatedRemainingServiceMs: Double
    ) {
        self.downstreamNodeIDs = downstreamNodeIDs
        self.topologicalLevel = topologicalLevel
        self.estimatedServiceMs = estimatedServiceMs
        self.estimatedRemainingServiceMs = estimatedRemainingServiceMs
    }
}

public struct GraphCriticalPathMetadata: Sendable, Hashable, Codable {
    public let graphID: String
    public let nodeMetadata: [String: GraphNodeCriticalPathMetadata]

    public init(graphID: String, nodeMetadata: [String: GraphNodeCriticalPathMetadata]) {
        self.graphID = graphID
        self.nodeMetadata = nodeMetadata
    }
}

public struct CriticalPathAnalyzer: Sendable {
    public init() {}

    public func analyze(_ graph: OrchestrationGraph) -> GraphCriticalPathMetadata {
        let nodeIDs = Set(graph.nodes.map(\.id))
        let successors = graph.edges.reduce(into: [String: Set<String>]()) { partial, edge in
            guard nodeIDs.contains(edge.from), nodeIDs.contains(edge.to) else { return }
            partial[edge.from, default: []].insert(edge.to)
        }
        let predecessors = graph.edges.reduce(into: [String: Set<String>]()) { partial, edge in
            guard nodeIDs.contains(edge.from), nodeIDs.contains(edge.to) else { return }
            partial[edge.to, default: []].insert(edge.from)
        }
        let levels = topologicalLevels(nodes: graph.nodes, predecessors: predecessors, successors: successors)
        var downstreamCache: [String: Set<String>] = [:]
        var remainingCache: [String: Double] = [:]
        var nodeMetadata: [String: GraphNodeCriticalPathMetadata] = [:]

        for node in graph.nodes {
            let downstream = downstreamNodeIDs(
                from: node.id,
                successors: successors,
                cache: &downstreamCache,
                visiting: []
            )
            let service = estimatedServiceMs(for: node)
            let remaining = estimatedRemainingServiceMs(
                from: node.id,
                nodesByID: Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) }),
                successors: successors,
                cache: &remainingCache,
                visiting: []
            )
            nodeMetadata[node.id] = GraphNodeCriticalPathMetadata(
                downstreamNodeIDs: downstream.sorted(),
                topologicalLevel: levels[node.id] ?? 0,
                estimatedServiceMs: service,
                estimatedRemainingServiceMs: remaining
            )
        }

        return GraphCriticalPathMetadata(graphID: graph.id, nodeMetadata: nodeMetadata)
    }

    private func topologicalLevels(
        nodes: [GraphNode],
        predecessors: [String: Set<String>],
        successors: [String: Set<String>]
    ) -> [String: Int] {
        var remainingPredecessors = predecessors
        var levels: [String: Int] = [:]
        var queue = nodes
            .map(\.id)
            .filter { remainingPredecessors[$0, default: []].isEmpty }
            .sorted()

        for id in queue {
            levels[id] = 0
        }

        while !queue.isEmpty {
            let current = queue.removeFirst()
            let nextLevel = (levels[current] ?? 0) + 1
            for next in successors[current, default: []].sorted() {
                remainingPredecessors[next, default: []].remove(current)
                if remainingPredecessors[next, default: []].isEmpty {
                    levels[next] = max(levels[next] ?? 0, nextLevel)
                    queue.append(next)
                } else {
                    levels[next] = max(levels[next] ?? 0, nextLevel)
                }
            }
        }

        return levels
    }

    private func downstreamNodeIDs(
        from nodeID: String,
        successors: [String: Set<String>],
        cache: inout [String: Set<String>],
        visiting: Set<String>
    ) -> Set<String> {
        if let cached = cache[nodeID] {
            return cached
        }
        guard !visiting.contains(nodeID) else {
            return []
        }
        var result = Set<String>()
        let nextVisiting = visiting.union([nodeID])
        for successor in successors[nodeID, default: []] {
            result.insert(successor)
            result.formUnion(downstreamNodeIDs(
                from: successor,
                successors: successors,
                cache: &cache,
                visiting: nextVisiting
            ))
        }
        cache[nodeID] = result
        return result
    }

    private func estimatedRemainingServiceMs(
        from nodeID: String,
        nodesByID: [String: GraphNode],
        successors: [String: Set<String>],
        cache: inout [String: Double],
        visiting: Set<String>
    ) -> Double {
        if let cached = cache[nodeID] {
            return cached
        }
        guard !visiting.contains(nodeID) else {
            return 0
        }
        guard let node = nodesByID[nodeID] else {
            return 0
        }
        let nextVisiting = visiting.union([nodeID])
        let own = estimatedServiceMs(for: node)
        let childMax = successors[nodeID, default: []]
            .map {
                estimatedRemainingServiceMs(
                    from: $0,
                    nodesByID: nodesByID,
                    successors: successors,
                    cache: &cache,
                    visiting: nextVisiting
                )
            }
            .max() ?? 0
        let value = own + childMax
        cache[nodeID] = value
        return value
    }

    private func estimatedServiceMs(for node: GraphNode) -> Double {
        switch node.executionPolicy {
        case .safetyGate:
            return 120
        case .required:
            return 200
        case .optional:
            return 80
        }
    }
}
