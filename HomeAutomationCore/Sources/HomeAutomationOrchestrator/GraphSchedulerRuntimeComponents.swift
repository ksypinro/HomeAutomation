import Foundation
import HomeAutomationAgents
import HomeAutomationCore

struct GraphDependencyTracker: Sendable {
    let nodesByID: [String: GraphNode]
    private let dependencies: [String: Set<String>]
    private var pending: Set<String>
    private var completed: Set<String>

    init(graph: OrchestrationGraph, completedNodeIDs: Set<String> = []) {
        self.nodesByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        self.dependencies = graph.edges.reduce(into: [:]) { partial, edge in
            partial[edge.to, default: []].insert(edge.from)
        }
        let validCompleted = completedNodeIDs.intersection(Set(graph.nodes.map(\.id)))
        self.pending = Set(graph.nodes.map(\.id)).subtracting(validCompleted)
        self.completed = validCompleted
    }

    var hasPendingNodes: Bool {
        !pending.isEmpty
    }

    var pendingNodeIDs: Set<String> {
        pending
    }

    var completedNodeIDs: Set<String> {
        completed
    }

    func readyNodes(in graph: OrchestrationGraph) -> [GraphNode] {
        graph.nodes.filter { node in
            pending.contains(node.id) &&
                dependencies[node.id, default: []].isSubset(of: completed)
        }
    }

    func blockedNodes() -> [GraphNode] {
        pending.compactMap { nodesByID[$0] }
    }

    mutating func complete(_ nodeID: String) {
        pending.remove(nodeID)
        completed.insert(nodeID)
    }
}

struct GraphGuardEvaluator: Sendable {
    func evaluate(
        _ guardCondition: GraphGuard?,
        context: ResolutionContext,
        graph: OrchestrationGraph,
        policy: OrchestratorPolicyEngine
    ) -> Bool {
        guard let guardCondition else {
            return true
        }
        switch guardCondition {
        case .contextKeyPresent(let key):
            return contextHasValue(key, context: context)
        case .contextKeyAbsent(let key):
            return !contextHasValue(key, context: context)
        case .operationType(let operation):
            return operationKind(for: graph.goal) == operation
        case .canExecuteCommand:
            return policy.canExecute(context: context)
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

    private func contextHasValue(_ key: String, context: ResolutionContext) -> Bool {
        switch key {
        case "request.text":
            return !context.request.text.isEmpty
        case ResolutionContextPatchKey.language.rawValue:
            return context.language != nil
        case ResolutionContextPatchKey.operation.rawValue:
            return context.operation != nil
        case ResolutionContextPatchKey.domain.rawValue:
            return context.domain != nil
        case ResolutionContextPatchKey.intent.rawValue:
            return context.intent != nil
        case ResolutionContextPatchKey.deviceType.rawValue:
            return context.deviceType != nil
        case ResolutionContextPatchKey.slots.rawValue:
            return context.slots != nil
        case ResolutionContextPatchKey.risk.rawValue:
            return context.risk != nil
        case ResolutionContextPatchKey.resolutionState.rawValue:
            return context.resolutionState != nil
        case ResolutionContextPatchKey.retrievedCandidates.rawValue:
            return !context.retrievedCandidates.isEmpty
        case ResolutionContextPatchKey.selectedCandidateIDs.rawValue:
            return !context.selectedCandidateIDs.isEmpty
        case ResolutionContextPatchKey.aggregation.rawValue:
            return context.aggregation != nil
        case ResolutionContextPatchKey.hydratedCandidates.rawValue:
            return !context.hydratedCandidates.isEmpty
        case ResolutionContextPatchKey.capabilityDecision.rawValue:
            return context.capabilityDecision != nil
        case ResolutionContextPatchKey.knowledgeSnippets.rawValue:
            return !context.knowledgeSnippets.isEmpty
        case ResolutionContextPatchKey.retrievalReports.rawValue:
            return !context.retrievalReports.isEmpty
        case ResolutionContextPatchKey.instructionPackage.rawValue:
            return context.instructionPackage != nil
        case ResolutionContextPatchKey.draft.rawValue:
            return context.draft != nil
        case ResolutionContextPatchKey.executionPlan.rawValue:
            return context.executionPlan != nil
        case ResolutionContextPatchKey.resolution.rawValue:
            return context.resolution != nil
        case ResolutionContextPatchKey.automationDraft.rawValue:
            return context.scopedValues[.root]?[ResolutionContextPatchKey.automationDraft.rawValue] != nil
        case ResolutionContextPatchKey.automationResolvedActions.rawValue:
            return context.scopedValues[.root]?[ResolutionContextPatchKey.automationResolvedActions.rawValue] != nil
        case ResolutionContextPatchKey.automationValidation.rawValue:
            return context.scopedValues[.root]?[ResolutionContextPatchKey.automationValidation.rawValue] != nil
        case ResolutionContextPatchKey.smartThingsRule.rawValue:
            return context.scopedValues[.backend("smartthings")]?[ResolutionContextPatchKey.smartThingsRule.rawValue] != nil
        case ResolutionContextPatchKey.automationPlan.rawValue:
            return context.scopedValues[.root]?[ResolutionContextPatchKey.automationPlan.rawValue] != nil
        default:
            return false
        }
    }
}

struct GraphAgentSelector: Sendable {
    func selectAgent(
        for node: GraphNode,
        graph: OrchestrationGraph,
        registry: AgentRegistry
    ) -> GraphAgentSelection? {
        switch node.requirement {
        case .byID(let id):
            guard let agent = registry.agent(for: id) else {
                return nil
            }
            let manifest = registry.manifest(for: id) ?? agent.manifest
            if let operation = operationKind(for: graph.goal),
               !manifest.supportedOperations.contains(operation) {
                return nil
            }
            return GraphAgentSelection(agent: agent, manifest: manifest)
        case .byCapability(let capability):
            let candidates: [any AnyHomeAgent]
            if let operation = operationKind(for: graph.goal) {
                candidates = registry.agents(for: capability, operation: operation)
            } else {
                candidates = registry.agents(for: capability)
            }
            guard let agent = candidates.first else {
                return nil
            }
            return GraphAgentSelection(agent: agent, manifest: registry.manifest(for: agent.id) ?? agent.manifest)
        }
    }

    func missingAgentID(for node: GraphNode) -> AgentID? {
        if case .byID(let id) = node.requirement {
            return id
        }
        return nil
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
}

struct GraphRetryController: Sendable {
    func shouldRetry(
        result: AgentRunResult,
        policy: OrchestratorPolicyEngine,
        attemptCount: Int
    ) -> Bool {
        guard case .retryableFailure(let failure) = result else {
            return false
        }
        return policy.shouldRetry(failure: failure, attemptCount: attemptCount)
    }
}

struct GraphSafetyGateHandler: Sendable {
    func isSafetyGate(
        node: GraphNode,
        agentID: AgentID,
        manifest: AgentManifest,
        policy: OrchestratorPolicyEngine
    ) -> Bool {
        node.executionPolicy == .safetyGate ||
            manifest.safetyRole != .none ||
            policy.isMandatorySafetyGate(agentID)
    }

    func failClosed(
        for agentID: AgentID,
        reason: String,
        context: ResolutionContext,
        contextStore: ResolutionContextStore,
        policy: OrchestratorPolicyEngine
    ) async -> AgentRunResult {
        let result = policy.failClosedResult(for: agentID, reason: reason, context: context)
        if case .success(let patch) = result {
            await contextStore.apply(patch)
        }
        return result
    }
}
