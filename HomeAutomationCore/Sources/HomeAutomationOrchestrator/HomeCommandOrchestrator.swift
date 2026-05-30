import Foundation
import FoundationModels
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationRAG
import OSLog

/// Real-time updates emitted during command resolution.
public enum OrchestratorUpdate: Sendable {
    /// A diagnostic event detailing a specific stage of resolution.
    case event(OrchestratorPipelineEvent)
    /// The final output of the resolution process.
    case result(HomeAutomationResolverResult)
}

private struct DirectCommandExecutionResult: Sendable {
    let exit: AgentRunResult?
    let fallbackUsed: Bool
    let graphRun: GraphRunMetrics?
}

private struct AutomationCreationExecutionResult: Sendable {
    let result: HomeAutomationResolverResult
    let graph: OrchestrationGraph
    let graphRun: GraphRunMetrics?
}

private struct UnsupportedExecutionResult: Sendable {
    let result: HomeAutomationResolverResult
    let graph: OrchestrationGraph
    let graphRun: GraphRunMetrics?
}

private struct RootRoutingExecutionResult: Sendable {
    let detectedOperation: HomeOperationDetectionResult
    let routedOperation: HomeOperationDetectionResult
    let graphRun: GraphRunMetrics?
}

/// The primary entry point for processing home automation natural language commands.
///
/// `HomeCommandOrchestrator` coordinates the lifecycle of parsing user input, fetching RAG context,
/// executing multi-agent execution plans, validating constraints, and generating the final command resolution.
public final class HomeCommandOrchestrator: HomeCommandResolving, Sendable {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "HomeCommandOrchestrator")
    private let registry: AgentRegistry
    private let graphPlanner: GraphPlanner
    private let policy: OrchestratorPolicyEngine
    private let scheduler: GraphScheduler
    private let metricsCollector: OrchestratorMetricsCollector
    private let conversationMemory: ConversationMemory
    private let circuitBreakers: CircuitBreakerRegistry
    private let deviceRegistry: any DeviceRegistryProtocol
    private let smartThingsRuleCreator: (any SmartThingsRuleCreating)?

    public init(
        dependencies: HomeAutomationRuntimeDependencies
    ) {
        self.registry = dependencies.agentRegistry
        self.graphPlanner = dependencies.graphPlanner
        self.policy = dependencies.policy
        self.scheduler = dependencies.scheduler
        self.metricsCollector = dependencies.metricsCollector
        self.conversationMemory = dependencies.conversationMemory
        self.circuitBreakers = dependencies.circuitBreakers
        self.deviceRegistry = dependencies.deviceRegistry
        self.smartThingsRuleCreator = dependencies.smartThingsRuleCreator
    }

    public convenience init(
        coordinator: HomeAutomationCoordinator
    ) {
        self.init(dependencies: coordinator.makeRuntimeDependencies())
    }

    public convenience init(
        registry: AgentRegistry,
        policy: OrchestratorPolicyEngine,
        graphPlanner: GraphPlanner,
        scheduler: GraphScheduler,
        metricsCollector: OrchestratorMetricsCollector,
        conversationMemory: ConversationMemory,
        circuitBreakers: CircuitBreakerRegistry,
        deviceRegistry: any DeviceRegistryProtocol,
        automationDraftAgent: AutomationDraftAgent? = nil,
        smartThingsRuleCreator: (any SmartThingsRuleCreating)? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        }
    ) {
        _ = automationDraftAgent
        _ = foundationModelAvailability
        self.init(
            dependencies: HomeAutomationRuntimeDependencies(
                agentRegistry: registry,
                graphPlanner: graphPlanner,
                policy: policy,
                scheduler: scheduler,
                metricsCollector: metricsCollector,
                conversationMemory: conversationMemory,
                circuitBreakers: circuitBreakers,
                deviceRegistry: deviceRegistry,
                smartThingsRuleCreator: smartThingsRuleCreator
            )
        )
    }

    public convenience init(
        deviceRegistry: (any DeviceRegistryProtocol)? = nil,
        contextRetriever: ContextRetriever? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        foundationModelAvailabilityStatus: @escaping @Sendable () -> String? = { nil },
        metricsCollector: OrchestratorMetricsCollector? = nil,
        conversationMemory: ConversationMemory? = nil,
        circuitBreakers: CircuitBreakerRegistry? = nil,
        smartThingsRuleCreator: (any SmartThingsRuleCreating)? = nil
    ) {
        self.init(
            coordinator: HomeAutomationCoordinator(
                deviceRegistry: deviceRegistry,
                contextRetriever: contextRetriever,
                foundationModelAvailability: foundationModelAvailability,
                foundationModelAvailabilityStatus: foundationModelAvailabilityStatus,
                metricsCollector: metricsCollector,
                conversationMemory: conversationMemory,
                circuitBreakers: circuitBreakers,
                smartThingsRuleCreator: smartThingsRuleCreator
            )
        )
    }

    public static func makeDependencies(
        deviceRegistry: (any DeviceRegistryProtocol)? = nil,
        contextRetriever: ContextRetriever? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        foundationModelAvailabilityStatus: @escaping @Sendable () -> String? = { nil },
        metricsCollector: OrchestratorMetricsCollector? = nil,
        conversationMemory: ConversationMemory? = nil,
        circuitBreakers: CircuitBreakerRegistry? = nil,
        smartThingsRuleCreator: (any SmartThingsRuleCreating)? = nil
    ) -> HomeAutomationRuntimeDependencies {
        HomeAutomationCoordinator(
            deviceRegistry: deviceRegistry,
            contextRetriever: contextRetriever,
            foundationModelAvailability: foundationModelAvailability,
            foundationModelAvailabilityStatus: foundationModelAvailabilityStatus,
            metricsCollector: metricsCollector,
            conversationMemory: conversationMemory,
            circuitBreakers: circuitBreakers,
            smartThingsRuleCreator: smartThingsRuleCreator
        ).makeRuntimeDependencies()
    }

    /// Initializes a fully configured, RAG-enabled orchestrator.
    ///
    /// This async initializer prepares the Vector Store and indexes all canonical
    /// device capability knowledge before returning the orchestrator.
    public static func makeRAGEnabled(
        deviceRegistry: (any DeviceRegistryProtocol)? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        foundationModelAvailabilityStatus: @escaping @Sendable () -> String? = { nil },
        metricsCollector: OrchestratorMetricsCollector? = nil,
        indexCache: VectorIndexCache = VectorIndexCache(),
        smartThingsRuleCreator: (any SmartThingsRuleCreating)? = nil
    ) async -> HomeCommandOrchestrator {
        let baseCoordinator = HomeAutomationCoordinator(
            deviceRegistry: deviceRegistry,
            foundationModelAvailability: foundationModelAvailability,
            foundationModelAvailabilityStatus: foundationModelAvailabilityStatus,
            metricsCollector: metricsCollector,
            smartThingsRuleCreator: smartThingsRuleCreator
        )
        let indexer = baseCoordinator.ragCoordinator.makeKnowledgeIndexer(cache: indexCache)
        await indexer.indexCanonicalKnowledge(deviceRegistry: baseCoordinator.deviceRegistry)
        let retriever = await indexer.makeRetriever()
        return HomeAutomationCoordinator(
            deviceRegistry: baseCoordinator.deviceRegistry,
            contextRetriever: retriever,
            foundationModelAvailability: foundationModelAvailability,
            foundationModelAvailabilityStatus: foundationModelAvailabilityStatus,
            metricsCollector: baseCoordinator.metricsCollector,
            conversationMemory: baseCoordinator.conversationMemory,
            circuitBreakers: baseCoordinator.circuitBreakers,
            smartThingsRuleCreator: smartThingsRuleCreator
        ).makeOrchestrator()
    }

    /// Synchronously waits for the complete resolution of a user command.
    ///
    /// - Parameters:
    ///   - text: The natural language command.
    ///   - executeLowRiskCommands: Whether to automatically mock execution for low risk intents.
    /// - Returns: The final `HomeAutomationResolverResult`.
    public func resolve(_ text: String, executeLowRiskCommands: Bool) async throws -> HomeAutomationResolverResult {
        try await resolve(
            text,
            executeLowRiskCommands: executeLowRiskCommands,
            automationCreationOptions: .dryRun
        )
    }

    public func resolve(
        _ text: String,
        executeLowRiskCommands: Bool = true,
        automationCreationOptions: SmartThingsRuleCreationOptions = .dryRun
    ) async throws -> HomeAutomationResolverResult {
        logger.info("Resolving text command synchronously: '\(text, privacy: .private)'")
        var finalResult: HomeAutomationResolverResult?
        for try await update in resolveStream(
            text,
            executeLowRiskCommands: executeLowRiskCommands,
            automationCreationOptions: automationCreationOptions
        ) {
            if case .result(let result) = update {
                finalResult = result
            }
        }
        guard let finalResult else {
            throw FoundationLabCoreError.invalidRequest("Orchestrator stream ended without a result")
        }
        return finalResult
    }

    /// Returns an asynchronous stream of real-time updates as the command is resolved.
    ///
    /// The stream emits intermediate `.event` updates and terminates with a final `.result`.
    public func resolveStream(
        _ text: String,
        executeLowRiskCommands: Bool = true,
        automationCreationOptions: SmartThingsRuleCreationOptions = .dryRun
    ) -> AsyncThrowingStream<OrchestratorUpdate, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedText.isEmpty else {
                    logger.error("Rejecting empty command request.")
                    continuation.finish(throwing: FoundationLabCoreError.invalidRequest("Missing home command"))
                    return
                }

                logger.info("Starting resolution stream for command: '\(trimmedText, privacy: .private)'")
                let request = CommandRequest(
                    text: trimmedText,
                    executeLowRiskCommands: executeLowRiskCommands,
                    automationCreationOptions: automationCreationOptions
                )
                let contextStore = ResolutionContextStore(request: request)
                if ConversationMemoryReferenceDetector.containsMemoryReference(trimmedText),
                   let hint = await conversationMemory.lastResolvedDeviceHint() {
                    logger.debug("Injecting conversational memory hint.")
                    await contextStore.appendMemoryHint(hint)
                }
                let eventBus = AgentEventBus()
                let runID = UUID()
                let traceID = runID.uuidString
                let runSpanID = TelemetryTraceContext.makeSpanID()
                let runTelemetryContext = HomeAutomationTelemetryContext(
                    traceID: traceID,
                    spanID: runSpanID,
                    spanKind: .run,
                    runID: runID.uuidString,
                    stage: "input",
                    runtimeMode: "graph"
                )
                let eventForwarder = Task {
                    for await event in await eventBus.stream() {
                        continuation.yield(.event(event))
                    }
                }

                let inputEvent = OrchestratorPipelineEvent(
                    runID: runID,
                    stage: "input",
                    status: .completed,
                    detail: trimmedText
                )
                await eventBus.publish(inputEvent)
                await HomeAutomationTelemetry.shared.log(
                    "run.started",
                    context: runTelemetryContext,
                    status: "running",
                    payload: [
                        "command": trimmedText,
                        "executeLowRiskCommands": String(executeLowRiskCommands),
                        "automationCreationMode": automationCreationOptions.mode.rawValue
                    ]
                )

                var metrics = OrchestratorMetrics(command: trimmedText)
                metrics.foundationModelUsage.modelAvailabilityStatus = policy.modelAvailabilityStatus()

                let rootRouting = await HomeAutomationTelemetryScope.$current.withValue(
                    runTelemetryContext.merging(operation: OrchestrationGoal.rootRouting.rawValue)
                ) {
                    await executeRootRoutingPipeline(
                        text: trimmedText,
                        contextStore: contextStore,
                        eventBus: eventBus,
                        runID: runID
                    )
                }
                let detectedOperation = rootRouting.detectedOperation
                let operation = rootRouting.routedOperation
                let pipelineTelemetryContext = HomeAutomationTelemetryContext(
                    traceID: traceID,
                    spanID: runSpanID,
                    spanKind: .run,
                    runID: runID.uuidString,
                    operation: operation.operation.rawValue,
                    runtimeMode: "graph"
                )
                let operationEvent = OrchestratorPipelineEvent(
                    runID: runID,
                    stage: "operationRouting",
                    agentID: "operationDetection",
                    status: .completed,
                    detail: Self.operationEventDetail(
                        detected: detectedOperation,
                        routed: operation
                    )
                )
                await eventBus.publish(operationEvent)
                await HomeAutomationTelemetry.shared.log(
                    "run.operationDetected",
                    context: pipelineTelemetryContext.merging(
                        stage: "operationDetection",
                        agentID: AgentID.operationDetection.rawValue
                    ),
                    status: "completed",
                    payload: [
                        "detectedOperation": detectedOperation.operation.rawValue,
                        "routedOperation": operation.operation.rawValue,
                        "domain": String(describing: operation.domain),
                        "confidence": String(operation.confidence),
                        "reason": operation.reason
                    ]
                )

                if operation.operation == .automationCreation {
                    let started = Date()
                    let execution = await HomeAutomationTelemetryScope.$current.withValue(pipelineTelemetryContext) {
                        await executeAutomationCreationPipeline(
                            text: trimmedText,
                            operation: operation,
                            contextStore: contextStore,
                            eventBus: eventBus,
                            runID: runID
                        )
                    }
                    let result = execution.result
                    metrics.finishedAt = Date()
                    metrics.agentTraces = await contextStore.snapshot().trace
                    metrics.outcome = Self.outcomeName(for: result.resolution)
                    metrics.totalDuration = metrics.finishedAt?.timeIntervalSince(started)
                    metrics.circuitStates = await circuitBreakers.allStatusStrings()
                    metrics.captureAutomationFields(
                        operation: operation,
                        graph: execution.graph,
                        result: result,
                        graphRun: execution.graphRun
                    )
                    await metricsCollector.store(metrics)

                    let outcomeEvent = OrchestratorPipelineEvent(
                        runID: runID,
                        stage: "outcome",
                        status: .completed,
                        detail: result.resolution.displaySummary
                    )
                    await eventBus.publish(outcomeEvent)
                    await HomeAutomationTelemetry.shared.log(
                        "run.completed",
                        context: pipelineTelemetryContext.merging(stage: "outcome"),
                        status: "completed",
                        durationMs: metrics.totalDuration.map { $0 * 1_000 },
                        payload: [
                            "outcome": metrics.outcome,
                            "resolution": result.resolution.displaySummary
                        ]
                    )
                    await eventBus.finish()
                    await eventForwarder.value
                    continuation.yield(.result(result))
                    continuation.finish()
                    return
                }

                if operation.operation != .executeDeviceCommand {
                    let execution = await HomeAutomationTelemetryScope.$current.withValue(pipelineTelemetryContext) {
                        await executeUnsupportedPipeline(
                            text: trimmedText,
                            operation: operation,
                            contextStore: contextStore,
                            eventBus: eventBus,
                            runID: runID
                        )
                    }
                    let result = execution.result
                    metrics.finishedAt = Date()
                    metrics.agentTraces = await contextStore.snapshot().trace
                    metrics.outcome = Self.outcomeName(for: result.resolution)
                    metrics.totalDuration = metrics.finishedAt?.timeIntervalSince(metrics.startedAt)
                    metrics.graphRun = execution.graphRun
                    metrics.circuitStates = await circuitBreakers.allStatusStrings()
                    await metricsCollector.store(metrics)

                    let outcomeEvent = OrchestratorPipelineEvent(
                        runID: runID,
                        stage: "outcome",
                        status: .completed,
                        detail: result.resolution.displaySummary
                    )
                    await eventBus.publish(outcomeEvent)
                    await HomeAutomationTelemetry.shared.log(
                        "run.completed",
                        context: pipelineTelemetryContext.merging(stage: "outcome"),
                        status: "completed",
                        durationMs: metrics.totalDuration.map { $0 * 1_000 },
                        payload: [
                            "outcome": metrics.outcome,
                            "resolution": result.resolution.displaySummary
                        ]
                    )
                    await eventBus.finish()
                    await eventForwarder.value
                    continuation.yield(.result(result))
                    continuation.finish()
                    return
                }

                let execution = await HomeAutomationTelemetryScope.$current.withValue(pipelineTelemetryContext) {
                    await executeDirectCommandPipeline(
                        text: trimmedText,
                        contextStore: contextStore,
                        eventBus: eventBus,
                        runID: runID
                    )
                }
                let exit = execution.exit

                let ctx = await contextStore.snapshot()
                let resolution = ctx.resolution ?? Self.resolution(from: exit)
                let result = HomeAutomationResolverResult(
                    state: ctx.resolutionState ?? Self.makeFallbackState(for: trimmedText),
                    retrievedCandidates: ctx.retrievedCandidates,
                    aggregation: ctx.aggregation ?? HomeCandidateAggregationResult(
                        finalCandidateIDs: ctx.selectedCandidateIDs,
                        needsClarification: false,
                        confidence: 0
                    ),
                    hydratedCandidates: ctx.hydratedCandidates,
                    draft: ctx.draft,
                    resolution: resolution
                )

                metrics.finishedAt = Date()
                metrics.agentTraces = ctx.trace
                metrics.outcome = Self.outcomeName(for: result.resolution)
                metrics.fallbackUsed = execution.fallbackUsed
                metrics.graphRun = execution.graphRun
                metrics.totalDuration = metrics.finishedAt?.timeIntervalSince(metrics.startedAt)
                metrics.circuitStates = await circuitBreakers.allStatusStrings()
                metrics.captureEvaluationFields(context: ctx, result: result)
                await metricsCollector.store(metrics)
                await conversationMemory.append(Self.memoryTurn(for: result, userText: trimmedText))

                let outcomeEvent = OrchestratorPipelineEvent(
                    runID: runID,
                    stage: "outcome",
                    status: .completed,
                    detail: result.resolution.displaySummary
                )
                await eventBus.publish(outcomeEvent)
                await HomeAutomationTelemetry.shared.log(
                    "run.completed",
                    context: pipelineTelemetryContext.merging(stage: "outcome"),
                    status: "completed",
                    durationMs: metrics.totalDuration.map { $0 * 1_000 },
                    payload: [
                        "outcome": metrics.outcome,
                        "resolution": result.resolution.displaySummary
                    ]
                )
                await eventBus.finish()
                await eventForwarder.value
                continuation.yield(.result(result))
                logger.info("Stream resolution completed successfully.")
                continuation.finish()
            }
        }
    }

    public func lastMetricsJSON() async -> String? {
        await metricsCollector.lastJSON()
    }

    public func lastMetrics() async -> OrchestratorMetrics? {
        await metricsCollector.lastMetrics()
    }

    public func circuitBreakerStatuses() async -> [String: String] {
        await circuitBreakers.allStatusStrings()
    }

    private func executeRootRoutingPipeline(
        text: String,
        contextStore: ResolutionContextStore,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> RootRoutingExecutionResult {
        let plan = graphPlanner.planRootRouting(
            for: text,
            context: await contextStore.snapshot()
        )
        let schedulerResult = await scheduler.execute(
            plan.graph,
            registry: registry,
            contextStore: contextStore,
            eventBus: eventBus,
            policy: policy,
            circuitBreakers: circuitBreakers,
            runID: runID
        )
        let context = await contextStore.snapshot()
        let detectedOperation = context.operation ?? HomeOperationDetectionResult(
            domain: .unsupported,
            operation: .unsupported,
            confidence: 0,
            reason: Self.resolution(from: schedulerResult.exit).displaySummary
        )
        let routedOperation = Self.supportedOperation(from: detectedOperation)
        if routedOperation != detectedOperation {
            await contextStore.setOperation(routedOperation)
        }
        return RootRoutingExecutionResult(
            detectedOperation: detectedOperation,
            routedOperation: routedOperation,
            graphRun: schedulerResult.metrics
        )
    }

    private func executeAutomationCreationPipeline(
        text: String,
        operation: HomeOperationDetectionResult,
        contextStore: ResolutionContextStore,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> AutomationCreationExecutionResult {
        let graph = graphPlanner.plan(
            for: text,
            context: await contextStore.snapshot(),
            operation: operation.operation
        ).graph

        await contextStore.setScopedValue(
            AutomationPipelineEventBridge(eventBus: eventBus, runID: runID),
            for: AutomationRuntimeContextKeys.pipelineEventBridge
        )
        let schedulerResult = await scheduler.execute(
            graph,
            registry: registry,
            contextStore: contextStore,
            eventBus: eventBus,
            policy: policy,
            circuitBreakers: circuitBreakers,
            runID: runID
        )
        let context = await contextStore.snapshot()
        let graphRun = Self.automationFanOutGraphRun(
            from: schedulerResult.metrics,
            context: context
        )
        let resolution = context.resolution ?? Self.resolution(from: schedulerResult.exit)
        let result = HomeAutomationResolverResult(
            state: context.resolutionState ?? HomeResolutionState.forOperation(text: text, operation: operation),
            retrievedCandidates: context.retrievedCandidates,
            aggregation: context.aggregation ?? HomeCandidateAggregationResult(
                finalCandidateIDs: context.selectedCandidateIDs,
                needsClarification: false,
                confidence: 0
            ),
            hydratedCandidates: context.hydratedCandidates,
            draft: context.draft,
            resolution: resolution
        )
        return AutomationCreationExecutionResult(
            result: result,
            graph: graph,
            graphRun: graphRun
        )
    }

    private func executeUnsupportedPipeline(
        text: String,
        operation: HomeOperationDetectionResult,
        contextStore: ResolutionContextStore,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> UnsupportedExecutionResult {
        let graph = graphPlanner.plan(
            for: text,
            context: await contextStore.snapshot(),
            operation: .unsupported
        ).graph
        let schedulerResult = await scheduler.execute(
            graph,
            registry: registry,
            contextStore: contextStore,
            eventBus: eventBus,
            policy: policy,
            circuitBreakers: circuitBreakers,
            runID: runID
        )
        let context = await contextStore.snapshot()
        let resolution = context.resolution ?? Self.resolution(from: schedulerResult.exit)
        let result = HomeAutomationResolverResult(
            state: context.resolutionState ?? HomeResolutionState.forOperation(text: text, operation: operation),
            retrievedCandidates: context.retrievedCandidates,
            aggregation: context.aggregation ?? HomeCandidateAggregationResult(
                finalCandidateIDs: context.selectedCandidateIDs,
                needsClarification: false,
                confidence: operation.confidence
            ),
            hydratedCandidates: context.hydratedCandidates,
            draft: context.draft,
            resolution: resolution
        )
        return UnsupportedExecutionResult(
            result: result,
            graph: graph,
            graphRun: schedulerResult.metrics
        )
    }

    private static func automationFanOutGraphRun(
        from graphRun: GraphRunMetrics,
        context: ResolutionContext
    ) -> GraphRunMetrics {
        var output = graphRun

        if let aggregate = context.scopedValue(for: AutomationRuntimeContextKeys.actionResolutionAggregate) {
            for (index, result) in aggregate.results.enumerated() {
                let nodeID = "\(AgentID.automationActionResolution.rawValue):a\(index + 1)"
                output.nodeStatuses[nodeID] = result.isResolved ? .completed : .failed
                output.selectedAgents[nodeID] = AgentID.automationActionResolution.rawValue
            }
            output.subgraphRuns.append(contentsOf: aggregate.subgraphRuns)
        }

        if let records = context.scopedValue(for: AutomationRuntimeContextKeys.conditionOperandResolutionRecords) {
            for record in records {
                let nodeID = "\(AgentID.automationConditionOperandResolution.rawValue):\(record.id)"
                output.nodeStatuses[nodeID] = record.isResolved ? .completed : .failed
                output.selectedAgents[nodeID] = AgentID.automationConditionOperandResolution.rawValue
            }
        }

        return output
    }

    private func executeDirectCommandPipeline(
        text: String,
        contextStore: ResolutionContextStore,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> DirectCommandExecutionResult {
        logger.debug("Generating graph execution plan.")
        let plan = graphPlanner.plan(for: text, context: await contextStore.snapshot())
        let result = await scheduler.execute(
            plan.graph,
            registry: registry,
            contextStore: contextStore,
            eventBus: eventBus,
            policy: policy,
            circuitBreakers: circuitBreakers,
            runID: runID
        )
        return DirectCommandExecutionResult(
            exit: result.exit,
            fallbackUsed: plan.isFallbackOnly,
            graphRun: result.metrics
        )
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

    private static func outcomeName(for resolution: HomeCommandResolution) -> String {
        switch resolution {
        case .readyToExecute:
            return "readyToExecute"
        case .executed:
            return "executed"
        case .requiresConfirmation:
            return "requiresConfirmation"
        case .automationDrafted:
            return "automationDrafted"
        case .automationRequiresConfirmation:
            return "automationRequiresConfirmation"
        case .needsClarification:
            return "needsClarification"
        case .unsupported:
            return "unsupported"
        }
    }

    private static func memoryTurn(for result: HomeAutomationResolverResult, userText: String) -> ConversationTurn {
        let selectedDeviceID = result.draft?.targetDeviceID ?? result.aggregation.finalCandidateIDs.first
        let selectedDevice = selectedDeviceID.flatMap { id in
            result.hydratedCandidates.first { $0.id == id } ??
                result.retrievedCandidates.first { $0.id == id }
        }
        let wasConfirmed: Bool = {
            if case .executed = result.resolution { return true }
            return false
        }()

        return ConversationTurn(
            userText: userText,
            resolvedDeviceID: selectedDeviceID,
            resolvedCapability: result.draft?.capability,
            wasConfirmed: wasConfirmed,
            riskLevel: selectedDevice?.riskLevel ?? result.state.risk.riskLevel
        )
    }

    private static func supportedOperation(
        from detected: HomeOperationDetectionResult
    ) -> HomeOperationDetectionResult {
        switch detected.operation {
        case .executeDeviceCommand, .automationCreation, .unsupported:
            return detected
        case .automationUpdate,
             .automationDeletion,
             .automationQuery,
             .sceneCreation,
             .routineExecution:
            return HomeOperationDetectionResult(
                domain: detected.domain,
                operation: .unsupported,
                confidence: detected.confidence,
                reason: "\(detected.operation.rawValue) is outside the supported scope. Only automation creation is currently supported."
            )
        }
    }

    private static func operationEventDetail(
        detected: HomeOperationDetectionResult,
        routed: HomeOperationDetectionResult
    ) -> String {
        let confidence = String(format: "%.2f", routed.confidence)
        guard detected.operation != routed.operation else {
            return "\(routed.operation.rawValue) confidence=\(confidence)"
        }
        return "\(routed.operation.rawValue) confidence=\(confidence) detected=\(detected.operation.rawValue)"
    }

    private static func makeFallbackState(for text: String) -> HomeResolutionState {
        HomeResolutionState(
            rawText: text,
            language: HomeLanguageDetectionResult(
                languageCode: "en",
                isMixedLanguage: false,
                confidence: 0.4,
                unsupportedLanguageLikely: false
            ),
            domain: HomeDomainClassificationResult(domain: .unsupported, confidence: 0.4),
            intent: HomeIntentFamilyResult(topFamilies: [.unsupported], confidence: 0.4),
            deviceType: HomeDeviceTypeResult(deviceTypes: [], confidence: 0.4),
            slots: HomeSlotExtractionResult(
                rooms: [],
                deviceNicknames: [],
                values: [],
                modes: [],
                confidence: 0.4
            ),
            risk: HomeRiskClassificationResult(
                riskLevel: .low,
                requiresConfirmation: false,
                reason: "Orchestrator fallback state",
                confidence: 0.4
            )
        )
    }

}
