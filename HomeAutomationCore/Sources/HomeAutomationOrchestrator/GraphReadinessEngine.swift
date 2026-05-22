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
