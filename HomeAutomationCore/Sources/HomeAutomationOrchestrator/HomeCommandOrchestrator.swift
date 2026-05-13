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

/// The primary entry point for processing home automation natural language commands.
///
/// `HomeCommandOrchestrator` coordinates the lifecycle of parsing user input, fetching RAG context,
/// executing multi-agent execution plans, validating constraints, and generating the final command resolution.
public final class HomeCommandOrchestrator: HomeCommandResolving, Sendable {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "HomeCommandOrchestrator")
    private let registry: AgentRegistry
    private let planner: AgentPlanner
    private let graphPlanner: GraphPlanner
    private let policy: OrchestratorPolicyEngine
    private let runtimeMode: OrchestratorRuntimeMode
    private let metricsCollector: OrchestratorMetricsCollector
    private let conversationMemory: ConversationMemory
    private let circuitBreakers: CircuitBreakerRegistry
    private let deviceRegistry: MockHomeDeviceRegistry
    private let operationDetector: HomeOperationDetectionService
    private let automationDraftAgent: AutomationDraftAgent
    private let conditionOperandResolver: AutomationConditionOperandResolver
    private let smartThingsCompiler: SmartThingsRuleCompiler

    public init(
        registry: AgentRegistry,
        planner: AgentPlanner,
        policy: OrchestratorPolicyEngine,
        runtimeMode: OrchestratorRuntimeMode = .legacy,
        deviceRegistry: MockHomeDeviceRegistry = MockHomeDeviceRegistry(),
        metricsCollector: OrchestratorMetricsCollector = OrchestratorMetricsCollector(),
        conversationMemory: ConversationMemory = ConversationMemory(),
        circuitBreakers: CircuitBreakerRegistry = CircuitBreakerRegistry(),
        automationDraftAgent: AutomationDraftAgent = AutomationDraftAgent()
    ) {
        self.registry = registry
        self.planner = planner
        self.graphPlanner = GraphPlanner(policy: policy)
        self.policy = policy
        self.runtimeMode = runtimeMode
        self.deviceRegistry = deviceRegistry
        self.metricsCollector = metricsCollector
        self.conversationMemory = conversationMemory
        self.circuitBreakers = circuitBreakers
        self.operationDetector = HomeOperationDetectionService()
        self.automationDraftAgent = automationDraftAgent
        self.conditionOperandResolver = AutomationConditionOperandResolver(registry: deviceRegistry)
        self.smartThingsCompiler = SmartThingsRuleCompiler()
    }

    public convenience init(
        deviceRegistry: MockHomeDeviceRegistry = MockHomeDeviceRegistry(),
        contextRetriever: ContextRetriever? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        foundationModelAvailabilityStatus: @escaping @Sendable () -> String? = { nil },
        runtimeMode: OrchestratorRuntimeMode = .legacy,
        metricsCollector: OrchestratorMetricsCollector = OrchestratorMetricsCollector(),
        conversationMemory: ConversationMemory = ConversationMemory(),
        circuitBreakers: CircuitBreakerRegistry = CircuitBreakerRegistry()
    ) {
        let policy = OrchestratorPolicyEngine(
            isModelAvailable: foundationModelAvailability,
            modelAvailabilityStatus: foundationModelAvailabilityStatus
        )
        self.init(
            registry: DefaultAgentRegistryFactory.make(
                registry: deviceRegistry,
                contextRetriever: contextRetriever,
                foundationModelAvailability: foundationModelAvailability
            ),
            planner: AgentPlanner(policy: policy),
            policy: policy,
            runtimeMode: runtimeMode,
            deviceRegistry: deviceRegistry,
            metricsCollector: metricsCollector,
            conversationMemory: conversationMemory,
            circuitBreakers: circuitBreakers,
            automationDraftAgent: AutomationDraftAgent(
                worker: AutomationDraftWorkerSession(foundationModelAvailability: foundationModelAvailability)
            )
        )
    }

    /// Initializes a fully configured, RAG-enabled orchestrator.
    ///
    /// This async initializer prepares the Vector Store and indexes all canonical
    /// device capability knowledge before returning the orchestrator.
    public static func makeRAGEnabled(
        deviceRegistry: MockHomeDeviceRegistry = MockHomeDeviceRegistry(),
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        foundationModelAvailabilityStatus: @escaping @Sendable () -> String? = { nil },
        runtimeMode: OrchestratorRuntimeMode = .legacy,
        metricsCollector: OrchestratorMetricsCollector = OrchestratorMetricsCollector(),
        indexCache: VectorIndexCache = VectorIndexCache()
    ) async -> HomeCommandOrchestrator {
        let conversationMemory = ConversationMemory()
        let circuitBreakers = CircuitBreakerRegistry()
        let indexer = KnowledgeIndexer(cache: indexCache)
        await indexer.indexCanonicalKnowledge(deviceRegistry: deviceRegistry)
        let retriever = await indexer.makeRetriever()
        return HomeCommandOrchestrator(
            deviceRegistry: deviceRegistry,
            contextRetriever: retriever,
            foundationModelAvailability: foundationModelAvailability,
            foundationModelAvailabilityStatus: foundationModelAvailabilityStatus,
            runtimeMode: runtimeMode,
            metricsCollector: metricsCollector,
            conversationMemory: conversationMemory,
            circuitBreakers: circuitBreakers
        )
    }

    /// Synchronously waits for the complete resolution of a user command.
    ///
    /// - Parameters:
    ///   - text: The natural language command.
    ///   - executeLowRiskCommands: Whether to automatically mock execution for low risk intents.
    /// - Returns: The final `HomeAutomationResolverResult`.
    public func resolve(_ text: String, executeLowRiskCommands: Bool = true) async throws -> HomeAutomationResolverResult {
        logger.info("Resolving text command synchronously: '\(text, privacy: .private)'")
        var finalResult: HomeAutomationResolverResult?
        for try await update in resolveStream(text, executeLowRiskCommands: executeLowRiskCommands) {
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
        executeLowRiskCommands: Bool = true
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
                let request = CommandRequest(text: trimmedText, executeLowRiskCommands: executeLowRiskCommands)
                let contextStore = ResolutionContextStore(request: request)
                if ConversationMemoryReferenceDetector.containsMemoryReference(trimmedText),
                   let hint = await conversationMemory.lastResolvedDeviceHint() {
                    logger.debug("Injecting conversational memory hint.")
                    await contextStore.appendMemoryHint(hint)
                }
                let eventBus = AgentEventBus()
                let runID = UUID()
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
                continuation.yield(.event(inputEvent))

                var metrics = OrchestratorMetrics(command: trimmedText)
                metrics.foundationModelUsage.modelAvailabilityStatus = policy.modelAvailabilityStatus()

                let operation = operationDetector.detect(trimmedText)
                let operationEvent = OrchestratorPipelineEvent(
                    runID: runID,
                    stage: "operationDetection",
                    agentID: "operationDetection",
                    status: .completed,
                    detail: "\(operation.operation.rawValue) confidence=\(String(format: "%.2f", operation.confidence))"
                )
                await eventBus.publish(operationEvent)
                continuation.yield(.event(operationEvent))

                if operation.operation == .automationCreation {
                    let started = Date()
                    let result = await resolveAutomationCreation(
                        text: trimmedText,
                        operation: operation,
                        eventBus: eventBus,
                        runID: runID
                    )
                    metrics.finishedAt = Date()
                    metrics.outcome = Self.outcomeName(for: result.resolution)
                    metrics.totalDuration = metrics.finishedAt?.timeIntervalSince(started)
                    metrics.circuitStates = await circuitBreakers.allStatusStrings()
                    await metricsCollector.store(metrics)

                    let outcomeEvent = OrchestratorPipelineEvent(
                        runID: runID,
                        stage: "outcome",
                        status: .completed,
                        detail: result.resolution.displaySummary
                    )
                    await eventBus.publish(outcomeEvent)
                    continuation.yield(.event(outcomeEvent))
                    continuation.yield(.result(result))
                    eventForwarder.cancel()
                    continuation.finish()
                    return
                }

                if operation.operation != .executeDeviceCommand {
                    let result = HomeAutomationResolverResult(
                        state: Self.makeOperationState(for: trimmedText, operation: operation),
                        retrievedCandidates: [],
                        aggregation: HomeCandidateAggregationResult(
                            finalCandidateIDs: [],
                            needsClarification: false,
                            confidence: operation.confidence
                        ),
                        hydratedCandidates: [],
                        draft: nil,
                        resolution: .unsupported("\(operation.operation.rawValue) is not implemented yet.")
                    )
                    metrics.finishedAt = Date()
                    metrics.outcome = Self.outcomeName(for: result.resolution)
                    metrics.totalDuration = metrics.finishedAt?.timeIntervalSince(metrics.startedAt)
                    metrics.circuitStates = await circuitBreakers.allStatusStrings()
                    await metricsCollector.store(metrics)

                    let outcomeEvent = OrchestratorPipelineEvent(
                        runID: runID,
                        stage: "outcome",
                        status: .completed,
                        detail: result.resolution.displaySummary
                    )
                    await eventBus.publish(outcomeEvent)
                    continuation.yield(.event(outcomeEvent))
                    continuation.yield(.result(result))
                    eventForwarder.cancel()
                    continuation.finish()
                    return
                }

                let execution = await executeDirectCommandPipeline(
                    text: trimmedText,
                    contextStore: contextStore,
                    eventBus: eventBus,
                    runID: runID
                )
                let exit = execution.exit

                if exit == nil, policy.canExecute(context: await contextStore.snapshot()) {
                    logger.info("Executing post-pipeline mock execution.")
                    let scheduler = AgentScheduler(
                        registry: registry,
                        contextStore: contextStore,
                        eventBus: eventBus,
                        policy: policy,
                        circuitBreakers: circuitBreakers,
                        runID: runID
                    )
                    _ = await scheduler.execute(
                        AgentExecutionPlan(phases: [
                            .sequential(AgentTask(.mockExecution))
                        ])
                    )
                }

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
                continuation.yield(.event(outcomeEvent))
                continuation.yield(.result(result))
                logger.info("Stream resolution completed successfully.")
                eventForwarder.cancel()
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

    private func resolveAutomationCreation(
        text: String,
        operation: HomeOperationDetectionResult,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> HomeAutomationResolverResult {
        let state = Self.makeOperationState(for: text, operation: operation)
        let draftOutput: AutomationDraftOutput
        do {
            draftOutput = try await automationDraftAgent.run(
                AutomationDraftInput(text: text, operation: operation),
                context: ResolutionContext(
                    request: CommandRequest(text: text, executeLowRiskCommands: false)
                )
            )
        } catch {
            return HomeAutomationResolverResult(
                state: state,
                retrievedCandidates: [],
                aggregation: HomeCandidateAggregationResult(
                    finalCandidateIDs: [],
                    needsClarification: false,
                    confidence: operation.confidence
                ),
                hydratedCandidates: [],
                draft: nil,
                resolution: .unsupported(error.localizedDescription)
            )
        }

        let ruleDraft: HomeAutomationRuleDraft
        do {
            ruleDraft = try draftOutput.makeRuleDraft()
        } catch {
            return HomeAutomationResolverResult(
                state: state,
                retrievedCandidates: [],
                aggregation: HomeCandidateAggregationResult(
                    finalCandidateIDs: [],
                    needsClarification: false,
                    confidence: operation.confidence
                ),
                hydratedCandidates: [],
                draft: nil,
                resolution: .unsupported(error.localizedDescription)
            )
        }

        await eventBus.publish(
            OrchestratorPipelineEvent(
                runID: runID,
                stage: "automationDraft",
                agentID: "automationDraft",
                status: .completed,
                detail: "\(ruleDraft.actionDescriptions.count) action(s), trigger=\(ruleDraft.trigger?.displayString ?? "none")"
            )
        )

        let resolvedCondition = await conditionOperandResolver.resolve(ruleDraft.condition)
        let resolvedRuleDraft = HomeAutomationRuleDraft(
            name: ruleDraft.name,
            domain: ruleDraft.domain,
            operation: ruleDraft.operation,
            intent: ruleDraft.intent,
            trigger: ruleDraft.trigger,
            condition: resolvedCondition,
            actionDescriptions: ruleDraft.actionDescriptions,
            confidence: ruleDraft.confidence
        )

        var resolvedActions: [HomeAutomationResolvedAction] = []
        var retrievedCandidates: [HomeCandidateRecord] = []
        var hydratedCandidates: [HomeCandidateRecord] = []
        var selectedIDs: [String] = []
        var firstDraft: HomeCommandDraft?
        var requiresConfirmation = false

        for (index, actionText) in resolvedRuleDraft.actionDescriptions.enumerated() {
            await eventBus.publish(
                OrchestratorPipelineEvent(
                    runID: runID,
                    stage: "automationActionResolution",
                    agentID: "automationActionResolution",
                    status: .running,
                    detail: actionText
                )
            )
            let actionResult = await resolveAutomationAction(
                text: actionText,
                eventBus: eventBus,
                runID: runID
            )
            retrievedCandidates.append(contentsOf: actionResult.retrievedCandidates)
            hydratedCandidates.append(contentsOf: actionResult.hydratedCandidates)
            selectedIDs.append(contentsOf: actionResult.aggregation.finalCandidateIDs)
            firstDraft = firstDraft ?? actionResult.draft

            if case .needsClarification(let question) = actionResult.resolution {
                return HomeAutomationResolverResult(
                    state: state,
                    retrievedCandidates: retrievedCandidates,
                    aggregation: HomeCandidateAggregationResult(
                        finalCandidateIDs: selectedIDs,
                        needsClarification: true,
                        clarificationQuestion: question,
                        confidence: actionResult.aggregation.confidence
                    ),
                    hydratedCandidates: hydratedCandidates,
                    draft: firstDraft,
                    resolution: .needsClarification("For automation action \(index + 1): \(question)")
                )
            }
            if case .unsupported(let reason) = actionResult.resolution {
                return HomeAutomationResolverResult(
                    state: state,
                    retrievedCandidates: retrievedCandidates,
                    aggregation: HomeCandidateAggregationResult(
                        finalCandidateIDs: selectedIDs,
                        needsClarification: false,
                        confidence: actionResult.aggregation.confidence
                    ),
                    hydratedCandidates: hydratedCandidates,
                    draft: firstDraft,
                    resolution: .unsupported("For automation action \(index + 1): \(reason)")
                )
            }

            guard let draft = actionResult.draft else {
                return HomeAutomationResolverResult(
                    state: state,
                    retrievedCandidates: retrievedCandidates,
                    aggregation: HomeCandidateAggregationResult(
                        finalCandidateIDs: selectedIDs,
                        needsClarification: false,
                        confidence: actionResult.aggregation.confidence
                    ),
                    hydratedCandidates: hydratedCandidates,
                    draft: firstDraft,
                    resolution: .unsupported("For automation action \(index + 1): no command draft was produced.")
                )
            }

            if case .requiresConfirmation = actionResult.resolution {
                requiresConfirmation = true
            }
            if case .readyToExecute(let plan) = actionResult.resolution, plan.requiresConfirmation {
                requiresConfirmation = true
            }

            let selectedDevice = draft.targetDeviceID.flatMap { id in
                actionResult.hydratedCandidates.first { $0.id == id } ??
                    actionResult.retrievedCandidates.first { $0.id == id }
            }
            resolvedActions.append(
                HomeAutomationResolvedAction(
                    originalText: actionText,
                    draft: draft,
                    device: selectedDevice,
                    confidence: draft.confidence
                )
            )
        }

        await eventBus.publish(
            OrchestratorPipelineEvent(
                runID: runID,
                stage: "automationActionResolution",
                agentID: "automationActionResolution",
                status: .completed,
                detail: "\(resolvedActions.count) action(s) resolved"
            )
        )

        var plan = HomeAutomationCreationPlan(
            name: ruleDraft.name,
            ruleDraft: resolvedRuleDraft,
            resolvedActions: resolvedActions,
            smartThingsRuleJSON: nil,
            requiresConfirmation: requiresConfirmation,
            unsupportedCompilationReason: nil
        )

        let compileDetail: String
        do {
            let document = try smartThingsCompiler.compile(plan)
            plan = HomeAutomationCreationPlan(
                name: plan.name,
                ruleDraft: plan.ruleDraft,
                resolvedActions: plan.resolvedActions,
                smartThingsRuleJSON: document.jsonString,
                requiresConfirmation: plan.requiresConfirmation,
                unsupportedCompilationReason: nil
            )
            compileDetail = "compiled"
        } catch {
            plan = HomeAutomationCreationPlan(
                name: plan.name,
                ruleDraft: plan.ruleDraft,
                resolvedActions: plan.resolvedActions,
                smartThingsRuleJSON: nil,
                requiresConfirmation: plan.requiresConfirmation,
                unsupportedCompilationReason: error.localizedDescription
            )
            compileDetail = error.localizedDescription
        }

        await eventBus.publish(
            OrchestratorPipelineEvent(
                runID: runID,
                stage: "smartThingsCompilation",
                agentID: "smartThingsCompilation",
                status: plan.smartThingsRuleJSON == nil ? .skipped : .completed,
                detail: compileDetail
            )
        )

        let aggregation = HomeCandidateAggregationResult(
            finalCandidateIDs: stableUnique(selectedIDs),
            needsClarification: false,
            confidence: resolvedActions.map(\.confidence).min() ?? ruleDraft.confidence
        )
        return HomeAutomationResolverResult(
            state: state,
            retrievedCandidates: stableUnique(retrievedCandidates),
            aggregation: aggregation,
            hydratedCandidates: stableUnique(hydratedCandidates),
            draft: firstDraft,
            resolution: requiresConfirmation ? .automationRequiresConfirmation(plan) : .automationDrafted(plan)
        )
    }

    private func resolveAutomationAction(
        text: String,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> HomeAutomationResolverResult {
        let request = CommandRequest(text: text, executeLowRiskCommands: false)
        let contextStore = ResolutionContextStore(request: request)
        let execution = await executeDirectCommandPipeline(
            text: text,
            contextStore: contextStore,
            eventBus: eventBus,
            runID: runID
        )
        let exit = execution.exit
        let ctx = await contextStore.snapshot()
        let resolution = ctx.resolution ?? Self.resolution(from: exit)
        return HomeAutomationResolverResult(
            state: ctx.resolutionState ?? Self.makeFallbackState(for: text),
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
    }

    private func executeDirectCommandPipeline(
        text: String,
        contextStore: ResolutionContextStore,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> DirectCommandExecutionResult {
        switch runtimeMode {
        case .legacy:
            logger.debug("Generating legacy execution plan.")
            let plan = planner.plan(for: text, context: await contextStore.snapshot())
            logger.debug("Initializing AgentScheduler for runID: \(runID, privacy: .public)")
            let scheduler = AgentScheduler(
                registry: registry,
                contextStore: contextStore,
                eventBus: eventBus,
                policy: policy,
                circuitBreakers: circuitBreakers,
                runID: runID
            )
            let exit = await scheduler.execute(plan)
            return DirectCommandExecutionResult(
                exit: exit,
                fallbackUsed: plan.isFallbackOnly,
                graphRun: nil
            )
        case .graph:
            logger.debug("Generating graph execution plan.")
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
            return DirectCommandExecutionResult(
                exit: result.exit,
                fallbackUsed: plan.isFallbackOnly,
                graphRun: result.metrics
            )
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

    private static func makeOperationState(
        for text: String,
        operation: HomeOperationDetectionResult
    ) -> HomeResolutionState {
        HomeResolutionState(
            rawText: text,
            language: HomeLanguageDetectionResult(
                languageCode: "en",
                isMixedLanguage: false,
                confidence: 0.75,
                unsupportedLanguageLikely: false
            ),
            domain: HomeDomainClassificationResult(
                domain: operation.domain,
                confidence: operation.confidence
            ),
            intent: HomeIntentFamilyResult(
                topFamilies: operation.operation == .automationCreation ? [.createAutomation] : [.unsupported],
                confidence: operation.confidence
            ),
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
                reason: operation.reason,
                confidence: operation.confidence
            )
        )
    }

    private func stableUnique(_ devices: [HomeCandidateRecord]) -> [HomeCandidateRecord] {
        var seen = Set<String>()
        var result: [HomeCandidateRecord] = []
        for device in devices where !seen.contains(device.id) {
            seen.insert(device.id)
            result.append(device)
        }
        return result
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
