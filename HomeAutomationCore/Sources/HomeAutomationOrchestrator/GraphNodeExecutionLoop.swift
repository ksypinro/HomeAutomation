import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import OSLog

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

struct GraphAgentSelection: Sendable {
    let agent: any AnyHomeAgent
    let manifest: AgentManifest
}

struct GraphNodeOutcome: Sendable {
    let nodeID: String
    let exit: AgentRunResult?
}

actor GraphRunMetricsRecorder {
    private var metrics: GraphRunMetrics
    private var readyAt: [String: Date] = [:]

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

    func markResumedCompleted(nodeIDs: Set<String>) {
        for nodeID in nodeIDs {
            metrics.nodeStatuses[nodeID] = .completed
        }
    }

    func markRunning(nodeID: String, agentID: AgentID, startedAt: Date) {
        metrics.nodeStatuses[nodeID] = .running
        metrics.selectedAgents[nodeID] = agentID.rawValue
    }

    func markReady(nodeID: String, at: Date) {
        readyAt[nodeID] = readyAt[nodeID] ?? at
    }

    func markQueuedStart(nodeID: String, at: Date) {
        if let ready = readyAt[nodeID] {
            metrics.nodeQueueDurations[nodeID] = at.timeIntervalSince(ready)
        }
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

    func recordSnapshot(duration: TimeInterval, contextKeyCount: Int) {
        metrics.contextSnapshotDurations.append(duration)
        metrics.contextKeyCounts.append(contextKeyCount)
    }

    func recordApply(duration: TimeInterval) {
        metrics.contextApplyDurations.append(duration)
    }

    func recordBatch(size: Int) {
        metrics.runnableBatchSizes.append(size)
    }

    func recordTransition(nodeID: String, request: GraphTransitionRequest, decision: String) {
        metrics.transitionDecisions.append("\(nodeID):\(request.kind):\(decision)")
    }

    func finish() -> GraphRunMetrics {
        metrics.finishedAt = Date()
        return metrics
    }
}

extension GraphScheduler {
    func runNode(
        _ node: GraphNode,
        graph: OrchestrationGraph,
        agentSelector: GraphAgentSelector,
        retryController: GraphRetryController,
        safetyGateHandler: GraphSafetyGateHandler,
        transitionPolicy: GraphTransitionPolicy,
        registry: AgentRegistry,
        context: ResolutionContext,
        contextStore: ResolutionContextStore,
        eventBus: AgentEventBus,
        policy: OrchestratorPolicyEngine,
        circuitBreakers: CircuitBreakerRegistry,
        runID: UUID,
        schedulerOptions: GraphSchedulerExecutionOptions,
        metrics: GraphRunMetricsRecorder
    ) async -> GraphNodeOutcome {
        let selection = agentSelector.selectAgent(for: node, graph: graph, registry: registry)
        guard let selection else {
            await markSkipped(
                node: node,
                selectedAgentID: nil,
                eventBus: eventBus,
                runID: runID,
                metrics: metrics,
                detail: "Agent unavailable"
            )

            if let missingID = agentSelector.missingAgentID(for: node),
               policy.isMandatorySafetyGate(missingID) || node.executionPolicy == .safetyGate {
                let exit = await safetyGateHandler.failClosed(
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
            Logger(subsystem: "com.homeautomation.orchestrator", category: "GraphScheduler")
                .warning("Circuit breaker OPEN for graph node \(node.id, privacy: .public), agent \(agentID.rawValue, privacy: .public)")
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
            if safetyGateHandler.isSafetyGate(node: node, agentID: agentID, manifest: selection.manifest, policy: policy) {
                let exit = await safetyGateHandler.failClosed(
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

        let nodeSpanID = TelemetryTraceContext.makeSpanID()
        let baseTelemetryContext = (HomeAutomationTelemetryScope.current ?? HomeAutomationTelemetryContext())
            .merging(
                spanID: nodeSpanID,
                parentSpanID: HomeAutomationTelemetryScope.current?.spanID,
                spanKind: .graphNode,
                runID: runID.uuidString,
                operation: graph.goal.rawValue,
                graphID: graph.id,
                stage: node.id,
                graphNodeID: node.id,
                agentID: agentID.rawValue
            )
        await HomeAutomationTelemetryScope.$current.withValue(baseTelemetryContext) {
            await eventBus.publish(
                OrchestratorPipelineEvent(
                    runID: runID,
                    stage: node.id,
                    agentID: agentID.rawValue,
                    status: .running
                )
            )
        }
        await HomeAutomationTelemetry.shared.log(
            "graph.node.started",
            context: baseTelemetryContext,
            status: .running,
            spanKind: .graphNode,
            completedAt: nil
        )

        var attemptCount = 0
        var result: AgentRunResult
        var start: Date
        var end: Date

        repeat {
            attemptCount += 1
            start = Date()
            await metrics.markQueuedStart(nodeID: node.id, at: start)
            await metrics.markRunning(nodeID: node.id, agentID: agentID, startedAt: start)
            let agentSessionID = selection.agent.agentSessionID
            let agentRunID = await selection.agent.nextAgentRunID()
            let telemetryContext = baseTelemetryContext.merging(
                spanID: TelemetryTraceContext.makeSpanID(),
                parentSpanID: nodeSpanID,
                spanKind: .agentAttempt,
                agentInvocationID: Self.agentInvocationID(
                    runID: runID,
                    actionID: baseTelemetryContext.actionID,
                    conditionID: baseTelemetryContext.conditionID,
                    agentID: agentID.rawValue,
                    attempt: attemptCount
                ),
                agentSessionID: agentSessionID,
                agentRunID: agentRunID,
                attempt: attemptCount
            )
            let criticalPathMetadata = schedulerOptions.criticalPath?.nodeMetadata[node.id]
            let fmAdmissionContext = FMAdmissionContext(
                schedulerMode: schedulerOptions.foundationModelSchedulerMode,
                runID: runID.uuidString,
                graphID: graph.id,
                nodeID: node.id,
                agentID: agentID.rawValue,
                jobKind: nil,
                criticalPathRemainingMs: criticalPathMetadata?.estimatedRemainingServiceMs,
                estimatedServiceMs: criticalPathMetadata?.estimatedServiceMs,
                deadlineClass: node.executionPolicy == .safetyGate ? .interactive : .pipeline,
                cancellationClass: node.executionPolicy == .safetyGate ? .cancellationResistant : .normal,
                prefixAffinityKey: "\(graph.goal.rawValue):\(agentID.rawValue)",
                workflowScopeID: graph.id
            )
            await HomeAutomationTelemetry.shared.log(
                "agent.started",
                context: telemetryContext,
                status: "running",
                payload: [
                    "agentID": agentID.rawValue,
                    "agentSessionID": agentSessionID,
                    "agentRunID": String(agentRunID),
                    "timeoutMs": String(selection.agent.timeoutNanoseconds / 1_000_000),
                    "manifestCapabilities": selection.manifest.capabilities.map(\.rawValue).sorted().joined(separator: ",")
                ]
            )
            
            do {
                let detachedExecutor = DetachedAgentExecutor()
                result = try await withAgentTimeout(
                    agentID: agentID,
                    timeoutNanoseconds: selection.agent.timeoutNanoseconds
                ) {
                    await FMAdmissionContextScope.$current.withValue(fmAdmissionContext) {
                        await detachedExecutor.runDetached(
                            agent: selection.agent,
                            context: context,
                            telemetryContext: telemetryContext,
                            priority: .userInitiated
                        )
                    }
                }
            } catch is CancellationError {
                end = Date()
                await contextStore.appendTrace(
                    AgentTraceEntry(
                        agentID: agentID,
                        startedAt: start,
                        endedAt: end,
                        result: .skipped
                    )
                )
                await metrics.markFinished(
                    nodeID: node.id,
                    status: .skipped,
                    startedAt: start,
                    endedAt: end
                )
                await HomeAutomationTelemetry.shared.log(
                    "graph.node.cancelled",
                    context: telemetryContext,
                    status: .cancelled,
                    spanKind: .graphNode,
                    durationMs: end.timeIntervalSince(start) * 1_000,
                    payload: TelemetryPayload(values: [
                        "detail": .string("Graph scheduler cancelled sibling after terminal exit")
                    ])
                )
                await HomeAutomationTelemetryScope.$current.withValue(baseTelemetryContext) {
                    await eventBus.publish(
                        OrchestratorPipelineEvent(
                            runID: runID,
                            stage: node.id,
                            agentID: agentID.rawValue,
                            status: .skipped,
                            detail: "Graph scheduler cancelled sibling after terminal exit"
                        )
                    )
                }
                return GraphNodeOutcome(nodeID: node.id, exit: nil)
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
            await HomeAutomationTelemetry.shared.log(
                telemetryEventType(for: result),
                context: telemetryContext,
                status: eventStatus(for: result).rawValue,
                durationMs: end.timeIntervalSince(start) * 1_000,
                payload: [
                    "result": traceResult(for: result).rawValue,
                    "detail": detail(for: result)
                ]
            )

            await record(result: result, breaker: breaker, registry: circuitBreakers)
            await contextStore.appendTrace(
                AgentTraceEntry(
                    agentID: agentID,
                    startedAt: start,
                    endedAt: end,
                    result: traceResult(for: result)
                )
            )
            
            if retryController.shouldRetry(result: result, policy: policy, attemptCount: attemptCount) {
                Logger(subsystem: "com.homeautomation.orchestrator", category: "GraphScheduler")
                    .info("Retrying agent \(agentID.rawValue, privacy: .public) (attempt \(attemptCount + 1))")
                continue
            }
            break
        } while true

        switch result {
        case .success(let patch):
            await measuredApply(
                patch,
                contextStore: contextStore,
                graph: graph,
                runID: runID,
                metrics: metrics,
                stage: node.id
            )
        case .retryableFailure(let failure), .terminalFailure(let failure):
            await contextStore.appendError(failure)
        case .clarification, .unsupported:
            break
        }

        var transitionExit: AgentRunResult?
        if case .success(let patch) = result,
           let transitionRequest = patch.transitionRequest {
            transitionExit = await handleTransition(
                transitionRequest,
                node: node,
                agentID: agentID,
                manifest: selection.manifest,
                graph: graph,
                transitionPolicy: transitionPolicy,
                safetyGateHandler: safetyGateHandler,
                contextStore: contextStore,
                eventBus: eventBus,
                policy: policy,
                circuitBreakers: circuitBreakers,
                registry: registry,
                runID: runID,
                metrics: metrics
            )
        }

        let effectiveResult = transitionExit ?? result
        await HomeAutomationTelemetryScope.$current.withValue(baseTelemetryContext) {
            await eventBus.publish(
                OrchestratorPipelineEvent(
                    runID: runID,
                    stage: node.id,
                    agentID: agentID.rawValue,
                    status: eventStatus(for: effectiveResult),
                    detail: detail(for: effectiveResult)
                )
            )
        }
        await HomeAutomationTelemetry.shared.log(
            "graph.node.completed",
            context: baseTelemetryContext,
            status: eventStatus(for: effectiveResult) == .completed ? .completed : .failed,
            spanKind: .graphNode,
            durationMs: end.timeIntervalSince(start) * 1_000,
            payload: TelemetryPayload(values: [
                "detail": .string(detail(for: effectiveResult))
            ])
        )
        await metrics.markFinished(
            nodeID: node.id,
            status: eventStatus(for: effectiveResult) == .completed ? .completed : .failed,
            startedAt: start,
            endedAt: end
        )

        if safetyGateHandler.isSafetyGate(node: node, agentID: agentID, manifest: selection.manifest, policy: policy) {
            switch result {
            case .success:
                break
            default:
                let exit = await safetyGateHandler.failClosed(
                    for: agentID,
                    reason: "mandatory gate failed",
                    context: await measuredSnapshot(
                        contextStore: contextStore,
                        graph: graph,
                        runID: runID,
                        metrics: metrics,
                        stage: node.id
                    ),
                    contextStore: contextStore,
                    policy: policy
                )
                return GraphNodeOutcome(nodeID: node.id, exit: exit)
            }
        }

        if policy.isTerminalExit(effectiveResult) {
            return GraphNodeOutcome(nodeID: node.id, exit: effectiveResult)
        }

        if let transitionExit {
            return GraphNodeOutcome(nodeID: node.id, exit: transitionExit)
        }

        if shouldStopAfterContextResolution(
            await measuredSnapshot(
                contextStore: contextStore,
                graph: graph,
                runID: runID,
                metrics: metrics,
                stage: node.id
            ),
            after: agentID
        ) {
            return GraphNodeOutcome(nodeID: node.id, exit: result)
        }

        return GraphNodeOutcome(nodeID: node.id, exit: nil)
    }

    func markSkipped(
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

    func markPendingSkipped(
        _ pending: Set<String>,
        nodesByID: [String: GraphNode],
        agentSelector: GraphAgentSelector,
        registry: AgentRegistry,
        graph: OrchestrationGraph,
        eventBus: AgentEventBus,
        runID: UUID,
        metrics: GraphRunMetricsRecorder,
        reason: String
    ) async {
        for nodeID in pending.sorted() {
            guard let node = nodesByID[nodeID] else { continue }
            let agentID = agentSelector.selectAgent(for: node, graph: graph, registry: registry)?.agent.id
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

    func traceResult(for result: AgentRunResult) -> AgentTraceEntry.TraceResult {
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

    func eventStatus(for result: AgentRunResult) -> OrchestratorPipelineEvent.EventStatus {
        switch result {
        case .success:
            return .completed
        case .clarification, .unsupported, .retryableFailure, .terminalFailure:
            return .failed
        }
    }

    func detail(for result: AgentRunResult) -> String {
        switch result {
        case .success:
            return ""
        case .clarification(let value), .unsupported(let value):
            return value
        case .retryableFailure(let failure), .terminalFailure(let failure):
            return failure.reason
        }
    }

    func telemetryEventType(for result: AgentRunResult) -> String {
        switch result {
        case .success:
            return "agent.completed"
        case .clarification:
            return "agent.clarification"
        case .unsupported:
            return "agent.unsupported"
        case .retryableFailure(let failure), .terminalFailure(let failure):
            if failure.reason.localizedCaseInsensitiveContains("timed out") {
                return "agent.timeout"
            }
            return "agent.failed"
        }
    }

    static func agentInvocationID(
        runID: UUID,
        actionID: String?,
        conditionID: String?,
        agentID: String,
        attempt: Int
    ) -> String {
        let runPrefix = String(runID.uuidString.prefix(8))
        let scope = actionID ?? conditionID ?? "root"
        return "\(runPrefix)-\(scope)-\(agentID)-\(String(format: "%02d", attempt))"
    }
}
