import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import OSLog

/// Result of resolving a single automation action description through the direct-command pipeline.
public struct AutomationActionResolutionResult: Sendable {
    public let resolvedAction: HomeAutomationResolvedAction?
    public let retrievedCandidates: [HomeCandidateRecord]
    public let hydratedCandidates: [HomeCandidateRecord]
    public let selectedCandidateIDs: [String]
    public let draft: HomeCommandDraft?
    public let resolution: HomeCommandResolution
    public let aggregation: HomeCandidateAggregationResult

    public init(
        resolvedAction: HomeAutomationResolvedAction?,
        retrievedCandidates: [HomeCandidateRecord],
        hydratedCandidates: [HomeCandidateRecord],
        selectedCandidateIDs: [String],
        draft: HomeCommandDraft?,
        resolution: HomeCommandResolution,
        aggregation: HomeCandidateAggregationResult
    ) {
        self.resolvedAction = resolvedAction
        self.retrievedCandidates = retrievedCandidates
        self.hydratedCandidates = hydratedCandidates
        self.selectedCandidateIDs = selectedCandidateIDs
        self.draft = draft
        self.resolution = resolution
        self.aggregation = aggregation
    }

    /// Whether the action resolved to a usable command draft.
    public var isResolved: Bool {
        resolvedAction != nil
    }

    /// Whether the action requires user clarification.
    public var needsClarification: Bool {
        if case .needsClarification = resolution { return true }
        return false
    }

    /// Whether the action is unsupported.
    public var isUnsupported: Bool {
        if case .unsupported = resolution { return true }
        return false
    }

    /// Whether the resolved action requires confirmation due to risk.
    public var requiresConfirmation: Bool {
        if case .requiresConfirmation = resolution { return true }
        if case .readyToExecute(let plan) = resolution, plan.requiresConfirmation { return true }
        return false
    }
}

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
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "AutomationActionResolver")
    private let registry: AgentRegistry
    private let planner: AgentPlanner
    private let graphPlanner: GraphPlanner
    private let policy: OrchestratorPolicyEngine
    private let runtimeMode: OrchestratorRuntimeMode
    private let circuitBreakers: CircuitBreakerRegistry
    private let maxConcurrentActions: Int

    public init(
        registry: AgentRegistry,
        planner: AgentPlanner,
        graphPlanner: GraphPlanner,
        policy: OrchestratorPolicyEngine,
        runtimeMode: OrchestratorRuntimeMode = .graph,
        circuitBreakers: CircuitBreakerRegistry = CircuitBreakerRegistry(),
        maxConcurrentActions: Int = 1
    ) {
        self.registry = registry
        self.planner = planner
        self.graphPlanner = graphPlanner
        self.policy = policy
        self.runtimeMode = runtimeMode
        self.circuitBreakers = circuitBreakers
        self.maxConcurrentActions = max(1, maxConcurrentActions)
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

        // Create a fresh context store for this action.
        // executeLowRiskCommands is false to prevent any mock execution.
        let request = CommandRequest(text: actionText, executeLowRiskCommands: false)
        let contextStore = ResolutionContextStore(request: request)

        let execution = await executeDirectCommandPipeline(
            text: actionText,
            contextStore: contextStore,
            eventBus: eventBus,
            runID: runID
        )

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
            aggregation: aggregation
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
    /// - Returns: An array of results, one per action. If an action fails, the array
    ///   will contain results only up to and including the failed action.
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
                    let result = await self.resolve(actionText, eventBus: childEventBus, runID: runID)
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

    private static func namespacedPipelineEvent(
        _ event: OrchestratorPipelineEvent,
        actionID: String
    ) -> OrchestratorPipelineEvent {
        let agentID = event.agentID ?? event.stage
        return OrchestratorPipelineEvent(
            runID: event.runID,
            stage: "\(AgentID.automationActionResolution.rawValue):\(actionID)/\(event.stage)",
            agentID: "\(agentID):\(actionID)",
            status: event.status,
            detail: event.detail
        )
    }

    private func executeDirectCommandPipeline(
        text: String,
        contextStore: ResolutionContextStore,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> (exit: AgentRunResult?, fallbackUsed: Bool) {
        switch runtimeMode {
        case .legacy:
            let plan = planner.plan(for: text, context: await contextStore.snapshot())
            let scheduler = AgentScheduler(
                registry: registry,
                contextStore: contextStore,
                eventBus: eventBus,
                policy: policy,
                circuitBreakers: circuitBreakers,
                runID: runID
            )
            let exit = await scheduler.execute(plan)
            return (exit, plan.isFallbackOnly)
        case .graph:
            let plan = graphPlanner.plan(for: text, context: await contextStore.snapshot())
            let scheduler = GraphScheduler()
            let result = await scheduler.execute(
                plan.graph,
                registry: registry,
                contextStore: contextStore,
                eventBus: eventBus,
                policy: policy,
                circuitBreakers: circuitBreakers,
                runID: runID
            )
            return (result.exit, plan.isFallbackOnly)
        }
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
