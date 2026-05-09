import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import HomeAutomationResolver
import Testing

@Suite
struct OrchestratorInfrastructureTests {
    @Test
    func storeExposesInitialSnapshot() async {
        let request = CommandRequest(text: "turn on the light", executeLowRiskCommands: true)
        let store = ResolutionContextStore(request: request)

        let snapshot = await store.snapshot()

        #expect(snapshot.request.text == "turn on the light")
        #expect(snapshot.request.executeLowRiskCommands)
    }

    @Test
    func eventBusReplaysPublishedEvents() async {
        let bus = AgentEventBus()
        let event = OrchestratorPipelineEvent(
            runID: .init(),
            stage: "contracts",
            status: .completed
        )

        await bus.publish(event)
        let stream = await bus.stream()
        var iterator = stream.makeAsyncIterator()
        let replayed = await iterator.next()

        #expect(replayed?.stage == "contracts")
    }

    @Test
    func plannerChoosesFallbackPlanWhenModelsUnavailable() {
        let policy = OrchestratorPolicyEngine(isModelAvailable: { false })
        let planner = AgentPlanner(policy: policy)
        let context = ResolutionContext(
            request: CommandRequest(text: "turn on the light", executeLowRiskCommands: false)
        )

        let plan = planner.plan(for: "turn on the light", context: context)

        #expect(plan.isFallbackOnly)
        #expect(plan.phases.count == 3)
    }

    @Test
    func defaultRegistryContainsAllPhaseThreeAgents() {
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })

        for id in [
            AgentID.language,
            .domain,
            .intentFamily,
            .deviceType,
            .slotExtraction,
            .riskClassification,
            .capabilityKnowledge,
            .bixbyKnowledge,
            .commandExample,
            .candidateRetrieval,
            .candidateRanking,
            .candidateShard,
            .candidateHydration,
            .instructionComposer,
            .draftGeneration,
            .draftRepair,
            .safetyValidation,
            .parameterValidation,
            .confirmationPolicy,
            .executionPlanning,
            .mockExecution,
            .ruleFallback,
            .bixbyFallback,
            .unsupportedCommand,
            .clarification,
            .resultSummary
        ] {
            #expect(registry.agent(for: id) != nil)
        }
    }

    @Test
    func orchestratorFallbackPathMatchesLegacyReadyResult() async throws {
        let command = "Turn on the bedroom lamp"
        let legacy = LegacyHomeCommandResolver(
            registry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let legacyResult = try await legacy.resolve(command, executeLowRiskCommands: false)
        let orchestratorResult = try await orchestrator.resolve(command, executeLowRiskCommands: false)

        #expect(orchestratorResult.aggregation.finalCandidateIDs == legacyResult.aggregation.finalCandidateIDs)
        #expect(orchestratorResult.draft?.targetDeviceID == legacyResult.draft?.targetDeviceID)

        guard case .readyToExecute(let legacyPlan) = legacyResult.resolution,
              case .readyToExecute(let orchestratorPlan) = orchestratorResult.resolution else {
            Issue.record("Expected both paths to return readyToExecute.")
            return
        }

        #expect(orchestratorPlan.steps.first?.deviceID == legacyPlan.steps.first?.deviceID)
        #expect(orchestratorPlan.steps.first?.capability == legacyPlan.steps.first?.capability)
        #expect(orchestratorPlan.steps.first?.command == legacyPlan.steps.first?.command)
    }

    @Test
    func orchestratorFallbackPathMatchesLegacyConfirmationResult() async throws {
        let command = "Unlock the front door"
        let legacy = LegacyHomeCommandResolver(
            registry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let legacyResult = try await legacy.resolve(command, executeLowRiskCommands: true)
        let orchestratorResult = try await orchestrator.resolve(command, executeLowRiskCommands: true)

        guard case .requiresConfirmation(let legacyDraft) = legacyResult.resolution,
              case .requiresConfirmation(let orchestratorDraft) = orchestratorResult.resolution else {
            Issue.record("Expected both paths to require confirmation.")
            return
        }

        #expect(orchestratorDraft.targetDeviceID == legacyDraft.targetDeviceID)
        #expect(orchestratorDraft.capability == legacyDraft.capability)
        #expect(orchestratorDraft.command == legacyDraft.command)
    }

    @Test
    func orchestratorStreamEmitsEventsAndResult() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        var sawInput = false
        var sawOutcome = false
        var result: HomeAutomationResolverResult?

        for try await update in orchestrator.resolveStream(
            "Turn on the bedroom lamp",
            executeLowRiskCommands: false
        ) {
            switch update {
            case .event(let event):
                if event.stage == "input" {
                    sawInput = true
                }
                if event.stage == "outcome" {
                    sawOutcome = true
                }
            case .result(let output):
                result = output
            }
        }

        #expect(sawInput)
        #expect(sawOutcome)
        #expect(result?.aggregation.finalCandidateIDs == ["bedroom_lamp"])
    }

    @Test
    func orchestratorMetricsIncludePhaseSevenEvaluationFields() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        _ = try await orchestrator.resolve("Turn on the bedroom lamp", executeLowRiskCommands: false)
        let metricsJSON = try #require(await orchestrator.lastMetricsJSON())
        let metrics = try JSONDecoder().decode(OrchestratorMetrics.self, from: Data(metricsJSON.utf8))

        #expect(metricsJSON.contains("stageDurations"))
        #expect(metricsJSON.contains("contextMetrics"))
        #expect(metricsJSON.contains("safetyMetrics"))
        #expect(metricsJSON.contains("candidateMetrics"))
        #expect(metricsJSON.contains("foundationModelUsage"))
        #expect(metrics.candidateMetrics.selectedCandidateIDs == ["bedroom_lamp"])
        #expect(metrics.contextMetrics.hasDraft)
        #expect(metrics.safetyMetrics.readyOrExecuted)
        #expect(metrics.agentStatuses[AgentID.ruleFallback.rawValue] == "success")
        #expect(metrics.foundationModelUsage.modelAvailabilityStatus == "unavailable")
        #expect(metrics.foundationModelUsage.modelCallCount == 0)
        #expect(metrics.foundationModelUsage.skippedModelCallCount > 0)
    }

    @Test
    func conversationMemoryProvidesLastResolvedDeviceHint() async {
        let memory = ConversationMemory(maxTurns: 2)

        await memory.append(
            ConversationTurn(
                userText: "Turn on the bedroom lamp",
                resolvedDeviceID: "bedroom_lamp",
                resolvedCapability: "switch"
            )
        )

        let hint = await memory.lastResolvedDeviceHint()

        #expect(hint?.deviceID == "bedroom_lamp")
        #expect(hint?.capability == "switch")
        #expect(ConversationMemoryReferenceDetector.containsMemoryReference("make it warmer"))
        #expect(!ConversationMemoryReferenceDetector.containsMemoryReference("turn on bedroom lamp"))
    }

    @Test
    func orchestratorUsesMemoryHintForPronounResolution() async throws {
        let memory = ConversationMemory()
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false },
            conversationMemory: memory
        )

        _ = try await orchestrator.resolve("Turn on the bedroom AC", executeLowRiskCommands: false)
        let result = try await orchestrator.resolve("Make it warmer by 2 degrees", executeLowRiskCommands: false)

        #expect(result.draft?.targetDeviceID == "bedroom_ac")
        #expect(result.retrievedCandidates.contains { $0.id == "bedroom_ac" })
    }

    @Test
    func highRiskMemoryDerivedTargetRequiresConfirmation() async throws {
        let memory = ConversationMemory()
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false },
            conversationMemory: memory
        )

        _ = try await orchestrator.resolve("Unlock the front door", executeLowRiskCommands: false)
        let result = try await orchestrator.resolve("Unlock it", executeLowRiskCommands: true)

        guard case .requiresConfirmation(let draft) = result.resolution else {
            Issue.record("Expected memory-derived high-risk action to require confirmation.")
            return
        }

        #expect(draft.targetDeviceID == "front_door_lock")
    }

    @Test
    func circuitBreakerOpensAfterThreshold() async {
        let registry = CircuitBreakerRegistry(threshold: 1, recoveryInterval: 60)
        let breaker = await registry.breaker(for: .language)

        await breaker.recordFailure()

        #expect(await breaker.currentState() == .open)
        #expect(await breaker.shouldAllow() == false)
    }

    @Test
    func schedulerSkipsOpenCircuitForNonMandatoryAgent() async {
        let circuitBreakers = CircuitBreakerRegistry(threshold: 1, recoveryInterval: 60)
        let registry = AgentRegistry(agents: [FailingAnyAgent(id: .language)])
        let contextStore = ResolutionContextStore(
            request: CommandRequest(text: "turn on light", executeLowRiskCommands: false)
        )
        let scheduler = AgentScheduler(
            registry: registry,
            contextStore: contextStore,
            eventBus: AgentEventBus(),
            policy: OrchestratorPolicyEngine(isModelAvailable: { true }),
            circuitBreakers: circuitBreakers,
            runID: UUID()
        )

        _ = await scheduler.execute(AgentExecutionPlan(phases: [.sequential(AgentTask(.language))]))
        let exit = await scheduler.execute(AgentExecutionPlan(phases: [.sequential(AgentTask(.language))]))
        let trace = await contextStore.snapshot().trace

        #expect(exit == nil)
        #expect(trace.last?.result == .skipped)
        #expect(await circuitBreakers.allStatuses()[.language] == .open)
    }

    @Test
    func schedulerFailsClosedWhenMandatoryCircuitIsOpen() async {
        let circuitBreakers = CircuitBreakerRegistry(threshold: 1, recoveryInterval: 60)
        let breaker = await circuitBreakers.breaker(for: .confirmationPolicy)
        await breaker.recordFailure()

        let contextStore = ResolutionContextStore(
            request: CommandRequest(text: "unlock it", executeLowRiskCommands: true)
        )
        let draft = HomeCommandDraft(
            intent: .unlock,
            targetDeviceID: "front_door_lock",
            capability: "lock",
            command: "unlock",
            needsClarification: false,
            requiresConfirmation: false,
            confidence: 1
        )
        await contextStore.setDraft(draft)

        let scheduler = AgentScheduler(
            registry: AgentRegistry(agents: [SuccessfulAnyAgent(id: .confirmationPolicy)]),
            contextStore: contextStore,
            eventBus: AgentEventBus(),
            policy: OrchestratorPolicyEngine(isModelAvailable: { true }),
            circuitBreakers: circuitBreakers,
            runID: UUID()
        )

        _ = await scheduler.execute(AgentExecutionPlan(phases: [.sequential(AgentTask(.confirmationPolicy))]))
        let context = await contextStore.snapshot()

        guard case .requiresConfirmation(let blockedDraft) = context.resolution else {
            Issue.record("Expected fail-closed confirmation resolution.")
            return
        }

        #expect(blockedDraft.targetDeviceID == "front_door_lock")
    }
}

private struct FailingAnyAgent: AnyHomeAgent {
    let id: AgentID
    let capabilities: Set<AgentCapability> = []
    let timeoutNanoseconds: UInt64 = 1_000_000_000

    func run(context: ResolutionContext) async -> AgentRunResult {
        .terminalFailure(
            AgentFailure(agentID: id, reason: "forced failure", isRetryable: false)
        )
    }
}

private struct SuccessfulAnyAgent: AnyHomeAgent {
    let id: AgentID
    let capabilities: Set<AgentCapability> = []
    let timeoutNanoseconds: UInt64 = 1_000_000_000

    func run(context: ResolutionContext) async -> AgentRunResult {
        .success(ResolutionContextPatch(agentID: id))
    }
}
