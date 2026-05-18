import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import OSLog

public struct GraphScheduler: Sendable {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "GraphScheduler")

    public init() {}

    public func execute(
        _ graph: OrchestrationGraph,
        registry: AgentRegistry,
        contextStore: ResolutionContextStore,
        eventBus: AgentEventBus,
        policy: OrchestratorPolicyEngine,
        circuitBreakers: CircuitBreakerRegistry,
        runID: UUID
    ) async -> GraphSchedulerResult {
        logger.info("Starting graph \(graph.id, privacy: .public) for runID: \(runID, privacy: .public)")
        let metrics = GraphRunMetricsRecorder(graph: graph)
        let validationErrors = GraphValidator().validate(graph, registry: registry)
        guard validationErrors.isEmpty else {
            let detail = validationErrors.map(\.description).joined(separator: "; ")
            let failure = AgentFailure(
                agentID: AgentID("graphScheduler"),
                reason: "Invalid orchestration graph: \(detail)",
                isRetryable: false
            )
            await eventBus.publish(
                OrchestratorPipelineEvent(
                    runID: runID,
                    stage: graph.id,
                    agentID: "graphScheduler",
                    status: .failed,
                    detail: failure.reason
                )
            )
            return GraphSchedulerResult(
                exit: .terminalFailure(failure),
                metrics: await metrics.finish()
            )
        }

        let nodesByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        let dependencies = dependencyMap(for: graph)
        var pending = Set(graph.nodes.map(\.id))
        var completed = Set<String>()

        while !pending.isEmpty {
            let context = await contextStore.snapshot()
            let candidates = graph.nodes.filter { node in
                pending.contains(node.id) &&
                    dependencies[node.id, default: []].isSubset(of: completed)
            }

            guard !candidates.isEmpty else {
                let blockedNodes = pending.compactMap { nodesByID[$0] }
                let allOptional = blockedNodes.allSatisfy { $0.executionPolicy == .optional }
                if allOptional {
                    await markPendingSkipped(
                        pending,
                        nodesByID: nodesByID,
                        registry: registry,
                        graph: graph,
                        eventBus: eventBus,
                        runID: runID,
                        metrics: metrics,
                        reason: "Optional nodes blocked"
                    )
                    break
                }
                
                let blocked = pending.sorted().joined(separator: ", ")
                let failure = AgentFailure(
                    agentID: AgentID("graphScheduler"),
                    reason: "No ready graph nodes. Blocked nodes: \(blocked)",
                    isRetryable: false
                )
                await eventBus.publish(
                    OrchestratorPipelineEvent(
                        runID: runID,
                        stage: graph.id,
                        agentID: "graphScheduler",
                        status: .failed,
                        detail: failure.reason
                    )
                )
                await markPendingSkipped(
                    pending,
                    nodesByID: nodesByID,
                    registry: registry,
                    graph: graph,
                    eventBus: eventBus,
                    runID: runID,
                    metrics: metrics,
                    reason: "Graph blocked"
                )
                return GraphSchedulerResult(
                    exit: .terminalFailure(failure),
                    metrics: await metrics.finish()
                )
            }

            var runnable: [GraphNode] = []
            for node in candidates {
                if evaluate(node.guardCondition, context: context, graph: graph) {
                    runnable.append(node)
                } else {
                    pending.remove(node.id)
                    completed.insert(node.id)
                    await markSkipped(
                        node: node,
                        selectedAgentID: nil,
                        eventBus: eventBus,
                        runID: runID,
                        metrics: metrics,
                        detail: "Graph guard not satisfied"
                    )
                }
            }

            guard !runnable.isEmpty else {
                continue
            }

            let firstExit = await withTaskGroup(of: GraphNodeOutcome.self) { group in
                for node in runnable {
                    group.addTask {
                        await self.runNode(
                            node,
                            graph: graph,
                            registry: registry,
                            context: context,
                            contextStore: contextStore,
                            eventBus: eventBus,
                            policy: policy,
                            circuitBreakers: circuitBreakers,
                            runID: runID,
                            metrics: metrics
                        )
                    }
                }

                var firstExit: AgentRunResult?
                for await outcome in group {
                    pending.remove(outcome.nodeID)
                    completed.insert(outcome.nodeID)
                    if firstExit == nil, let exit = outcome.exit {
                        firstExit = exit
                    }
                }
                return firstExit
            }

            if let firstExit {
                await markPendingSkipped(
                    pending,
                    nodesByID: nodesByID,
                    registry: registry,
                    graph: graph,
                    eventBus: eventBus,
                    runID: runID,
                    metrics: metrics,
                    reason: "Terminal graph exit"
                )
                return GraphSchedulerResult(exit: firstExit, metrics: await metrics.finish())
            }
        }

        logger.info("Graph \(graph.id, privacy: .public) completed without terminal exit.")
        return GraphSchedulerResult(exit: nil, metrics: await metrics.finish())
    }

    private func runNode(
        _ node: GraphNode,
        graph: OrchestrationGraph,
        registry: AgentRegistry,
        context: ResolutionContext,
        contextStore: ResolutionContextStore,
        eventBus: AgentEventBus,
        policy: OrchestratorPolicyEngine,
        circuitBreakers: CircuitBreakerRegistry,
        runID: UUID,
        metrics: GraphRunMetricsRecorder
    ) async -> GraphNodeOutcome {
        let selection = selectAgent(for: node, graph: graph, registry: registry)
        guard let selection else {
            await markSkipped(
                node: node,
                selectedAgentID: nil,
                eventBus: eventBus,
                runID: runID,
                metrics: metrics,
                detail: "Agent unavailable"
            )

            if let missingID = missingAgentID(for: node),
               policy.isMandatorySafetyGate(missingID) || node.executionPolicy == .safetyGate {
                let exit = await failClosed(
                    for: missingID,
                    reason: "agent unavailable",
                    context: context,
                    contextStore: contextStore,
                    policy: policy
                )
                return GraphNodeOutcome(nodeID: node.id, exit: exit)
            }

            if node.executionPolicy == .safetyGate {
                let failure = AgentFailure(
                    agentID: AgentID("graphScheduler"),
                    reason: "Safety gate \(node.id) has no available agent",
                    isRetryable: false
                )
                return GraphNodeOutcome(nodeID: node.id, exit: .terminalFailure(failure))
            }

            return GraphNodeOutcome(nodeID: node.id, exit: nil)
        }

        let agentID = selection.agent.id
        let breaker = await circuitBreakers.breaker(for: agentID)
        guard await breaker.shouldAllow() else {
            logger.warning("Circuit breaker OPEN for graph node \(node.id, privacy: .public), agent \(agentID.rawValue, privacy: .public)")
            let now = Date()
            await contextStore.appendTrace(
                AgentTraceEntry(
                    agentID: agentID,
                    startedAt: now,
                    endedAt: now,
                    result: .skipped
                )
            )
            await markSkipped(
                node: node,
                selectedAgentID: agentID,
                eventBus: eventBus,
                runID: runID,
                metrics: metrics,
                detail: "Circuit breaker open"
            )
            if isSafetyGate(node: node, agentID: agentID, manifest: selection.manifest, policy: policy) {
                let exit = await failClosed(
                    for: agentID,
                    reason: "circuit breaker open",
                    context: context,
                    contextStore: contextStore,
                    policy: policy
                )
                return GraphNodeOutcome(nodeID: node.id, exit: exit)
            }
            return GraphNodeOutcome(nodeID: node.id, exit: nil)
        }

        await eventBus.publish(
            OrchestratorPipelineEvent(
                runID: runID,
                stage: node.id,
                agentID: agentID.rawValue,
                status: .running
            )
        )

        var attemptCount = 0
        var result: AgentRunResult
        var start: Date
        var end: Date

        repeat {
            attemptCount += 1
            start = Date()
            await metrics.markRunning(nodeID: node.id, agentID: agentID, startedAt: start)
            
            do {
                result = try await withAgentTimeout(
                    agentID: agentID,
                    timeoutNanoseconds: selection.agent.timeoutNanoseconds
                ) {
                    await selection.agent.run(context: context)
                }
            } catch is AgentTimeoutError {
                result = .retryableFailure(AgentFailure(
                    agentID: agentID,
                    reason: "Agent timed out after \(selection.agent.timeoutNanoseconds / 1_000_000)ms",
                    isRetryable: true
                ))
            } catch {
                result = .terminalFailure(AgentFailure(
                    agentID: agentID,
                    reason: error.localizedDescription,
                    isRetryable: false
                ))
            }
            
            end = Date()

            await record(result: result, breaker: breaker, registry: circuitBreakers)
            await contextStore.appendTrace(
                AgentTraceEntry(
                    agentID: agentID,
                    startedAt: start,
                    endedAt: end,
                    result: traceResult(for: result)
                )
            )
            
            if case .retryableFailure(let failure) = result,
               policy.shouldRetry(failure: failure, attemptCount: attemptCount) {
                logger.info("Retrying agent \(agentID.rawValue, privacy: .public) (attempt \(attemptCount + 1))")
                continue
            }
            break
        } while true

        switch result {
        case .success(let patch):
            await contextStore.apply(patch)
        case .retryableFailure(let failure), .terminalFailure(let failure):
            await contextStore.appendError(failure)
        case .clarification, .unsupported:
            break
        }

        await eventBus.publish(
            OrchestratorPipelineEvent(
                runID: runID,
                stage: node.id,
                agentID: agentID.rawValue,
                status: eventStatus(for: result),
                detail: detail(for: result)
            )
        )
        await metrics.markFinished(
            nodeID: node.id,
            status: eventStatus(for: result) == .completed ? .completed : .failed,
            startedAt: start,
            endedAt: end
        )

        if isSafetyGate(node: node, agentID: agentID, manifest: selection.manifest, policy: policy) {
            switch result {
            case .success:
                break
            default:
                let exit = await failClosed(
                    for: agentID,
                    reason: "mandatory gate failed",
                    context: await contextStore.snapshot(),
                    contextStore: contextStore,
                    policy: policy
                )
                return GraphNodeOutcome(nodeID: node.id, exit: exit)
            }
        }

        if policy.isTerminalExit(result) {
            return GraphNodeOutcome(nodeID: node.id, exit: result)
        }

        if shouldStopAfterContextResolution(await contextStore.snapshot(), after: agentID) {
            return GraphNodeOutcome(nodeID: node.id, exit: result)
        }

        return GraphNodeOutcome(nodeID: node.id, exit: nil)
    }

    private func selectAgent(
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

    private func missingAgentID(for node: GraphNode) -> AgentID? {
        if case .byID(let id) = node.requirement {
            return id
        }
        return nil
    }

    private func isSafetyGate(
        node: GraphNode,
        agentID: AgentID,
        manifest: AgentManifest,
        policy: OrchestratorPolicyEngine
    ) -> Bool {
        node.executionPolicy == .safetyGate ||
            manifest.safetyRole != .none ||
            policy.isMandatorySafetyGate(agentID)
    }

    private func record(result: AgentRunResult, breaker: AgentCircuitBreaker, registry: CircuitBreakerRegistry) async {
        switch result {
        case .success, .clarification, .unsupported:
            await breaker.recordSuccess()
        case .retryableFailure, .terminalFailure:
            await breaker.recordFailure()
        }
        await registry.persist()
    }

    private func failClosed(
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

    private func shouldStopAfterContextResolution(_ context: ResolutionContext, after agentID: AgentID) -> Bool {
        guard let resolution = context.resolution else { return false }
        switch resolution {
        case .needsClarification, .unsupported, .requiresConfirmation, .executed:
            return true
        case .automationDrafted, .automationRequiresConfirmation:
            return true
        case .readyToExecute:
            return agentID == .ruleFallback || agentID == .bixbyFallback
        }
    }

    private func evaluate(
        _ guardCondition: GraphGuard?,
        context: ResolutionContext,
        graph: OrchestrationGraph
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

    private func dependencyMap(for graph: OrchestrationGraph) -> [String: Set<String>] {
        graph.edges.reduce(into: [:]) { partial, edge in
            partial[edge.to, default: []].insert(edge.from)
        }
    }

    private func markSkipped(
        node: GraphNode,
        selectedAgentID: AgentID?,
        eventBus: AgentEventBus,
        runID: UUID,
        metrics: GraphRunMetricsRecorder,
        detail: String
    ) async {
        await metrics.markSkipped(nodeID: node.id, agentID: selectedAgentID)
        await eventBus.publish(
            OrchestratorPipelineEvent(
                runID: runID,
                stage: node.id,
                agentID: selectedAgentID?.rawValue,
                status: .skipped,
                detail: detail
            )
        )
    }

    private func markPendingSkipped(
        _ pending: Set<String>,
        nodesByID: [String: GraphNode],
        registry: AgentRegistry,
        graph: OrchestrationGraph,
        eventBus: AgentEventBus,
        runID: UUID,
        metrics: GraphRunMetricsRecorder,
        reason: String
    ) async {
        for nodeID in pending.sorted() {
            guard let node = nodesByID[nodeID] else { continue }
            let agentID = selectAgent(for: node, graph: graph, registry: registry)?.agent.id
            await markSkipped(
                node: node,
                selectedAgentID: agentID,
                eventBus: eventBus,
                runID: runID,
                metrics: metrics,
                detail: reason
            )
        }
    }

    private func traceResult(for result: AgentRunResult) -> AgentTraceEntry.TraceResult {
        switch result {
        case .success:
            return .success
        case .clarification:
            return .clarification
        case .unsupported:
            return .unsupported
        case .retryableFailure:
            return .retryableFailure
        case .terminalFailure:
            return .terminalFailure
        }
    }

    private func eventStatus(for result: AgentRunResult) -> OrchestratorPipelineEvent.EventStatus {
        switch result {
        case .success:
            return .completed
        case .clarification, .unsupported, .retryableFailure, .terminalFailure:
            return .failed
        }
    }

    private func detail(for result: AgentRunResult) -> String {
        switch result {
        case .success:
            return ""
        case .clarification(let value), .unsupported(let value):
            return value
        case .retryableFailure(let failure), .terminalFailure(let failure):
            return failure.reason
        }
    }
}

private struct GraphAgentSelection: Sendable {
    let agent: any AnyHomeAgent
    let manifest: AgentManifest
}

private struct GraphNodeOutcome: Sendable {
    let nodeID: String
    let exit: AgentRunResult?
}

private actor GraphRunMetricsRecorder {
    private var metrics: GraphRunMetrics

    init(graph: OrchestrationGraph) {
        var nodeStatuses: [String: GraphNodeRunStatus] = [:]
        for node in graph.nodes {
            nodeStatuses[node.id] = .pending
        }
        self.metrics = GraphRunMetrics(
            graphID: graph.id,
            goal: graph.goal,
            nodeStatuses: nodeStatuses
        )
    }

    func markRunning(nodeID: String, agentID: AgentID, startedAt: Date) {
        metrics.nodeStatuses[nodeID] = .running
        metrics.selectedAgents[nodeID] = agentID.rawValue
    }

    func markFinished(
        nodeID: String,
        status: GraphNodeRunStatus,
        startedAt: Date,
        endedAt: Date
    ) {
        metrics.nodeStatuses[nodeID] = status
        metrics.nodeDurations[nodeID] = endedAt.timeIntervalSince(startedAt)
    }

    func markSkipped(nodeID: String, agentID: AgentID?) {
        metrics.nodeStatuses[nodeID] = .skipped
        if let agentID {
            metrics.selectedAgents[nodeID] = agentID.rawValue
        }
        if !metrics.skippedNodeIDs.contains(nodeID) {
            metrics.skippedNodeIDs.append(nodeID)
        }
    }

    func finish() -> GraphRunMetrics {
        metrics.finishedAt = Date()
        return metrics
    }
}
