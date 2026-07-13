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
        runID: UUID,
        options: GraphSchedulerExecutionOptions = GraphSchedulerExecutionOptions()
    ) async -> GraphSchedulerResult {
        logger.info("Starting graph \(graph.id, privacy: .public) for runID: \(runID, privacy: .public)")
        let graphStartedAt = Date()
        let inheritedTelemetry = HomeAutomationTelemetryScope.current
        let graphTelemetryContext = (inheritedTelemetry ?? HomeAutomationTelemetryContext())
            .merging(
                traceID: inheritedTelemetry?.traceID ?? runID.uuidString,
                spanID: TelemetryTraceContext.makeSpanID(),
                parentSpanID: inheritedTelemetry?.spanID,
                spanKind: .graph,
                runID: runID.uuidString,
                operation: graph.goal.rawValue,
                graphID: graph.id,
                stage: graph.id,
                runtimeMode: inheritedTelemetry?.runtimeMode
            )
        await HomeAutomationTelemetry.shared.log(
            "graph.started",
            context: graphTelemetryContext,
            status: .running,
            spanKind: .graph,
            startedAt: graphStartedAt,
            completedAt: nil,
            payload: TelemetryPayload(values: [
                "nodeCount": .int(graph.nodes.count),
                "entryNodeCount": .int(graph.entryNodeIDs.count)
            ])
        )
        let metrics = GraphRunMetricsRecorder(graph: graph)
        let initialContext = await HomeAutomationTelemetryScope.$current.withValue(graphTelemetryContext) {
            await measuredSnapshot(
                contextStore: contextStore,
                graph: graph,
                runID: runID,
                metrics: metrics,
                stage: "validation"
            )
        }
        let validationErrors = GraphValidator().validate(
            graph,
            registry: registry,
            initialContext: initialContext
        )
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

        let resumedNodeIDs = resumeNodeIDs(from: options.resumeFromCheckpoint, graph: graph, runID: runID)
        var dependencies = GraphDependencyTracker(graph: graph, completedNodeIDs: resumedNodeIDs)
        await metrics.markResumedCompleted(nodeIDs: dependencies.completedNodeIDs)
        let guardEvaluator = GraphGuardEvaluator()
        let agentSelector = GraphAgentSelector()
        let retryController = GraphRetryController()
        let safetyGateHandler = GraphSafetyGateHandler()
        let transitionPolicy = GraphTransitionPolicy()
        var interruption: GraphCheckpointRecord?

        let firstExit = await HomeAutomationTelemetryScope.$current.withValue(graphTelemetryContext) {
            await withTaskGroup(
            of: GraphNodeOutcome.self,
            returning: AgentRunResult?.self
            ) { group in
            var runningNodeIDs = Set<String>()
            var firstExit: AgentRunResult?

            while dependencies.hasPendingNodes || !runningNodeIDs.isEmpty {
                if firstExit == nil {
                    let context = await measuredSnapshot(
                        contextStore: contextStore,
                        graph: graph,
                        runID: runID,
                        metrics: metrics,
                        stage: "scheduler"
                    )
                    let candidates = dependencies.readyNodes(in: graph)
                        .filter { !runningNodeIDs.contains($0.id) }
                    for node in candidates {
                        await metrics.markReady(nodeID: node.id, at: Date())
                    }

                    var runnable: [GraphNode] = []
                    for node in candidates {
                        if !guardEvaluator.evaluate(node.guardCondition, context: context, graph: graph, policy: policy) {
                            dependencies.complete(node.id)
                            await markSkipped(
                                node: node,
                                selectedAgentID: agentSelector.missingAgentID(for: node),
                                eventBus: eventBus,
                                runID: runID,
                                metrics: metrics,
                                detail: "Graph guard not satisfied"
                            )
                            await saveCheckpoint(
                                options: options,
                                graph: graph,
                                runID: runID,
                                dependencies: dependencies,
                                context: await measuredSnapshot(
                                    contextStore: contextStore,
                                    graph: graph,
                                    runID: runID,
                                    metrics: metrics,
                                    stage: node.id
                                ),
                                lastCompletedNodeID: node.id
                            )
                            continue
                        }

                        if options.shouldInterrupt(before: node) {
                            if runningNodeIDs.isEmpty {
                                let checkpoint = await makeCheckpoint(
                                    graph: graph,
                                    runID: runID,
                                    dependencies: dependencies,
                                    context: context,
                                    lastCompletedNodeID: dependencies.completedNodeIDs.sorted().last,
                                    interruptedBeforeNodeID: node.id,
                                    interrupt: node.interrupt ?? GraphInterrupt(
                                        kind: .confirmation,
                                        reason: "Caller requested interruption before \(node.id)."
                                    )
                                )
                                await options.checkpointStore?.save(checkpoint)
                                await eventBus.publish(
                                    OrchestratorPipelineEvent(
                                        runID: runID,
                                        stage: node.id,
                                        agentID: agentSelector.missingAgentID(for: node)?.rawValue,
                                        status: .skipped,
                                        detail: checkpoint.interrupt?.reason ?? "Graph interrupted"
                                    )
                                )
                                await HomeAutomationTelemetry.shared.log(
                                    "graph.interrupted",
                                    context: HomeAutomationTelemetryScope.current?.merging(
                                        runID: runID.uuidString,
                                        operation: graph.goal.rawValue,
                                        graphID: graph.id,
                                        stage: node.id,
                                        graphNodeID: node.id
                                    ),
                                    status: "paused",
                                    payload: [
                                        "interruptedBeforeNodeID": node.id,
                                        "interruptKind": checkpoint.interrupt?.kind.rawValue ?? "",
                                        "reason": checkpoint.interrupt?.reason ?? ""
                                    ]
                                )
                                interruption = checkpoint
                                return Optional<AgentRunResult>.none
                            }
                            continue
                        }

                        runnable.append(node)
                    }

                    if !runnable.isEmpty {
                        await metrics.recordBatch(size: runnable.count)
                    }

                    for node in runnable {
                        runningNodeIDs.insert(node.id)
                        let startContext = context
                        group.addTask {
                            await self.runNode(
                                node,
                                graph: graph,
                                agentSelector: agentSelector,
                                retryController: retryController,
                                safetyGateHandler: safetyGateHandler,
                                transitionPolicy: transitionPolicy,
                                registry: registry,
                                context: startContext,
                                contextStore: contextStore,
                                eventBus: eventBus,
                                policy: policy,
                                circuitBreakers: circuitBreakers,
                                runID: runID,
                                schedulerOptions: options,
                                metrics: metrics
                            )
                        }
                    }

                    if runningNodeIDs.isEmpty && dependencies.hasPendingNodes {
                        let nextReady = dependencies.readyNodes(in: graph)
                        if !nextReady.isEmpty {
                            continue
                        }

                        let blockedNodes = dependencies.blockedNodes()
                        let allOptional = blockedNodes.allSatisfy { $0.executionPolicy == .optional }
                        if allOptional {
                            await markPendingSkipped(
                                dependencies.pendingNodeIDs,
                                nodesByID: dependencies.nodesByID,
                                agentSelector: agentSelector,
                                registry: registry,
                                graph: graph,
                                eventBus: eventBus,
                                runID: runID,
                                metrics: metrics,
                                reason: "Optional nodes blocked"
                            )
                            break
                        }

                        let blocked = dependencies.pendingNodeIDs.sorted().joined(separator: ", ")
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
                            dependencies.pendingNodeIDs,
                            nodesByID: dependencies.nodesByID,
                            agentSelector: agentSelector,
                            registry: registry,
                            graph: graph,
                            eventBus: eventBus,
                            runID: runID,
                            metrics: metrics,
                            reason: "Graph blocked"
                        )
                        return .terminalFailure(failure)
                    }
                }

                guard !runningNodeIDs.isEmpty else {
                    if firstExit != nil {
                        break
                    }
                    continue
                }

                guard let outcome = await group.next() else {
                    break
                }
                runningNodeIDs.remove(outcome.nodeID)
                dependencies.complete(outcome.nodeID)
                await saveCheckpoint(
                    options: options,
                    graph: graph,
                    runID: runID,
                    dependencies: dependencies,
                    context: await measuredSnapshot(
                        contextStore: contextStore,
                        graph: graph,
                        runID: runID,
                        metrics: metrics,
                        stage: outcome.nodeID
                    ),
                    lastCompletedNodeID: outcome.nodeID
                )
                if firstExit == nil, let exit = outcome.exit {
                    firstExit = exit
                    if !runningNodeIDs.isEmpty || dependencies.hasPendingNodes {
                        group.cancelAll()
                        await markPendingSkipped(
                            runningNodeIDs.union(dependencies.pendingNodeIDs),
                            nodesByID: dependencies.nodesByID,
                            agentSelector: agentSelector,
                            registry: registry,
                            graph: graph,
                            eventBus: eventBus,
                            runID: runID,
                            metrics: metrics,
                            reason: "Terminal graph exit"
                        )
                        return firstExit
                    }
                }
            }

            if firstExit != nil {
                await markPendingSkipped(
                    dependencies.pendingNodeIDs,
                    nodesByID: dependencies.nodesByID,
                    agentSelector: agentSelector,
                    registry: registry,
                    graph: graph,
                    eventBus: eventBus,
                    runID: runID,
                    metrics: metrics,
                    reason: "Terminal graph exit"
                )
            }
            return firstExit
            }
        }

        if let interruption {
            await HomeAutomationTelemetry.shared.log(
                "graph.completed",
                context: graphTelemetryContext,
                status: .skipped,
                spanKind: .graph,
                startedAt: graphStartedAt,
                durationMs: Date().timeIntervalSince(graphStartedAt) * 1_000,
                payload: TelemetryPayload(values: ["interrupted": .bool(true)])
            )
            return GraphSchedulerResult(
                exit: nil,
                metrics: await metrics.finish(),
                interruption: interruption
            )
        }

        if let firstExit {
            await HomeAutomationTelemetry.shared.log(
                "graph.completed",
                context: graphTelemetryContext,
                status: .failed,
                spanKind: .graph,
                startedAt: graphStartedAt,
                durationMs: Date().timeIntervalSince(graphStartedAt) * 1_000,
                payload: TelemetryPayload(values: ["terminalExit": .bool(true)])
            )
            return GraphSchedulerResult(exit: firstExit, metrics: await metrics.finish())
        }

        logger.info("Graph \(graph.id, privacy: .public) completed without terminal exit.")
        await saveCheckpoint(
            options: options,
            graph: graph,
            runID: runID,
            dependencies: dependencies,
            context: await contextStore.snapshot(),
            lastCompletedNodeID: dependencies.completedNodeIDs.sorted().last
        )
        await HomeAutomationTelemetry.shared.log(
            "graph.completed",
            context: graphTelemetryContext,
            status: .completed,
            spanKind: .graph,
            startedAt: graphStartedAt,
            durationMs: Date().timeIntervalSince(graphStartedAt) * 1_000
        )
        return GraphSchedulerResult(exit: nil, metrics: await metrics.finish())
    }
}
