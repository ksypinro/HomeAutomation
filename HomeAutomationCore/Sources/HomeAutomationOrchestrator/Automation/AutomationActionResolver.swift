import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import OSLog

/// Resolves automation action descriptions into `HomeAutomationResolvedAction` values
/// by running each through the existing direct-command agent pipeline.
///
/// This service reuses NLU, candidate retrieval, ranking, hydration, draft generation,
/// safety validation, parameter validation, confirmation policy, and execution planning
/// agents — the same pipeline that powers direct commands. It explicitly prevents mock
/// execution so automation creation never modifies device state.
///
/// ## Usage
///
/// ```swift
/// let resolver = AutomationActionResolver(...)
/// let results = await resolver.resolveAll(["Turn on AC", "Turn off lamp"], ...)
/// ```
public struct AutomationActionResolver: Sendable {
    /// Actions fan out per-action subgraphs whose FM calls serialize on the
    /// shared on-device model; bounding concurrency keeps queue wait (and
    /// soft-timeout races) predictable.
    public static let defaultMaxConcurrentActions = 2

    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "AutomationActionResolver")
    private let registry: AgentRegistry
    private let graphPlanner: GraphPlanner
    private let policy: OrchestratorPolicyEngine
    private let subgraphRunner: GraphSubgraphRunner
    private let circuitBreakers: CircuitBreakerRegistry
    private let maxConcurrentActions: Int
    private let miniPipeline: AutomationActionMiniPipeline?

    public init(
        registry: AgentRegistry,
        graphPlanner: GraphPlanner,
        policy: OrchestratorPolicyEngine,
        scheduler: GraphScheduler,
        subgraphRunner: GraphSubgraphRunner,
        circuitBreakers: CircuitBreakerRegistry,
        maxConcurrentActions: Int = Self.defaultMaxConcurrentActions,
        miniPipeline: AutomationActionMiniPipeline? = nil
    ) {
        self.registry = registry
        self.graphPlanner = graphPlanner
        self.policy = policy
        self.subgraphRunner = subgraphRunner
        self.circuitBreakers = circuitBreakers
        self.maxConcurrentActions = max(1, maxConcurrentActions)
        self.miniPipeline = miniPipeline
    }

    /// Resolves a single action description through the direct-command pipeline.
    ///
    /// - Parameters:
    ///   - actionText: The natural language action (e.g., "Turn on AC").
    ///   - eventBus: Event bus for publishing pipeline progress.
    ///   - runID: The run identifier for tracing.
    /// - Returns: An `AutomationActionResolutionResult` containing the resolved action, candidates, and resolution status.
    public func resolve(
        _ actionText: String,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> AutomationActionResolutionResult {
        logger.info("Resolving automation action: '\(actionText, privacy: .private)'")

        if let miniPipeline {
            return await miniPipeline.resolve(actionText, eventBus: eventBus, runID: runID)
        }

        // Create a fresh context store for this action.
        // executeLowRiskCommands is false to prevent any mock execution.
        let request = CommandRequest(text: actionText, executeLowRiskCommands: false)
        let contextStore = ResolutionContextStore(request: request)
        await seedDirectCommandRoutingContext(for: actionText, in: contextStore)

        let actionID = HomeAutomationTelemetryScope.current?.actionID ?? "a1"
        let subgraphEventBus = AgentEventBus()
        let eventForwarder = Task {
            for await event in await subgraphEventBus.stream() {
                await eventBus.publish(
                    Self.namespacedPipelineEvent(
                        event,
                        actionID: actionID
                    )
                )
            }
        }
        let execution = await executeDirectCommandPipeline(
            text: actionText,
            actionID: actionID,
            contextStore: contextStore,
            eventBus: subgraphEventBus,
            runID: runID
        )
        await subgraphEventBus.finish()
        await eventForwarder.value

        let ctx = await contextStore.snapshot()
        let resolution = ctx.resolution ?? Self.resolution(from: execution.exit)

        let draft = ctx.draft
        let aggregation = ctx.aggregation ?? HomeCandidateAggregationResult(
            finalCandidateIDs: ctx.selectedCandidateIDs,
            needsClarification: false,
            confidence: 0
        )

        // Build the resolved action if we have a valid draft.
        let resolvedAction: HomeAutomationResolvedAction?
        if let draft {
            let selectedDevice = draft.targetDeviceID.flatMap { id in
                ctx.hydratedCandidates.first { $0.id == id } ??
                    ctx.retrievedCandidates.first { $0.id == id }
            }
            resolvedAction = HomeAutomationResolvedAction(
                originalText: actionText,
                draft: draft,
                device: selectedDevice,
                confidence: draft.confidence
            )
        } else {
            resolvedAction = nil
        }

        logger.info("Action '\(actionText, privacy: .private)' resolved: draft=\(draft != nil), device=\(resolvedAction?.device?.displayName ?? "none", privacy: .public)")

        return AutomationActionResolutionResult(
            resolvedAction: resolvedAction,
            retrievedCandidates: ctx.retrievedCandidates,
            hydratedCandidates: ctx.hydratedCandidates,
            selectedCandidateIDs: aggregation.finalCandidateIDs,
            draft: draft,
            resolution: resolution,
            aggregation: aggregation,
            subgraphRun: execution.subgraphRun
        )
    }

    /// Resolves all action descriptions independently and returns them in input order.
    ///
    /// Each action runs through its own direct-command pipeline with an isolated context store,
    /// so one action cannot overwrite another action's draft, candidates, or resolution.
    ///
    /// - Parameters:
    ///   - actionDescriptions: Natural language action descriptions.
    ///   - eventBus: Event bus for publishing pipeline progress.
    ///   - runID: The run identifier for tracing.
    /// - Returns: An array of results, one per action, preserving input order.
    public func resolveAll(
        _ actionDescriptions: [String],
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> [AutomationActionResolutionResult] {
        logger.info("Resolving \(actionDescriptions.count, privacy: .public) automation action(s).")
        guard !actionDescriptions.isEmpty else {
            await eventBus.publish(
                OrchestratorPipelineEvent(
                    runID: runID,
                    stage: "automationActionResolution",
                    agentID: "automationActionResolution",
                    status: .completed,
                    detail: "0/0 action(s) resolved"
                )
            )
            return []
        }

        let indexedResults = await withTaskGroup(of: (Int, AutomationActionResolutionResult).self) { group in
            var nextIndex = 0

            func enqueueNextAction() -> Bool {
                guard nextIndex < actionDescriptions.count else { return false }
                let index = nextIndex
                nextIndex += 1
                let actionText = actionDescriptions[index]

                group.addTask {
                    let actionID = "a\(index + 1)"
                    let inheritedContext = HomeAutomationTelemetryScope.current
                    let actionContext = HomeAutomationTelemetryContext(
                        runID: runID.uuidString,
                        operation: inheritedContext?.operation,
                        graphID: inheritedContext?.graphID,
                        stage: "automationActionResolution:\(actionID)",
                        graphNodeID: AgentID.automationActionResolution.rawValue,
                        agentID: AgentID.automationActionResolution.rawValue,
                        agentInvocationID: Self.actionInvocationID(runID: runID, actionID: actionID),
                        actionID: actionID,
                        runtimeMode: inheritedContext?.runtimeMode
                    )
                    let childEventBus = AgentEventBus()
                    let eventForwarder = Task {
                        for await event in await childEventBus.stream() {
                            await eventBus.publish(
                                Self.namespacedPipelineEvent(
                                    event,
                                    actionID: actionID
                                )
                            )
                        }
                    }
                    await eventBus.publish(
                        OrchestratorPipelineEvent(
                            runID: runID,
                            stage: "automationActionResolution:\(actionID)",
                            agentID: Self.actionAgentID(actionID),
                            status: .running,
                            detail: "[\(index + 1)/\(actionDescriptions.count)] \(actionText)"
                        )
                    )
                    let startedAt = Date()
                    await HomeAutomationTelemetry.shared.log(
                        "automation.action.started",
                        context: actionContext,
                        status: "running",
                        payload: [
                            "actionIndex": String(index + 1),
                            "actionCount": String(actionDescriptions.count),
                            "actionText": actionText
                        ]
                    )
                    let result = await HomeAutomationTelemetryScope.$current.withValue(actionContext) {
                        await self.resolve(actionText, eventBus: childEventBus, runID: runID)
                    }
                    await HomeAutomationTelemetry.shared.log(
                        "automation.action.completed",
                        context: actionContext,
                        status: result.isResolved ? "completed" : "failed",
                        durationMs: Date().timeIntervalSince(startedAt) * 1_000,
                        payload: [
                            "actionText": actionText,
                            "resolved": String(result.isResolved),
                            "resolution": result.resolution.displaySummary,
                            "selectedCandidateIDs": result.selectedCandidateIDs.joined(separator: ",")
                        ]
                    )
                    await childEventBus.finish()
                    await eventForwarder.value
                    await eventBus.publish(
                        OrchestratorPipelineEvent(
                            runID: runID,
                            stage: "automationActionResolution:\(actionID)",
                            agentID: Self.actionAgentID(actionID),
                            status: result.isResolved ? .completed : .failed,
                            detail: result.resolution.displaySummary
                        )
                    )
                    return (index, result)
                }
                return true
            }

            for _ in 0..<min(maxConcurrentActions, actionDescriptions.count) {
                _ = enqueueNextAction()
            }

            var results: [(Int, AutomationActionResolutionResult)] = []
            for await result in group {
                results.append(result)
                _ = enqueueNextAction()
            }
            return results
        }
        let orderedResults = indexedResults
            .sorted { $0.0 < $1.0 }
            .map(\.1)

        await eventBus.publish(
            OrchestratorPipelineEvent(
                runID: runID,
                stage: "automationActionResolution",
                agentID: "automationActionResolution",
                status: .completed,
                detail: "\(orderedResults.filter(\.isResolved).count)/\(actionDescriptions.count) action(s) resolved"
            )
        )

        return orderedResults
    }

    // MARK: - Private

    private static func actionAgentID(_ actionID: String) -> String {
        "\(AgentID.automationActionResolution.rawValue):\(actionID)"
    }

    private static func actionInvocationID(runID: UUID, actionID: String) -> String {
        "\(String(runID.uuidString.prefix(8)))-\(actionID)-\(AgentID.automationActionResolution.rawValue)"
    }

    private func seedDirectCommandRoutingContext(
        for actionText: String,
        in contextStore: ResolutionContextStore
    ) async {
        let deterministicState = AgentTextParser.deterministicState(
            for: actionText,
            confidence: 0.82,
            riskReason: "Seeded automation action routing context"
        )
        let operation = HomeOperationDetectionResult(
            domain: deterministicState.domain.domain,
            operation: deterministicState.domain.domain == .homeAutomation ? .executeDeviceCommand : .unsupported,
            confidence: deterministicState.domain.confidence,
            reason: "Automation action subgraph seeded direct-command routing context"
        )

        await contextStore.setOperation(operation)
        await contextStore.setLanguage(deterministicState.language)
        await contextStore.setDomain(deterministicState.domain)
        // Action fragments are short imperatives the deterministic parser handles
        // well; threshold-gate the subgraph NLU so the model is only consulted
        // when deterministic confidence is below the per-task thresholds.
        await contextStore.setArtifact(
            NLUModelCallMode.thresholdGated,
            for: ContextArtifactKeys.nluPolicyOverride()
        )
    }

    private static func namespacedPipelineEvent(
        _ event: OrchestratorPipelineEvent,
        actionID: String
    ) -> OrchestratorPipelineEvent {
        let prefix = "\(AgentID.automationActionResolution.rawValue):\(actionID)"
        let stage = event.stage == prefix || event.stage.hasPrefix("\(prefix)/")
            ? event.stage
            : "\(prefix)/\(event.stage)"
        return OrchestratorPipelineEvent(
            runID: event.runID,
            stage: stage,
            agentID: event.agentID,
            traceID: event.traceID,
            spanID: event.spanID,
            parentSpanID: event.parentSpanID,
            graphID: event.graphID,
            graphNodeID: event.graphNodeID,
            agentInvocationID: event.agentInvocationID,
            agentSessionID: event.agentSessionID,
            agentRunID: event.agentRunID,
            componentKind: event.componentKind,
            componentID: event.componentID,
            actionID: event.actionID ?? actionID,
            conditionID: event.conditionID,
            runtimeMode: event.runtimeMode,
            status: event.status,
            detail: event.detail
        )
    }

    private func executeDirectCommandPipeline(
        text: String,
        actionID: String,
        contextStore: ResolutionContextStore,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> (exit: AgentRunResult?, fallbackUsed: Bool, subgraphRun: HomeAutomationSubgraphRunSummary) {
        let plan = graphPlanner.plan(for: text, context: await contextStore.snapshot())
        let descriptor = GraphSubgraphDescriptor(
            id: "\(AgentID.automationActionResolution.rawValue):\(actionID)",
            parentNodeID: AgentID.automationActionResolution.rawValue,
            scopeID: actionID,
            inputSummary: text
        )
        let result = await subgraphRunner.execute(
            descriptor: descriptor,
            graph: plan.graph,
            registry: registry,
            contextStore: contextStore,
            eventBus: eventBus,
            policy: policy,
            circuitBreakers: circuitBreakers,
            runID: runID
        )
        return (result.schedulerResult.exit, plan.isFallbackOnly, result.summary)
    }

    private static func resolution(from exit: AgentRunResult?) -> HomeCommandResolution {
        guard let exit else {
            return .unsupported("No resolution produced")
        }
        switch exit {
        case .clarification(let question):
            return .needsClarification(question)
        case .unsupported(let reason):
            return .unsupported(reason)
        case .terminalFailure(let failure), .retryableFailure(let failure):
            return .unsupported(failure.reason)
        case .success:
            return .unsupported("No resolution produced")
        }
    }
}
