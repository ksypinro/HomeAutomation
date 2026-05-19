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
    case missingManifestInput(graphID: String, nodeID: String, key: String, availableKeys: [String])
    case missingTerminalOutput(graphID: String, nodeID: String, requiredKeys: [String], availableKeys: [String])

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
        case .missingManifestInput(let graphID, let nodeID, let key, let availableKeys):
            return "Graph \(graphID) node \(nodeID) consumes missing key '\(key)'. Available keys: \(availableKeys.joined(separator: ", "))"
        case .missingTerminalOutput(let graphID, let nodeID, let requiredKeys, let availableKeys):
            return "Graph \(graphID) terminal node \(nodeID) cannot produce required terminal output. Required one of: \(requiredKeys.joined(separator: ", ")). Available keys: \(availableKeys.joined(separator: ", "))"
        }
    }
}

public struct GraphValidator: Sendable {
    public init() {}

    public func validate(
        _ graph: OrchestrationGraph,
        registry: AgentRegistry? = nil,
        initialContext: ResolutionContext? = nil
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
            if canValidateManifestFlow(errors) {
                errors.append(contentsOf: manifestDataFlowErrors(graph, registry: registry, initialContext: initialContext))
                errors.append(contentsOf: terminalOutputErrors(graph, registry: registry, initialContext: initialContext))
            }
        }

        return stableUnique(errors)
    }

    public func validateOrThrow(
        _ graph: OrchestrationGraph,
        registry: AgentRegistry? = nil,
        initialContext: ResolutionContext? = nil
    ) throws {
        let errors = validate(graph, registry: registry, initialContext: initialContext)
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

    private func manifestDataFlowErrors(
        _ graph: OrchestrationGraph,
        registry: AgentRegistry,
        initialContext: ResolutionContext?
    ) -> [GraphValidationError] {
        let manifestsByNode = selectedManifestsByNode(graph, registry: registry)
        var availableKeys = initialAvailableKeys(for: graph.goal, context: initialContext)
        var completedNodeIDs = Set<String>()
        var pendingNodeIDs = Set(graph.nodes.map(\.id))
        var errors: [GraphValidationError] = []
        let dependencies = graph.edges.reduce(into: [String: Set<String>]()) { partial, edge in
            partial[edge.to, default: []].insert(edge.from)
        }

        while !pendingNodeIDs.isEmpty {
            let readyNodes = graph.nodes.filter { node in
                pendingNodeIDs.contains(node.id) &&
                    dependencies[node.id, default: []].isSubset(of: completedNodeIDs)
            }
            guard !readyNodes.isEmpty else {
                break
            }

            for node in readyNodes {
                let manifest = manifestsByNode[node.id]
                let consumes = manifest?.consumes ?? []
                for key in consumes.sorted() where !availableKeys.contains(key) {
                    errors.append(
                        .missingManifestInput(
                            graphID: graph.id,
                            nodeID: node.id,
                            key: key,
                            availableKeys: availableKeys.sorted()
                        )
                    )
                }

                availableKeys.formUnion(manifest?.produces ?? [])
                pendingNodeIDs.remove(node.id)
                completedNodeIDs.insert(node.id)
            }
        }

        return errors
    }

    private func terminalOutputErrors(
        _ graph: OrchestrationGraph,
        registry: AgentRegistry,
        initialContext: ResolutionContext?
    ) -> [GraphValidationError] {
        let requiredKeys = terminalOutputKeys(for: graph.goal)
        guard !requiredKeys.isEmpty else { return [] }

        let manifestsByNode = selectedManifestsByNode(graph, registry: registry)
        let outgoingNodeIDs = Set(graph.edges.map(\.from))
        let terminalNodes = graph.nodes.filter { !outgoingNodeIDs.contains($0.id) }
        guard !terminalNodes.isEmpty else { return [] }

        let upstream = upstreamNodeIDsByTerminal(graph)
        var errors: [GraphValidationError] = []
        for terminal in terminalNodes {
            var available = initialAvailableKeys(for: graph.goal, context: initialContext)
            for nodeID in upstream[terminal.id, default: []] {
                available.formUnion(manifestsByNode[nodeID]?.produces ?? [])
            }
            if available.isDisjoint(with: requiredKeys) {
                errors.append(
                    .missingTerminalOutput(
                        graphID: graph.id,
                        nodeID: terminal.id,
                        requiredKeys: requiredKeys.sorted(),
                        availableKeys: available.sorted()
                    )
                )
            }
        }
        return errors
    }

    private func selectedManifestsByNode(
        _ graph: OrchestrationGraph,
        registry: AgentRegistry
    ) -> [String: AgentManifest] {
        let selector = GraphAgentSelector()
        return graph.nodes.reduce(into: [:]) { partial, node in
            if let selection = selector.selectAgent(for: node, graph: graph, registry: registry) {
                partial[node.id] = selection.manifest
            }
        }
    }

    private func initialAvailableKeys(
        for goal: OrchestrationGoal,
        context: ResolutionContext?
    ) -> Set<String> {
        var keys: Set<String> = [
            "request.text",
            "request.executeLowRiskCommands",
            "request.automationCreationOptions"
        ]

        if goal == .automationCreation {
            keys.insert(ResolutionContextPatchKey.operation.rawValue)
        }

        guard let context else {
            return keys
        }

        if !context.request.text.isEmpty { keys.insert("request.text") }
        if context.operation != nil { keys.insert(ResolutionContextPatchKey.operation.rawValue) }
        if context.language != nil { keys.insert(ResolutionContextPatchKey.language.rawValue) }
        if context.domain != nil { keys.insert(ResolutionContextPatchKey.domain.rawValue) }
        if context.intent != nil { keys.insert(ResolutionContextPatchKey.intent.rawValue) }
        if context.deviceType != nil { keys.insert(ResolutionContextPatchKey.deviceType.rawValue) }
        if context.slots != nil { keys.insert(ResolutionContextPatchKey.slots.rawValue) }
        if context.risk != nil { keys.insert(ResolutionContextPatchKey.risk.rawValue) }
        if context.resolutionState != nil { keys.insert(ResolutionContextPatchKey.resolutionState.rawValue) }
        if !context.retrievedCandidates.isEmpty { keys.insert(ResolutionContextPatchKey.retrievedCandidates.rawValue) }
        if !context.selectedCandidateIDs.isEmpty { keys.insert(ResolutionContextPatchKey.selectedCandidateIDs.rawValue) }
        if context.aggregation != nil { keys.insert(ResolutionContextPatchKey.aggregation.rawValue) }
        if !context.hydratedCandidates.isEmpty { keys.insert(ResolutionContextPatchKey.hydratedCandidates.rawValue) }
        if context.capabilityDecision != nil { keys.insert(ResolutionContextPatchKey.capabilityDecision.rawValue) }
        if !context.knowledgeSnippets.isEmpty { keys.insert(ResolutionContextPatchKey.knowledgeSnippets.rawValue) }
        if !context.retrievalReports.isEmpty { keys.insert(ResolutionContextPatchKey.retrievalReports.rawValue) }
        if context.instructionPackage != nil { keys.insert(ResolutionContextPatchKey.instructionPackage.rawValue) }
        if context.draft != nil { keys.insert(ResolutionContextPatchKey.draft.rawValue) }
        if context.executionPlan != nil { keys.insert(ResolutionContextPatchKey.executionPlan.rawValue) }
        if context.resolution != nil { keys.insert(ResolutionContextPatchKey.resolution.rawValue) }

        for values in context.scopedValues.values {
            keys.formUnion(values.keys)
        }

        return keys
    }

    private func terminalOutputKeys(for goal: OrchestrationGoal) -> Set<String> {
        switch goal {
        case .rootRouting:
            return [ResolutionContextPatchKey.operation.rawValue]
        case .executeDeviceCommand, .automationCreation, .unsupported:
            return [
                ResolutionContextPatchKey.resolution.rawValue,
                ResolutionContextPatchKey.resolverResult.rawValue
            ]
        }
    }

    private func upstreamNodeIDsByTerminal(_ graph: OrchestrationGraph) -> [String: Set<String>] {
        var incoming: [String: [String]] = [:]
        for edge in graph.edges {
            incoming[edge.to, default: []].append(edge.from)
        }

        let outgoingNodeIDs = Set(graph.edges.map(\.from))
        let terminalNodeIDs = graph.nodes.map(\.id).filter { !outgoingNodeIDs.contains($0) }
        return terminalNodeIDs.reduce(into: [:]) { partial, terminalID in
            var visited = Set<String>()
            var stack = [terminalID]
            while let current = stack.popLast() {
                guard !visited.contains(current) else { continue }
                visited.insert(current)
                stack.append(contentsOf: incoming[current, default: []])
            }
            partial[terminalID] = visited
        }
    }

    private func canValidateManifestFlow(_ errors: [GraphValidationError]) -> Bool {
        !errors.contains {
            switch $0 {
            case .duplicateNodeID, .missingEdgeEndpoint, .cycleDetected, .missingEntryNode, .unreachableNode:
                return true
            case .duplicateEdge, .optionalSafetyGateNode, .missingManifestInput, .missingTerminalOutput:
                return false
            }
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
        case .rootRouting:
            return nil
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
