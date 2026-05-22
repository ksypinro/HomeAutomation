import Foundation
import HomeAutomationAgents
import HomeAutomationCore

struct GraphTransitionPolicy: Sendable {
    enum Decision: Sendable, Hashable {
        case approved
        case rejected(String)

        var isApproved: Bool {
            if case .approved = self { return true }
            return false
        }

        var detail: String {
            switch self {
            case .approved:
                return "approved"
            case .rejected(let reason):
                return reason
            }
        }
    }

    func evaluate(
        _ request: GraphTransitionRequest,
        node: GraphNode,
        agentID: AgentID,
        manifest: AgentManifest,
        context: ResolutionContext,
        graph: OrchestrationGraph,
        safetyGateHandler: GraphSafetyGateHandler,
        policy: OrchestratorPolicyEngine
    ) -> Decision {
        if safetyGateHandler.isSafetyGate(node: node, agentID: agentID, manifest: manifest, policy: policy) {
            switch request {
            case .insertConfirmationBeforeExecution:
                return .approved
            default:
                return .rejected("Safety gates may only request confirmation insertion.")
            }
        }

        switch request {
        case .routeToClarification:
            return .approved
        case .routeToUnsupported:
            return .approved
        case .routeToFallback:
            return graph.goal == .executeDeviceCommand
                ? .approved
                : .rejected("Fallback transitions are only supported in direct-command graphs.")
        case .insertConfirmationBeforeExecution:
            return context.draft == nil
                ? .rejected("Cannot request confirmation without a command draft.")
                : .approved
        case .retryWithAlternateCapability:
            return agentID == .capabilityResolution
                ? .approved
                : .rejected("Only capability resolution may request alternate capability retry.")
        }
    }
}

extension GraphScheduler {
    func handleTransition(
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
}
