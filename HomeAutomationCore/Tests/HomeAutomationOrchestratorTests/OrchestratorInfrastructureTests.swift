import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
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
    func plannerIncludesRetrievalJudgeAfterKnowledgePhaseWhenModelsAvailable() {
        let policy = OrchestratorPolicyEngine(isModelAvailable: { true })
        let planner = AgentPlanner(policy: policy)
        let context = ResolutionContext(
            request: CommandRequest(text: "turn on the light", executeLowRiskCommands: false)
        )

        let plan = planner.plan(for: "turn on the light", context: context)

        #expect(!plan.isFallbackOnly)
        #expect(plan.phases.contains { phase in
            if case .sequential(let task) = phase {
                return task.agentID == .retrievalJudge
            }
            return false
        })
    }

    @Test
    func graphPlannerExposesAutomationCreationGraph() {
        let policy = OrchestratorPolicyEngine(isModelAvailable: { false })
        let planner = GraphPlanner(policy: policy)
        let context = ResolutionContext(
            request: CommandRequest(text: "Turn on AC everyday at 7 AM", executeLowRiskCommands: false)
        )

        let plan = planner.plan(for: context.request.text, context: context, operation: .automationCreation)
        let graph = plan.graph

        #expect(graph.id == "automation-creation-graph")
        #expect(graph.goal == .automationCreation)
        #expect(GraphValidator().validate(graph).isEmpty)
        #expect(graph.nodes.map(\.id) == [
            AgentID.operationDetection.rawValue,
            AgentID.automationDraft.rawValue,
            AgentID.automationConditionOperandResolution.rawValue,
            AgentID.automationActionResolution.rawValue,
            AgentID.automationValidation.rawValue,
            AgentID.smartThingsCompilation.rawValue,
            AgentID.smartThingsRuleCreation.rawValue,
            AgentID.automationResultAssembly.rawValue
        ])
        #expect(graph.edges.contains(GraphEdge(from: AgentID.automationDraft.rawValue, to: AgentID.automationConditionOperandResolution.rawValue)))
        #expect(graph.edges.contains(GraphEdge(from: AgentID.automationDraft.rawValue, to: AgentID.automationActionResolution.rawValue)))
        #expect(graph.edges.contains(GraphEdge(from: AgentID.automationConditionOperandResolution.rawValue, to: AgentID.automationValidation.rawValue)))
        #expect(graph.edges.contains(GraphEdge(from: AgentID.automationActionResolution.rawValue, to: AgentID.automationValidation.rawValue)))
        #expect(graph.edges.contains(GraphEdge(from: AgentID.smartThingsCompilation.rawValue, to: AgentID.smartThingsRuleCreation.rawValue)))
        #expect(graph.edges.contains(GraphEdge(from: AgentID.smartThingsRuleCreation.rawValue, to: AgentID.automationResultAssembly.rawValue)))
        #expect(!graph.edges.contains(GraphEdge(from: AgentID.automationConditionOperandResolution.rawValue, to: AgentID.automationActionResolution.rawValue)))
    }

    @Test
    func runtimeConfigurationDefaultsToGraphAndCanRollbackToLegacy() {
        let defaultConfiguration = OrchestratorRuntimeConfiguration.resolving(environment: [:])
        let rollbackConfiguration = OrchestratorRuntimeConfiguration.resolving(
            environment: [
                OrchestratorRuntimeConfiguration.environmentVariableName: OrchestratorRuntimeMode.legacy.rawValue
            ]
        )
        let invalidConfiguration = OrchestratorRuntimeConfiguration.resolving(
            environment: [
                OrchestratorRuntimeConfiguration.environmentVariableName: "not-a-runtime"
            ]
        )

        #expect(defaultConfiguration.runtimeMode == .graph)
        #expect(rollbackConfiguration.runtimeMode == .legacy)
        #expect(invalidConfiguration.runtimeMode == .graph)
    }

    @Test
    func orchestratorDefaultRuntimeUsesGraph() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        _ = try await orchestrator.resolve("Turn on the bedroom lamp", executeLowRiskCommands: false)
        let metrics = try #require(await orchestrator.lastMetrics())

        #expect(metrics.graphRun?.graphID == "direct-command-fallback-graph")
    }

    @Test
    func legacyRuntimeCanBeExplicitlySelectedAsRollback() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false },
            runtimeMode: .legacy
        )

        let result = try await orchestrator.resolve("Turn on the bedroom lamp", executeLowRiskCommands: false)
        let metrics = try #require(await orchestrator.lastMetrics())

        guard case .readyToExecute = result.resolution else {
            Issue.record("Expected legacy rollback runtime to keep direct commands working.")
            return
        }
        #expect(metrics.graphRun == nil)
        #expect(metrics.agentStatuses[AgentID.ruleFallback.rawValue] == "success")
    }

    @Test
    func defaultRegistryContainsAllPhaseThreeAgents() {
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })

        for id in [
            AgentID.operationDetection,
            .automationDraft,
            .automationConditionOperandResolution,
            .automationActionResolution,
            .automationValidation,
            .smartThingsCompilation,
            .smartThingsRuleCreation,
            .automationResultAssembly,
            AgentID.language,
            .domain,
            .intentFamily,
            .deviceType,
            .slotExtraction,
            .riskClassification,
            .capabilityKnowledge,
            .bixbyKnowledge,
            .commandExample,
            .retrievalJudge,
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
    func defaultRegistrySatisfiesAutomationCreationGraph() {
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })
        let graph = GraphPlanner.automationCreationGraph()

        #expect(GraphValidator().validate(graph, registry: registry).isEmpty)
        for node in graph.nodes {
            guard case .byID(let id) = node.requirement else {
                Issue.record("Automation graph should use concrete agent IDs.")
                continue
            }
            let agent = registry.agent(for: id)
            let manifest = registry.manifest(for: id)
            #expect(agent != nil)
            #expect(manifest?.supportedOperations.contains(.automationCreation) == true)
        }
        #expect(registry.manifest(for: .automationActionResolution)?.produces.contains(ResolutionContextPatchKey.automationResolvedActions) == true)
        #expect(registry.manifest(for: .smartThingsCompilation)?.produces.contains(ResolutionContextPatchKey.automationPlan) == true)
        #expect(registry.manifest(for: .smartThingsRuleCreation)?.produces.contains(ResolutionContextPatchKey.automationPlan) == true)
        #expect(registry.manifest(for: .automationResultAssembly)?.produces.contains(ResolutionContextPatchKey.resolverResult) == true)
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
    func orchestratorStreamDoesNotDuplicateEventIDs() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )
        var eventIDs: [String] = []

        for try await update in orchestrator.resolveStream(
            "Turn on the bedroom lamp",
            executeLowRiskCommands: false
        ) {
            if case .event(let event) = update {
                eventIDs.append(event.id)
            }
        }

        #expect(!eventIDs.isEmpty)
        #expect(Set(eventIDs).count == eventIDs.count)
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
    func automationMetricsIncludePhaseNineFields() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        _ = try await orchestrator.resolve("Turn on bedroom AC everyday at 7 AM", executeLowRiskCommands: true)
        let metricsJSON = try #require(await orchestrator.lastMetricsJSON())
        let metrics = try JSONDecoder().decode(OrchestratorMetrics.self, from: Data(metricsJSON.utf8))

        #expect(metrics.automationMetrics.operation == HomeAutomationOperationKind.automationCreation.rawValue)
        #expect(metrics.automationMetrics.runtimeMode == OrchestratorRuntimeMode.graph.rawValue)
        #expect(metrics.automationMetrics.graphID == "automation-creation-graph")
        #expect(metrics.automationMetrics.automationActionCount == 1)
        #expect(metrics.automationMetrics.automationCompilerTarget == "SmartThingsRulesV1")
        #expect(metrics.automationMetrics.automationCompilationSupported)
        #expect(metrics.automationMetrics.graphNodeStatuses[AgentID.smartThingsCompilation.rawValue] == GraphNodeRunStatus.completed.rawValue)
        #expect(metrics.graphRun?.graphID == "automation-creation-graph")
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
