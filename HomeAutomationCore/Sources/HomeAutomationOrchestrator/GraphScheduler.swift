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
        let metrics = GraphRunMetricsRecorder(graph: graph)
        let initialContext = await measuredSnapshot(
            contextStore: contextStore,
            graph: graph,
            runID: runID,
            metrics: metrics,
            stage: "validation"
        )
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

        let firstExit = await withTaskGroup(
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
                                        graphNodeID: node.id,
                                        runtimeMode: "graph"
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

        if let interruption {
            return GraphSchedulerResult(
                exit: nil,
                metrics: await metrics.finish(),
                interruption: interruption
            )
        }

        if let firstExit {
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
        return GraphSchedulerResult(exit: nil, metrics: await metrics.finish())
    }

    private func measuredSnapshot(
        contextStore: ResolutionContextStore,
        graph: OrchestrationGraph,
        runID: UUID,
        metrics: GraphRunMetricsRecorder,
        stage: String
    ) async -> ResolutionContext {
        let start = Date()
        let context = await contextStore.snapshot()
        let duration = Date().timeIntervalSince(start)
        await metrics.recordSnapshot(duration: duration, contextKeyCount: context.contextKeyCount)
        await HomeAutomationTelemetry.shared.log(
            "context.snapshot",
            context: HomeAutomationTelemetryScope.current?.merging(
                runID: runID.uuidString,
                operation: graph.goal.rawValue,
                graphID: graph.id,
                stage: stage,
                runtimeMode: "graph"
            ),
            status: "completed",
            durationMs: duration * 1_000,
            payload: [
                "contextKeyCount": String(context.contextKeyCount)
            ]
        )
        return context
    }

    private func measuredApply(
        _ patch: ResolutionContextPatch,
        contextStore: ResolutionContextStore,
        graph: OrchestrationGraph,
        runID: UUID,
        metrics: GraphRunMetricsRecorder,
        stage: String
    ) async {
        let start = Date()
        await contextStore.apply(patch)
        let duration = Date().timeIntervalSince(start)
        await metrics.recordApply(duration: duration)
        await HomeAutomationTelemetry.shared.log(
            "context.apply",
            context: HomeAutomationTelemetryScope.current?.merging(
                runID: runID.uuidString,
                operation: graph.goal.rawValue,
                graphID: graph.id,
                stage: stage,
                graphNodeID: stage,
                agentID: patch.agentID.rawValue,
                runtimeMode: "graph"
            ),
            status: "completed",
            durationMs: duration * 1_000,
            payload: [
                "updateCount": String(patch.updates.count),
                "scopedUpdateCount": String(patch.scopedUpdates.values.reduce(0) { $0 + $1.count }),
                "hasTransitionRequest": String(patch.transitionRequest != nil)
            ]
        )
    }

    private func resumeNodeIDs(
        from checkpoint: GraphCheckpointRecord?,
        graph: OrchestrationGraph,
        runID: UUID
    ) -> Set<String> {
        guard let checkpoint,
              checkpoint.runID == runID.uuidString,
              checkpoint.graphID == graph.id else {
            return []
        }
        return Set(checkpoint.completedNodeIDs)
    }

    private func saveCheckpoint(
        options: GraphSchedulerExecutionOptions,
        graph: OrchestrationGraph,
        runID: UUID,
        dependencies: GraphDependencyTracker,
        context: ResolutionContext,
        lastCompletedNodeID: String?
    ) async {
        guard let checkpointStore = options.checkpointStore else { return }
        let checkpoint = await makeCheckpoint(
            graph: graph,
            runID: runID,
            dependencies: dependencies,
            context: context,
            lastCompletedNodeID: lastCompletedNodeID
        )
        await checkpointStore.save(checkpoint)
    }

    private func makeCheckpoint(
        graph: OrchestrationGraph,
        runID: UUID,
        dependencies: GraphDependencyTracker,
        context: ResolutionContext,
        lastCompletedNodeID: String?,
        interruptedBeforeNodeID: String? = nil,
        interrupt: GraphInterrupt? = nil
    ) async -> GraphCheckpointRecord {
        GraphCheckpointRecord(
            runID: runID.uuidString,
            graphID: graph.id,
            goal: graph.goal.rawValue,
            completedNodeIDs: Array(dependencies.completedNodeIDs),
            pendingNodeIDs: Array(dependencies.pendingNodeIDs),
            lastCompletedNodeID: lastCompletedNodeID,
            interruptedBeforeNodeID: interruptedBeforeNodeID,
            interrupt: interrupt,
            contextKeys: contextKeys(in: context)
        )
    }

    private func contextKeys(in context: ResolutionContext) -> [String] {
        var keys: [String] = ["request.text", "request.executeLowRiskCommands"]
        if context.operation != nil { keys.append(ResolutionContextPatchKey.operation.rawValue) }
        if context.language != nil { keys.append(ResolutionContextPatchKey.language.rawValue) }
        if context.domain != nil { keys.append(ResolutionContextPatchKey.domain.rawValue) }
        if context.intent != nil { keys.append(ResolutionContextPatchKey.intent.rawValue) }
        if context.deviceType != nil { keys.append(ResolutionContextPatchKey.deviceType.rawValue) }
        if context.slots != nil { keys.append(ResolutionContextPatchKey.slots.rawValue) }
        if context.risk != nil { keys.append(ResolutionContextPatchKey.risk.rawValue) }
        if context.resolutionState != nil { keys.append(ResolutionContextPatchKey.resolutionState.rawValue) }
        if !context.retrievedCandidates.isEmpty { keys.append(ResolutionContextPatchKey.retrievedCandidates.rawValue) }
        if !context.selectedCandidateIDs.isEmpty { keys.append(ResolutionContextPatchKey.selectedCandidateIDs.rawValue) }
        if context.aggregation != nil { keys.append(ResolutionContextPatchKey.aggregation.rawValue) }
        if !context.hydratedCandidates.isEmpty { keys.append(ResolutionContextPatchKey.hydratedCandidates.rawValue) }
        if context.capabilityDecision != nil { keys.append(ResolutionContextPatchKey.capabilityDecision.rawValue) }
        if !context.knowledgeSnippets.isEmpty { keys.append(ResolutionContextPatchKey.knowledgeSnippets.rawValue) }
        if !context.retrievalReports.isEmpty { keys.append(ResolutionContextPatchKey.retrievalReports.rawValue) }
        if !context.memoryHints.isEmpty { keys.append("memoryHints") }
        if context.instructionPackage != nil { keys.append(ResolutionContextPatchKey.instructionPackage.rawValue) }
        if context.draft != nil { keys.append(ResolutionContextPatchKey.draft.rawValue) }
        if context.executionPlan != nil { keys.append(ResolutionContextPatchKey.executionPlan.rawValue) }
        if context.resolution != nil { keys.append(ResolutionContextPatchKey.resolution.rawValue) }
        for (scope, values) in context.scopedValues {
            for key in values.keys {
                keys.append("scope.\(scope.description).\(key)")
            }
        }
        return keys
    }

    private func runNode(
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

        await eventBus.publish(
            OrchestratorPipelineEvent(
                runID: runID,
                stage: node.id,
                agentID: agentID.rawValue,
                status: .running
            )
        )
        let baseTelemetryContext = (HomeAutomationTelemetryScope.current ?? HomeAutomationTelemetryContext())
            .merging(
                runID: runID.uuidString,
                operation: graph.goal.rawValue,
                graphID: graph.id,
                stage: node.id,
                graphNodeID: node.id,
                agentID: agentID.rawValue
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
            let telemetryContext = baseTelemetryContext.merging(
                agentInvocationID: Self.agentInvocationID(
                    runID: runID,
                    actionID: baseTelemetryContext.actionID,
                    conditionID: baseTelemetryContext.conditionID,
                    agentID: agentID.rawValue,
                    attempt: attemptCount
                ),
                attempt: attemptCount
            )
            await HomeAutomationTelemetry.shared.log(
                "agent.started",
                context: telemetryContext,
                status: "running",
                payload: [
                    "timeoutMs": String(selection.agent.timeoutNanoseconds / 1_000_000),
                    "manifestCapabilities": selection.manifest.capabilities.map(\.rawValue).sorted().joined(separator: ",")
                ]
            )
            
            do {
                result = try await withAgentTimeout(
                    agentID: agentID,
                    timeoutNanoseconds: selection.agent.timeoutNanoseconds
                ) {
                    await HomeAutomationTelemetryScope.$current.withValue(telemetryContext) {
                        await selection.agent.run(context: context)
                    }
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
                logger.info("Retrying agent \(agentID.rawValue, privacy: .public) (attempt \(attemptCount + 1))")
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
        await eventBus.publish(
            OrchestratorPipelineEvent(
                runID: runID,
                stage: node.id,
                agentID: agentID.rawValue,
                status: eventStatus(for: effectiveResult),
                detail: detail(for: effectiveResult)
            )
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

    private func handleTransition(
        _ request: GraphTransitionRequest,
        node: GraphNode,
        agentID: AgentID,
        manifest: AgentManifest,
        graph: OrchestrationGraph,
        transitionPolicy: GraphTransitionPolicy,
        safetyGateHandler: GraphSafetyGateHandler,
        contextStore: ResolutionContextStore,
        eventBus: AgentEventBus,
        policy: OrchestratorPolicyEngine,
        circuitBreakers: CircuitBreakerRegistry,
        registry: AgentRegistry,
        runID: UUID,
        metrics: GraphRunMetricsRecorder
    ) async -> AgentRunResult? {
        let context = await measuredSnapshot(
            contextStore: contextStore,
            graph: graph,
            runID: runID,
            metrics: metrics,
            stage: node.id
        )
        let decision = transitionPolicy.evaluate(
            request,
            node: node,
            agentID: agentID,
            manifest: manifest,
            context: context,
            graph: graph,
            safetyGateHandler: safetyGateHandler,
            policy: policy
        )
        let decisionSummary = decision.isApproved ? "approved" : "rejected:\(decision.detail)"
        await metrics.recordTransition(nodeID: node.id, request: request, decision: decisionSummary)
        await HomeAutomationTelemetry.shared.log(
            "graph.transition",
            context: HomeAutomationTelemetryScope.current?.merging(
                runID: runID.uuidString,
                operation: graph.goal.rawValue,
                graphID: graph.id,
                stage: node.id,
                graphNodeID: node.id,
                agentID: agentID.rawValue,
                runtimeMode: "graph"
            ),
            status: decision.isApproved ? "approved" : "rejected",
            payload: [
                "transitionKind": request.kind,
                "reason": request.reason,
                "decision": decision.detail
            ]
        )

        guard decision.isApproved else {
            let failure = AgentFailure(
                agentID: agentID,
                reason: "Graph transition \(request.kind) rejected: \(decision.detail)",
                isRetryable: false
            )
            await contextStore.appendError(failure)
            return .terminalFailure(failure)
        }

        switch request {
        case .routeToClarification(let question, _):
            let patch = ResolutionContextPatch(
                agentID: agentID,
                updates: [
                    ResolutionContextPatchKey.resolution.rawValue: AnySendableValue(HomeCommandResolution.needsClarification(question))
                ]
            )
            await measuredApply(
                patch,
                contextStore: contextStore,
                graph: graph,
                runID: runID,
                metrics: metrics,
                stage: node.id
            )
            return .clarification(question)
        case .routeToUnsupported(let reason):
            let patch = ResolutionContextPatch(
                agentID: agentID,
                updates: [
                    ResolutionContextPatchKey.resolution.rawValue: AnySendableValue(HomeCommandResolution.unsupported(reason))
                ]
            )
            await measuredApply(
                patch,
                contextStore: contextStore,
                graph: graph,
                runID: runID,
                metrics: metrics,
                stage: node.id
            )
            return .unsupported(reason)
        case .routeToFallback(let reason):
            let result = await GraphScheduler().execute(
                GraphPlanner.fallbackGraph(),
                registry: registry,
                contextStore: contextStore,
                eventBus: eventBus,
                policy: policy,
                circuitBreakers: circuitBreakers,
                runID: runID
            )
            if let exit = result.exit {
                return exit
            }
            let latest = await measuredSnapshot(
                contextStore: contextStore,
                graph: graph,
                runID: runID,
                metrics: metrics,
                stage: node.id
            )
            if latest.resolution != nil {
                return .success(ResolutionContextPatch(agentID: agentID))
            }
            return .unsupported("Fallback transition did not produce a resolution: \(reason)")
        case .insertConfirmationBeforeExecution(let reason):
            guard let draft = context.draft else {
                return .terminalFailure(
                    AgentFailure(
                        agentID: agentID,
                        reason: "Cannot insert confirmation without a command draft: \(reason)",
                        isRetryable: false
                    )
                )
            }
            let patch = ResolutionContextPatch(
                agentID: agentID,
                updates: [
                    ResolutionContextPatchKey.resolution.rawValue: AnySendableValue(HomeCommandResolution.requiresConfirmation(draft))
                ]
            )
            await measuredApply(
                patch,
                contextStore: contextStore,
                graph: graph,
                runID: runID,
                metrics: metrics,
                stage: node.id
            )
            return .success(patch)
        case .retryWithAlternateCapability(let capability, let command, let reason):
            var evidence = context.capabilityDecision?.evidence ?? []
            evidence.append("Graph transition requested alternate capability: \(reason)")
            let decision = HomeCapabilityDecision(
                selectedCapability: capability,
                selectedCommand: command,
                targetDeviceID: context.capabilityDecision?.targetDeviceID,
                alternatives: context.capabilityDecision?.alternatives ?? [],
                evidence: evidence,
                confidence: max(context.capabilityDecision?.confidence ?? 0, 0.7)
            )
            let patch = ResolutionContextPatch(
                agentID: agentID,
                updates: [
                    ResolutionContextPatchKey.capabilityDecision.rawValue: AnySendableValue(decision)
                ]
            )
            await measuredApply(
                patch,
                contextStore: contextStore,
                graph: graph,
                runID: runID,
                metrics: metrics,
                stage: node.id
            )
            return nil
        }
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

    private func telemetryEventType(for result: AgentRunResult) -> String {
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

    private static func agentInvocationID(
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

struct GraphAgentSelection: Sendable {
    let agent: any AnyHomeAgent
    let manifest: AgentManifest
}

private struct GraphNodeOutcome: Sendable {
    let nodeID: String
    let exit: AgentRunResult?
}

private actor GraphRunMetricsRecorder {
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
