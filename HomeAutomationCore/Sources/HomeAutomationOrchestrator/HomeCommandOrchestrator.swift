import Foundation
import FoundationModels
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationRAG

public enum OrchestratorUpdate: Sendable {
    case event(OrchestratorPipelineEvent)
    case result(HomeAutomationResolverResult)
}

public final class HomeCommandOrchestrator: HomeCommandResolving, Sendable {
    private let registry: AgentRegistry
    private let planner: AgentPlanner
    private let policy: OrchestratorPolicyEngine
    private let metricsCollector: OrchestratorMetricsCollector
    private let conversationMemory: ConversationMemory
    private let circuitBreakers: CircuitBreakerRegistry

    public init(
        registry: AgentRegistry,
        planner: AgentPlanner,
        policy: OrchestratorPolicyEngine,
        metricsCollector: OrchestratorMetricsCollector = OrchestratorMetricsCollector(),
        conversationMemory: ConversationMemory = ConversationMemory(),
        circuitBreakers: CircuitBreakerRegistry = CircuitBreakerRegistry()
    ) {
        self.registry = registry
        self.planner = planner
        self.policy = policy
        self.metricsCollector = metricsCollector
        self.conversationMemory = conversationMemory
        self.circuitBreakers = circuitBreakers
    }

    public convenience init(
        deviceRegistry: MockHomeDeviceRegistry = MockHomeDeviceRegistry(),
        contextRetriever: ContextRetriever? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        metricsCollector: OrchestratorMetricsCollector = OrchestratorMetricsCollector(),
        conversationMemory: ConversationMemory = ConversationMemory(),
        circuitBreakers: CircuitBreakerRegistry = CircuitBreakerRegistry()
    ) {
        let policy = OrchestratorPolicyEngine(isModelAvailable: foundationModelAvailability)
        self.init(
            registry: DefaultAgentRegistryFactory.make(
                registry: deviceRegistry,
                contextRetriever: contextRetriever,
                foundationModelAvailability: foundationModelAvailability
            ),
            planner: AgentPlanner(policy: policy),
            policy: policy,
            metricsCollector: metricsCollector,
            conversationMemory: conversationMemory,
            circuitBreakers: circuitBreakers
        )
    }

    public static func makeRAGEnabled(
        deviceRegistry: MockHomeDeviceRegistry = MockHomeDeviceRegistry(),
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        metricsCollector: OrchestratorMetricsCollector = OrchestratorMetricsCollector()
    ) async -> HomeCommandOrchestrator {
        let conversationMemory = ConversationMemory()
        let circuitBreakers = CircuitBreakerRegistry()
        let indexer = KnowledgeIndexer()
        await indexer.indexCanonicalKnowledge(deviceRegistry: deviceRegistry)
        let retriever = await indexer.makeRetriever()
        return HomeCommandOrchestrator(
            deviceRegistry: deviceRegistry,
            contextRetriever: retriever,
            foundationModelAvailability: foundationModelAvailability,
            metricsCollector: metricsCollector,
            conversationMemory: conversationMemory,
            circuitBreakers: circuitBreakers
        )
    }

    public func resolve(_ text: String, executeLowRiskCommands: Bool = true) async throws -> HomeAutomationResolverResult {
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

    public func resolveStream(
        _ text: String,
        executeLowRiskCommands: Bool = true
    ) -> AsyncThrowingStream<OrchestratorUpdate, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedText.isEmpty else {
                    continuation.finish(throwing: FoundationLabCoreError.invalidRequest("Missing home command"))
                    return
                }

                let request = CommandRequest(text: trimmedText, executeLowRiskCommands: executeLowRiskCommands)
                let contextStore = ResolutionContextStore(request: request)
                if ConversationMemoryReferenceDetector.containsMemoryReference(trimmedText),
                   let hint = await conversationMemory.lastResolvedDeviceHint() {
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
                let plan = planner.plan(for: trimmedText, context: await contextStore.snapshot())
                let scheduler = AgentScheduler(
                    registry: registry,
                    contextStore: contextStore,
                    eventBus: eventBus,
                    policy: policy,
                    circuitBreakers: circuitBreakers,
                    runID: runID
                )

                let exit = await scheduler.execute(plan)

                if exit == nil, policy.canExecute(context: await contextStore.snapshot()) {
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
                metrics.fallbackUsed = plan.isFallbackOnly
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
}
