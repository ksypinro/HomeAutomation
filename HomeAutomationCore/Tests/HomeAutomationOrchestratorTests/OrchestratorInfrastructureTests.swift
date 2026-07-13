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
    func contextualAgentExposesStableSessionAndIncrementingRunID() async {
        let wrapper = ContextualHomeAgent(
            agent: TraceIdentityTestAgent(),
            makeInput: { _ in "input" },
            makePatch: { _, _ in ResolutionContextPatch(agentID: .semanticNLU) }
        )

        let sessionID = wrapper.agentSessionID
        let firstRun = await wrapper.nextAgentRunID()
        let secondRun = await wrapper.nextAgentRunID()

        #expect(!sessionID.isEmpty)
        #expect(wrapper.agentSessionID == sessionID)
        #expect(firstRun == 1)
        #expect(secondRun == 2)
    }

    @Test
    func graphPlannerChoosesFallbackGraphWhenModelsUnavailable() {
        let policy = OrchestratorPolicyEngine(isModelAvailable: { false })
        let planner = GraphPlanner(policy: policy)
        let context = ResolutionContext(
            request: CommandRequest(text: "turn on the light", executeLowRiskCommands: false)
        )

        let plan = planner.plan(for: "turn on the light", context: context)

        #expect(plan.isFallbackOnly)
        #expect(plan.graph.id == "direct-command-fallback-graph")
        #expect(plan.graph.nodes.map(\.id) == [
            AgentID.ruleFallback.rawValue,
            AgentID.bixbyFallback.rawValue,
            AgentID.unsupportedCommand.rawValue
        ])
    }

    @Test
    func graphPlannerIncludesRetrievalJudgeAndMockExecutionWhenModelsAvailable() {
        let policy = OrchestratorPolicyEngine(isModelAvailable: { true })
        let planner = GraphPlanner(policy: policy)
        let context = ResolutionContext(
            request: CommandRequest(text: "turn on the light", executeLowRiskCommands: false)
        )

        let plan = planner.plan(for: "turn on the light", context: context)

        #expect(!plan.isFallbackOnly)
        #expect(plan.graph.nodes.contains { $0.id == AgentID.retrievalJudge.rawValue })
        #expect(plan.graph.nodes.contains { $0.id == AgentID.capabilityResolution.rawValue })
        #expect(plan.graph.nodes.contains { node in
            node.id == AgentID.mockExecution.rawValue &&
                node.executionPolicy == .safetyGate &&
                node.guardCondition == .canExecuteCommand
        })
        #expect(plan.graph.edges.contains(GraphEdge(from: AgentID.candidateHydration.rawValue, to: AgentID.capabilityResolution.rawValue)))
        #expect(plan.graph.edges.contains(GraphEdge(from: AgentID.capabilityResolution.rawValue, to: AgentID.instructionComposer.rawValue)))
        #expect(plan.graph.edges.contains(GraphEdge(from: AgentID.executionPlanning.rawValue, to: AgentID.mockExecution.rawValue)))
    }

    @Test
    func graphPlannerExposesRootRoutingGraph() {
        let policy = OrchestratorPolicyEngine(isModelAvailable: { true })
        let planner = GraphPlanner(policy: policy)
        let context = ResolutionContext(
            request: CommandRequest(text: "Turn on AC everyday at 7 AM", executeLowRiskCommands: false)
        )

        let graph = planner.planRootRouting(for: context.request.text, context: context).graph

        #expect(graph.id == "root-command-graph")
        #expect(graph.goal == .rootRouting)
        #expect(GraphValidator().validate(graph).isEmpty)
        #expect(graph.nodes.map(\.id) == [AgentID.operationDetection.rawValue])
        #expect(graph.entryNodeIDs == [AgentID.operationDetection.rawValue])
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
            AgentID.automationComponentSegmentation.rawValue,
            AgentID.automationComponentFanOut.rawValue,
            AgentID.automationDraftAssembly.rawValue,
            AgentID.automationValidation.rawValue,
            AgentID.smartThingsCompilation.rawValue,
            AgentID.smartThingsRuleCreation.rawValue,
            AgentID.automationResultAssembly.rawValue
        ])
        #expect(graph.entryNodeIDs == [AgentID.automationComponentSegmentation.rawValue])
        #expect(graph.edges.contains(GraphEdge(from: AgentID.automationComponentSegmentation.rawValue, to: AgentID.automationComponentFanOut.rawValue)))
        #expect(graph.edges.contains(GraphEdge(from: AgentID.automationComponentFanOut.rawValue, to: AgentID.automationDraftAssembly.rawValue)))
        #expect(graph.edges.contains(GraphEdge(from: AgentID.automationDraftAssembly.rawValue, to: AgentID.automationValidation.rawValue)))
        #expect(graph.edges.contains(GraphEdge(from: AgentID.smartThingsCompilation.rawValue, to: AgentID.smartThingsRuleCreation.rawValue)))
        #expect(graph.edges.contains(GraphEdge(from: AgentID.smartThingsRuleCreation.rawValue, to: AgentID.automationResultAssembly.rawValue)))
        #expect(!graph.edges.contains(GraphEdge(from: AgentID.automationDraft.rawValue, to: AgentID.automationActionResolution.rawValue)))
    }

    @Test
    func orchestratorDefaultRuntimeUsesGraph() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        _ = try await orchestrator.resolve("Turn on the bedroom lamp", executeLowRiskCommands: false)
        let metrics = try #require(await orchestrator.lastMetrics())

        #expect(metrics.graphRun?.graphID == "direct-command-finalization-graph")
    }

    @Test
    func orchestratorMetricsAlwaysUseGraphRuntimeLabel() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        _ = try await orchestrator.resolve("Turn on bedroom AC everyday at 7 AM", executeLowRiskCommands: true)
        let metrics = try #require(await orchestrator.lastMetrics())

        #expect(metrics.automationMetrics.runtimeMode == "graph")
        #expect(metrics.graphRun?.graphID == "automation-creation-graph")
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
            .semanticNLU,
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
            .capabilityResolution,
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
    func coordinatorBuildsRuntimeDependenciesFromOneCompositionRoot() {
        let coordinator = HomeAutomationCoordinator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let dependencies = coordinator.makeRuntimeDependencies()
        let context = ResolutionContext(
            request: CommandRequest(text: "turn on bedroom AC", executeLowRiskCommands: false)
        )
        let graph = dependencies.graphPlanner.plan(for: context.request.text, context: context).graph

        #expect(dependencies.policy.modelAvailabilityStatus() == "unavailable")
        #expect(graph.id == "direct-command-fallback-graph")
        #expect(dependencies.agentRegistry.agent(for: .operationDetection) != nil)
        #expect(dependencies.agentRegistry.agent(for: .automationComponentFanOut) != nil)
    }

    @Test
    func coordinatorAcceptsProtocolBackedAgentRegistryFactory() {
        let coordinator = HomeAutomationCoordinator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false },
            agentRegistryFactory: EmptyAgentRegistryFactory()
        )

        let dependencies = coordinator.makeRuntimeDependencies()

        #expect(dependencies.agentRegistry.agent(for: .operationDetection) == nil)
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
        #expect(registry.manifest(for: .automationActionResolution)?.produces.contains(ResolutionContextPatchKey.automationResolvedActions.rawValue) == true)
        #expect(registry.manifest(for: .smartThingsCompilation)?.produces.contains(ResolutionContextPatchKey.automationPlan.rawValue) == true)
        #expect(registry.manifest(for: .smartThingsRuleCreation)?.produces.contains(ResolutionContextPatchKey.automationPlan.rawValue) == true)
        #expect(registry.manifest(for: .automationResultAssembly)?.produces.contains(ResolutionContextPatchKey.resolverResult.rawValue) == true)
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
    func automationGraphMetricsIncludeFinalizationReceipt() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        _ = try await orchestrator.resolve("Turn on bedroom AC everyday at 7 AM", executeLowRiskCommands: true)
        let metrics = try #require(await orchestrator.lastMetrics())
        let receipt = try #require(metrics.safetyMetrics.finalizationReceipt)

        #expect(receipt.status == .completed)
        #expect(receipt.graphID == "automation-creation-graph")
        #expect(receipt.requiredGateIDs == [
            AgentID.automationValidation.rawValue,
            AgentID.smartThingsCompilation.rawValue,
            AgentID.smartThingsRuleCreation.rawValue,
            AgentID.automationResultAssembly.rawValue
        ])
        #expect(receipt.gateRecords.contains { $0.gateID == AgentID.automationValidation.rawValue && $0.status == GraphNodeRunStatus.completed.rawValue })
        #expect(receipt.gateRecords.contains { $0.gateID == AgentID.smartThingsCompilation.rawValue && $0.status == GraphNodeRunStatus.completed.rawValue })
        #expect(receipt.gateRecords.contains { $0.gateID == AgentID.smartThingsRuleCreation.rawValue })
        #expect(receipt.missingGateIDs.isEmpty)
        #expect(receipt.failedGateID == nil)
    }

    @Test
    func directCommandGraphMetricsIncludeFinalizationReceipt() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on the bedroom lamp",
            executeLowRiskCommands: false
        )
        let metrics = try #require(await orchestrator.lastMetrics())
        let receipt = try #require(metrics.safetyMetrics.finalizationReceipt)

        guard case .readyToExecute = result.resolution else {
            Issue.record("Expected ready-to-execute direct command, got \(result.resolution)")
            return
        }

        #expect(receipt.status == .completed)
        #expect(receipt.graphID == "direct-command-finalization-graph")
        #expect(receipt.requiredGateIDs == [
            AgentID.safetyValidation.rawValue,
            AgentID.parameterValidation.rawValue,
            AgentID.confirmationPolicy.rawValue,
            AgentID.executionPlanning.rawValue,
            AgentID.mockExecution.rawValue
        ])
        #expect(receipt.gateRecords.contains {
            $0.gateID == AgentID.mockExecution.rawValue &&
            $0.status == GraphNodeRunStatus.skipped.rawValue
        })
        #expect(receipt.missingGateIDs.isEmpty)
        #expect(receipt.failedGateID == nil)
    }

    @Test
    func verifierLoopEscalatedAutomationRunsResolutionFinalizerWhenGraphFallbackUnavailable() async throws {
        let coordinator = HomeAutomationCoordinator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )
        let orchestrator = HomeCommandOrchestrator(
            dependencies: coordinator.makeRuntimeDependencies(orchestrationMode: .verifierLoop)
        )

        _ = try await orchestrator.resolve("When the entry contact sensor opens, turn on the porch light", executeLowRiskCommands: true)
        let metrics = try #require(await orchestrator.lastMetrics())
        let receipt = try #require(metrics.safetyMetrics.finalizationReceipt)

        #expect(metrics.loop != nil)
        #expect(metrics.loop?.escalationReason == EscalationReason.verifierUnavailable.rawValue)
        #expect(receipt.status == .completed)
        #expect(receipt.graphID == "automation-finalization-graph")
    }

    @Test
    func verifierLoopAcceptedAutomationRunsResolutionFinalizer() async throws {
        let orchestrator = makeAcceptedVerifierLoopOrchestrator()

        let result = try await orchestrator.resolve(
            "When the entry contact sensor opens, turn on the porch light",
            executeLowRiskCommands: true
        )
        let metrics = try #require(await orchestrator.lastMetrics())
        let receipt = try #require(metrics.safetyMetrics.finalizationReceipt)

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automation draft, got \(result.resolution)")
            return
        }

        #expect(plan.smartThingsRuleJSON != nil)
        #expect(metrics.loop?.acceptedOnIteration == 1)
        #expect(metrics.automationMetrics.graphID == "automation-finalization-graph")
        #expect(receipt.status == .completed)
        #expect(receipt.graphID == "automation-finalization-graph")
        #expect(receipt.requiredGateIDs.contains(AgentID.automationResultAssembly.rawValue))
    }

    @Test
    func verifierLoopAcceptedDirectCommandRunsResolutionFinalizer() async throws {
        let orchestrator = makeAcceptedVerifierLoopOrchestrator()

        let result = try await orchestrator.resolve(
            "Turn on the bedroom lamp",
            executeLowRiskCommands: false
        )
        let metrics = try #require(await orchestrator.lastMetrics())
        let receipt = try #require(metrics.safetyMetrics.finalizationReceipt)

        guard case .readyToExecute = result.resolution else {
            Issue.record("Expected ready-to-execute result, got \(result.resolution)")
            return
        }

        #expect(metrics.loop?.acceptedOnIteration == 1)
        #expect(receipt.status == .completed)
        #expect(receipt.graphID == "direct-command-finalization-graph")
        #expect(receipt.gateRecords.contains {
            $0.gateID == AgentID.mockExecution.rawValue &&
            $0.status == GraphNodeRunStatus.skipped.rawValue
        })
    }

    @Test
    func verifierLoopAcceptedAutomationCreateRunsBackendOnlyAfterFinalizerGates() async throws {
        let creator = RecordingSmartThingsRuleCreator()
        let orchestrator = makeAcceptedVerifierLoopOrchestrator(smartThingsRuleCreator: creator)

        let result = try await orchestrator.resolve(
            "Turn on bedroom AC every day at 7 AM",
            executeLowRiskCommands: true,
            automationCreationOptions: .create(locationID: "location-1")
        )
        let metrics = try #require(await orchestrator.lastMetrics())
        let receipt = try #require(metrics.safetyMetrics.finalizationReceipt)

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected created automation draft, got \(result.resolution)")
            return
        }

        #expect(await creator.callCount == 1)
        #expect(plan.backendResponse?.status == .created)
        #expect(receipt.status == .completed)
        #expect(receipt.gateRecords.first { $0.gateID == AgentID.automationValidation.rawValue }?.status == GraphNodeRunStatus.completed.rawValue)
        #expect(receipt.gateRecords.first { $0.gateID == AgentID.smartThingsCompilation.rawValue }?.status == GraphNodeRunStatus.completed.rawValue)
        #expect(receipt.gateRecords.first { $0.gateID == AgentID.smartThingsRuleCreation.rawValue }?.status == GraphNodeRunStatus.completed.rawValue)
        #expect(receipt.gateRecords.first { $0.gateID == AgentID.automationResultAssembly.rawValue }?.status == GraphNodeRunStatus.completed.rawValue)
    }

    @Test
    func verifierLoopAcceptedHighRiskAutomationDoesNotCallBackendWithoutConfirmation() async throws {
        let creator = RecordingSmartThingsRuleCreator()
        let orchestrator = makeAcceptedVerifierLoopOrchestrator(smartThingsRuleCreator: creator)

        let result = try await orchestrator.resolve(
            "Unlock front door every day at 7 AM",
            executeLowRiskCommands: true,
            automationCreationOptions: .create(locationID: "location-1")
        )
        let metrics = try #require(await orchestrator.lastMetrics())
        let receipt = try #require(metrics.safetyMetrics.finalizationReceipt)

        guard case .automationRequiresConfirmation(let plan) = result.resolution else {
            Issue.record("Expected high-risk automation confirmation, got \(result.resolution)")
            return
        }

        #expect(await creator.callCount == 0)
        #expect(plan.backendResponse?.status == .confirmationRequired)
        #expect(receipt.status == .completed)
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
        #expect(metrics.automationMetrics.runtimeMode == "graph")
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
        let breaker = await registry.breaker(for: .semanticNLU)

        await breaker.recordFailure()

        #expect(await breaker.currentState() == .open)
        #expect(await breaker.shouldAllow() == false)
    }

    @Test
    func graphSchedulerSkipsOpenCircuitForNonMandatoryAgent() async {
        let circuitBreakers = CircuitBreakerRegistry(threshold: 1, recoveryInterval: 60)
        let registry = AgentRegistry(agents: [
            FailingAnyAgent(id: .semanticNLU),
            SuccessfulAnyAgent(id: .unsupportedCommand)
        ])
        let contextStore = ResolutionContextStore(
            request: CommandRequest(text: "turn on light", executeLowRiskCommands: false)
        )
        let graph = OrchestrationGraph(
            id: "non-mandatory-open-circuit",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(id: AgentID.semanticNLU.rawValue, requirement: .byID(.semanticNLU)),
                GraphNode(id: AgentID.unsupportedCommand.rawValue, requirement: .byID(.unsupportedCommand))
            ],
            edges: [
                GraphEdge(from: AgentID.semanticNLU.rawValue, to: AgentID.unsupportedCommand.rawValue)
            ],
            entryNodeIDs: [AgentID.semanticNLU.rawValue]
        )
        let scheduler = GraphScheduler()
        let policy = OrchestratorPolicyEngine(isModelAvailable: { true })
        let runID = UUID()

        _ = await scheduler.execute(
            graph,
            registry: registry,
            contextStore: contextStore,
            eventBus: AgentEventBus(),
            policy: policy,
            circuitBreakers: circuitBreakers,
            runID: UUID()
        )
        let result = await scheduler.execute(
            graph,
            registry: registry,
            contextStore: contextStore,
            eventBus: AgentEventBus(),
            policy: policy,
            circuitBreakers: circuitBreakers,
            runID: runID
        )
        let trace = await contextStore.snapshot().trace

        #expect(result.exit == nil)
        #expect(trace.contains { $0.agentID == .semanticNLU && $0.result == .skipped })
        #expect(await circuitBreakers.allStatuses()[.semanticNLU] == .open)
        #expect(result.metrics.nodeStatuses[AgentID.semanticNLU.rawValue] == .skipped)
    }

    @Test
    func graphSchedulerFailsClosedWhenMandatoryCircuitIsOpen() async {
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
        await contextStore.setHydratedCandidates([
            HomeCandidateRecord(
                id: "front_door_lock",
                displayName: "Front Door Lock",
                deviceType: "lock",
                room: "entry",
                capabilities: ["lock"],
                supportedCommands: ["lock": ["lock", "unlock"]],
                riskLevel: .high
            )
        ])

        let graph = OrchestrationGraph(
            id: "mandatory-open-circuit",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(
                    id: AgentID.confirmationPolicy.rawValue,
                    requirement: .byID(.confirmationPolicy),
                    executionPolicy: .safetyGate
                )
            ],
            edges: [],
            entryNodeIDs: [AgentID.confirmationPolicy.rawValue]
        )

        _ = await GraphScheduler().execute(
            graph,
            registry: AgentRegistry(agents: [SuccessfulAnyAgent(id: .confirmationPolicy)]),
            contextStore: contextStore,
            eventBus: AgentEventBus(),
            policy: OrchestratorPolicyEngine(isModelAvailable: { true }),
            circuitBreakers: circuitBreakers,
            runID: UUID()
        )
        let context = await contextStore.snapshot()

        guard case .requiresConfirmation(let blockedDraft) = context.resolution else {
            Issue.record("Expected fail-closed confirmation resolution.")
            return
        }

        #expect(blockedDraft.targetDeviceID == "front_door_lock")
    }

    private func makeAcceptedVerifierLoopOrchestrator(
        smartThingsRuleCreator: (any SmartThingsRuleCreating)? = nil
    ) -> HomeCommandOrchestrator {
        let registry = MockHomeDeviceRegistry()
        let coordinator = HomeAutomationCoordinator(
            deviceRegistry: registry,
            foundationModelAvailability: { false },
            smartThingsRuleCreator: smartThingsRuleCreator
        )
        let loop = VerifierLoopOrchestrator(
            pipeline: DeterministicDraftPipeline(registry: registry),
            verifier: DraftVerifierWorkerSession(
                verify: { _, _ in
                    DraftVerdict(accepted: true, disputes: [], needsClarification: false)
                },
                foundationModelAvailability: { false }
            ),
            promptBuilder: VerifierPromptBuilder(),
            planner: RepairPlanner(),
            specialists: RepairSpecialistRegistry(execute: { _, _ in nil }),
            policy: VerifierLoopPolicy()
        )

        return HomeCommandOrchestrator(
            dependencies: HomeAutomationRuntimeDependencies(
                agentRegistry: coordinator.makeAgentRegistry(),
                graphPlanner: coordinator.graphPlanner,
                policy: coordinator.policy,
                scheduler: coordinator.scheduler,
                metricsCollector: OrchestratorMetricsCollector(),
                conversationMemory: ConversationMemory(),
                circuitBreakers: coordinator.circuitBreakers,
                deviceRegistry: registry,
                smartThingsRuleCreator: smartThingsRuleCreator,
                orchestrationMode: .verifierLoop,
                loopOrchestrator: loop
            )
        )
    }
}

private struct EmptyAgentRegistryFactory: HomeAutomationAgentRegistryFactory {
    func makeAgentRegistry(
        dependencies: HomeAutomationAgentFactoryDependencies
    ) -> AgentRegistry {
        _ = dependencies
        return AgentRegistry(agents: [])
    }
}

private struct TraceIdentityTestAgent: HomeAgent {
    typealias Input = String
    typealias Output = String

    let id = AgentID.semanticNLU
    let capabilities: Set<AgentCapability> = []
    let timeoutNanoseconds: UInt64 = 1_000_000_000

    func run(_ input: String, context: ResolutionContext) async throws -> String {
        input
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

private actor RecordingSmartThingsRuleCreator: SmartThingsRuleCreating {
    private var requests: [SmartThingsRuleCreationRequest] = []

    var callCount: Int {
        requests.count
    }

    func createRule(_ request: SmartThingsRuleCreationRequest) async throws -> SmartThingsRuleCreationReceipt {
        requests.append(request)
        return SmartThingsRuleCreationReceipt(
            status: .created,
            ruleID: "rule-\(requests.count)",
            locationID: request.locationID,
            requestID: "request-\(requests.count)",
            message: "Created by infrastructure test backend.",
            createdAt: Date(),
            rawResponse: #"{"ruleId":"rule-\#(requests.count)"}"#
        )
    }
}
