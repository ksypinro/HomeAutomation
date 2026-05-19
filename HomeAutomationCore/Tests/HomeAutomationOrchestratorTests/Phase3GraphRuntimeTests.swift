import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite
struct Phase3GraphRuntimeTests {
    @Test
    func graphPlannerBuildsFallbackGraphWhenModelsUnavailable() {
        let planner = GraphPlanner(policy: OrchestratorPolicyEngine(isModelAvailable: { false }))
        let context = ResolutionContext(
            request: CommandRequest(text: "turn on the lamp", executeLowRiskCommands: false)
        )

        let plan = planner.plan(for: "turn on the lamp", context: context)

        #expect(plan.isFallbackOnly)
        #expect(plan.graph.id == "direct-command-fallback-graph")
        #expect(plan.graph.entryNodeIDs == [AgentID.ruleFallback.rawValue])
        #expect(plan.graph.nodes.map(\.id) == [
            AgentID.ruleFallback.rawValue,
            AgentID.bixbyFallback.rawValue,
            AgentID.unsupportedCommand.rawValue
        ])
    }

    @Test
    func graphPlannerBuildsDirectCommandGraphWhenModelsAvailable() {
        let planner = GraphPlanner(policy: OrchestratorPolicyEngine(isModelAvailable: { true }))
        let context = ResolutionContext(
            request: CommandRequest(text: "turn on the lamp", executeLowRiskCommands: false)
        )

        let plan = planner.plan(for: "turn on the lamp", context: context)

        #expect(!plan.isFallbackOnly)
        #expect(plan.graph.id == "direct-command-graph")
        #expect(plan.graph.nodes.contains { $0.id == AgentID.retrievalJudge.rawValue })
        #expect(plan.graph.nodes.contains { $0.id == AgentID.capabilityResolution.rawValue })
        #expect(plan.graph.nodes.contains { node in
            node.id == AgentID.mockExecution.rawValue &&
                node.executionPolicy == .safetyGate &&
                node.guardCondition == .canExecuteCommand
        })
        #expect(plan.graph.edges.contains(GraphEdge(from: AgentID.retrievalJudge.rawValue, to: AgentID.candidateRanking.rawValue)))
        #expect(plan.graph.edges.contains(GraphEdge(from: AgentID.candidateHydration.rawValue, to: AgentID.capabilityResolution.rawValue)))
        #expect(plan.graph.edges.contains(GraphEdge(from: AgentID.capabilityResolution.rawValue, to: AgentID.instructionComposer.rawValue)))
        #expect(plan.graph.edges.contains(GraphEdge(from: AgentID.executionPlanning.rawValue, to: AgentID.mockExecution.rawValue)))
        #expect(plan.graph.entryNodeIDs.contains(AgentID.language.rawValue))
    }

    @Test
    func operationGraphCatalogSelectsAutomationCreationFocusedGraphs() {
        let context = ResolutionContext(
            request: CommandRequest(text: "Turn on AC everyday at 7 AM", executeLowRiskCommands: false)
        )
        let unavailableCatalog = OperationGraphCatalog.defaultCatalog(
            policy: OrchestratorPolicyEngine(isModelAvailable: { false })
        )
        let availableCatalog = OperationGraphCatalog.defaultCatalog(
            policy: OrchestratorPolicyEngine(isModelAvailable: { true })
        )

        #expect(unavailableCatalog.plan(for: .executeDeviceCommand, context: context).graph.id == "direct-command-fallback-graph")
        #expect(unavailableCatalog.plan(for: .executeDeviceCommand, context: context).isFallbackOnly)
        #expect(availableCatalog.plan(for: .executeDeviceCommand, context: context).graph.id == "direct-command-graph")
        #expect(unavailableCatalog.plan(for: .automationCreation, context: context).graph.id == "automation-creation-graph")
        #expect(unavailableCatalog.plan(for: .unsupported, context: context).graph.id == "unsupported-graph")

        let outOfScopeOperations: [HomeAutomationOperationKind] = [
            .automationUpdate,
            .automationDeletion,
            .automationQuery,
            .sceneCreation,
            .routineExecution
        ]
        for operation in outOfScopeOperations {
            #expect(unavailableCatalog.plan(for: operation, context: context).graph.id == "unsupported-graph")
        }
    }

    @Test
    func graphPlannerRoutesOutOfScopeOperationsToUnsupportedGraph() {
        let planner = GraphPlanner(policy: OrchestratorPolicyEngine(isModelAvailable: { false }))
        let context = ResolutionContext(
            request: CommandRequest(text: "Delete my morning automation", executeLowRiskCommands: false)
        )

        let plan = planner.plan(
            for: context.request.text,
            context: context,
            operation: .automationDeletion
        )

        #expect(!plan.isFallbackOnly)
        #expect(plan.graph.id == "unsupported-graph")
        #expect(plan.graph.goal == .unsupported)
        #expect(plan.graph.nodes.map(\.id) == [AgentID.unsupportedCommand.rawValue])
        #expect(GraphValidator().validate(plan.graph).isEmpty)
    }

    @Test
    func graphSchedulerResolvesAgentByCapability() async {
        let graph = OrchestrationGraph(
            id: "capability-resolution",
            goal: .rootRouting,
            nodes: [
                GraphNode(id: "detect-operation", requirement: .byCapability(.operationDetection))
            ],
            edges: [],
            entryNodeIDs: ["detect-operation"]
        )
        let registry = AgentRegistry(
            agents: [
                StubGraphAgent(
                    id: .operationDetection,
                    capabilities: [.operationDetection],
                    operations: [.executeDeviceCommand, .automationCreation, .unsupported],
                    priority: 10
                )
            ]
        )
        let contextStore = ResolutionContextStore(
            request: CommandRequest(text: "turn on lamp", executeLowRiskCommands: false)
        )

        let result = await GraphScheduler().execute(
            graph,
            registry: registry,
            contextStore: contextStore,
            eventBus: AgentEventBus(),
            policy: OrchestratorPolicyEngine(isModelAvailable: { true }),
            circuitBreakers: CircuitBreakerRegistry(),
            runID: UUID()
        )

        let context = await contextStore.snapshot()
        #expect(result.exit == nil)
        #expect(context.trace.map(\.agentID) == [.operationDetection])
        #expect(result.metrics.nodeStatuses["detect-operation"] == .completed)
        #expect(result.metrics.selectedAgents["detect-operation"] == AgentID.operationDetection.rawValue)
    }

    @Test
    func graphSchedulerAcceptsNearBoundaryAgentResult() async {
        let graph = OrchestrationGraph(
            id: "near-timeout-result",
            goal: .rootRouting,
            nodes: [
                GraphNode(id: AgentID.operationDetection.rawValue, requirement: .byID(.operationDetection))
            ],
            edges: [],
            entryNodeIDs: [AgentID.operationDetection.rawValue]
        )
        let contextStore = ResolutionContextStore(
            request: CommandRequest(text: "turn on lamp", executeLowRiskCommands: false)
        )

        let result = await GraphScheduler().execute(
            graph,
            registry: AgentRegistry(
                agents: [
                    SlowSuccessGraphAgent(
                        id: .operationDetection,
                        timeoutNanoseconds: 50_000_000,
                        delayNanoseconds: 75_000_000
                    )
                ]
            ),
            contextStore: contextStore,
            eventBus: AgentEventBus(),
            policy: OrchestratorPolicyEngine(isModelAvailable: { true }),
            circuitBreakers: CircuitBreakerRegistry(),
            runID: UUID()
        )

        let context = await contextStore.snapshot()
        #expect(result.exit == nil)
        #expect(context.trace.map(\.agentID) == [.operationDetection])
        #expect(result.metrics.nodeStatuses[AgentID.operationDetection.rawValue] == .completed)
    }

    @Test
    func graphSchedulerFailsClosedWhenMandatoryCircuitIsOpen() async {
        let circuitBreakers = CircuitBreakerRegistry(threshold: 1, recoveryInterval: 60)
        let breaker = await circuitBreakers.breaker(for: .confirmationPolicy)
        await breaker.recordFailure()

        let draft = HomeCommandDraft(
            intent: .unlock,
            targetDeviceID: "front_door_lock",
            capability: "lock",
            command: "unlock",
            needsClarification: false,
            requiresConfirmation: false,
            confidence: 1
        )
        let contextStore = ResolutionContextStore(
            request: CommandRequest(text: "unlock it", executeLowRiskCommands: true)
        )
        await contextStore.setDraft(draft)
        await contextStore.setHydratedCandidates([Self.frontDoorLock()])

        let result = await GraphScheduler().execute(
            OrchestrationGraph(
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
            ),
            registry: AgentRegistry(
                agents: [
                    StubGraphAgent(
                        id: .confirmationPolicy,
                        capabilities: [.confirmationPolicy],
                        operations: [.executeDeviceCommand],
                        priority: 0
                    )
                ]
            ),
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
        #expect(result.metrics.nodeStatuses[AgentID.confirmationPolicy.rawValue] == .skipped)
    }

    @Test
    func graphRuntimeResolvesFallbackDirectCommand() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve("Turn on the bedroom lamp", executeLowRiskCommands: false)

        #expect(result.aggregation.finalCandidateIDs == ["bedroom_lamp"])
        #expect(result.draft?.targetDeviceID == "bedroom_lamp")
        guard case .readyToExecute(let plan) = result.resolution else {
            Issue.record("Expected graph fallback to produce a ready-to-execute resolution.")
            return
        }
        #expect(!plan.requiresConfirmation)
        #expect(plan.steps.first?.deviceID == "bedroom_lamp")
    }

    @Test
    func directCommandMatrixResolvesThroughGraphRuntime() async throws {
        let commands = [
            "Turn on the TV",
            "Set the bedroom lamp to 40 percent",
            "Make the bedroom AC cooler by 2 degrees",
            "Unlock the front door",
            "Run movie time"
        ]

        for command in commands {
            let orchestrator = HomeCommandOrchestrator(
                deviceRegistry: MockHomeDeviceRegistry(),
                foundationModelAvailability: { false }
            )

            let result = try await orchestrator.resolve(command, executeLowRiskCommands: false)
            let metrics = try #require(await orchestrator.lastMetrics())

            #expect(metrics.graphRun != nil)
            #expect(Self.resolutionKind(result.resolution) != "unsupported")
        }
    }

    @Test
    func graphRuntimeMetricsCaptureNodeStatusesAndSelectedAgents() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        _ = try await orchestrator.resolve("Turn on the bedroom lamp", executeLowRiskCommands: false)
        let metrics = try #require(await orchestrator.lastMetrics())
        let graphRun = try #require(metrics.graphRun)

        #expect(metrics.fallbackUsed)
        #expect(graphRun.graphID == "direct-command-fallback-graph")
        #expect(graphRun.nodeStatuses[AgentID.ruleFallback.rawValue] == .completed)
        #expect(graphRun.selectedAgents[AgentID.ruleFallback.rawValue] == AgentID.ruleFallback.rawValue)
        #expect(graphRun.skippedNodeIDs.contains(AgentID.bixbyFallback.rawValue))
        #expect(graphRun.skippedNodeIDs.contains(AgentID.unsupportedCommand.rawValue))
    }

    @Test
    func graphRuntimeRequiresConfirmationForHighRiskCommand() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve("Unlock the front door", executeLowRiskCommands: false)

        guard case .requiresConfirmation(let draft) = result.resolution else {
            Issue.record("Expected high-risk graph command to require confirmation.")
            return
        }

        #expect(draft.targetDeviceID == "front_door_lock")
    }

    @Test
    func graphRuntimeUsesConversationMemory() async throws {
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
    func graphSchedulerSkipsMockExecutionWhenPolicyCannotExecute() async {
        let contextStore = ResolutionContextStore(
            request: CommandRequest(text: "turn on lamp", executeLowRiskCommands: false)
        )
        let result = await runMockExecutionGraph(contextStore: contextStore)
        let context = await contextStore.snapshot()

        guard case .readyToExecute = context.resolution else {
            Issue.record("Expected skipped mock execution to preserve ready-to-execute resolution.")
            return
        }
        #expect(result.metrics.nodeStatuses[AgentID.executionPlanning.rawValue] == GraphNodeRunStatus.completed)
        #expect(result.metrics.nodeStatuses[AgentID.mockExecution.rawValue] == GraphNodeRunStatus.skipped)
    }

    @Test
    func graphSchedulerRunsMockExecutionWhenPolicyCanExecute() async {
        let contextStore = ResolutionContextStore(
            request: CommandRequest(text: "turn on lamp", executeLowRiskCommands: true)
        )
        let result = await runMockExecutionGraph(contextStore: contextStore)
        let context = await contextStore.snapshot()

        guard case .executed(let plan, let updatedDevice) = context.resolution else {
            Issue.record("Expected mock execution to produce executed resolution.")
            return
        }
        #expect(plan.steps.first?.deviceID == "bedroom_lamp")
        #expect(updatedDevice.id == "bedroom_lamp")
        #expect(result.metrics.nodeStatuses[AgentID.mockExecution.rawValue] == GraphNodeRunStatus.completed)
    }
}

private struct StubGraphAgent: AnyHomeAgent {
    let id: AgentID
    let capabilities: Set<AgentCapability>
    let manifest: AgentManifest
    let timeoutNanoseconds: UInt64 = 1_000_000_000

    init(
        id: AgentID,
        capabilities: Set<AgentCapability>,
        operations: Set<HomeAutomationOperationKind>,
        priority: Int
    ) {
        self.id = id
        self.capabilities = capabilities
        let defaults = AgentManifestDefaults.manifest(id: id, capabilities: capabilities)
        self.manifest = AgentManifest(
            id: id,
            capabilities: capabilities,
            supportedOperations: operations,
            consumes: defaults.consumes,
            produces: defaults.produces,
            safetyRole: defaults.safetyRole,
            retryPolicy: defaults.retryPolicy,
            priority: priority
        )
    }

    func run(context: ResolutionContext) async -> AgentRunResult {
        .success(ResolutionContextPatch(agentID: id))
    }
}

private struct SlowSuccessGraphAgent: AnyHomeAgent {
    let id: AgentID
    let timeoutNanoseconds: UInt64
    let delayNanoseconds: UInt64
    let capabilities: Set<AgentCapability> = []

    func run(context: ResolutionContext) async -> AgentRunResult {
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        return .success(ResolutionContextPatch(agentID: id))
    }
}

private struct ReadyExecutionGraphAgent: AnyHomeAgent {
    let id = AgentID.executionPlanning
    let capabilities: Set<AgentCapability> = [.executionPlanning]
    let timeoutNanoseconds: UInt64 = 1_000_000_000

    func run(context: ResolutionContext) async -> AgentRunResult {
        let plan = Phase3GraphRuntimeTests.singleLampPlan()
        return .success(
            ResolutionContextPatch(
                agentID: id,
                updates: [
                    ResolutionContextPatchKey.executionPlan.rawValue: AnySendableValue(plan),
                    ResolutionContextPatchKey.resolution.rawValue: AnySendableValue(HomeCommandResolution.readyToExecute(plan))
                ]
            )
        )
    }
}

private struct ExecutedMockGraphAgent: AnyHomeAgent {
    let id = AgentID.mockExecution
    let capabilities: Set<AgentCapability> = [.execution]
    let timeoutNanoseconds: UInt64 = 1_000_000_000

    func run(context: ResolutionContext) async -> AgentRunResult {
        let plan = context.executionPlan ?? Phase3GraphRuntimeTests.singleLampPlan()
        let device = HomeCandidateRecord(
            id: "bedroom_lamp",
            displayName: "Bedroom Lamp",
            deviceType: "light",
            room: "bedroom",
            capabilities: ["switch"],
            supportedCommands: ["switch": ["on", "off"]],
            currentState: ["switch": "on"]
        )
        return .success(
            ResolutionContextPatch(
                agentID: id,
                updates: [
                    ResolutionContextPatchKey.resolution.rawValue: AnySendableValue(HomeCommandResolution.executed(plan, updatedDevice: device))
                ]
            )
        )
    }
}

private struct ComparableExecutionStep: Equatable {
    let type: String
    let deviceID: String
    let deviceName: String
    let capability: String
    let command: String
    let value: String?
    let attribute: String?
    let valueFormula: String?

    init(_ step: HomeAutomationExecutionStep) {
        self.type = step.type
        self.deviceID = step.deviceID
        self.deviceName = step.deviceName
        self.capability = step.capability
        self.command = step.command
        self.value = step.value
        self.attribute = step.attribute
        self.valueFormula = step.valueFormula
    }
}

private extension Phase3GraphRuntimeTests {
    static func singleLampPlan() -> HomeAutomationExecutionPlan {
        HomeAutomationExecutionPlan(
            steps: [
                HomeAutomationExecutionStep(
                    type: "command",
                    deviceID: "bedroom_lamp",
                    deviceName: "Bedroom Lamp",
                    capability: "switch",
                    command: "on"
                )
            ],
            requiresConfirmation: false
        )
    }

    static func bedroomLamp() -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: "bedroom_lamp",
            displayName: "Bedroom Lamp",
            deviceType: "light",
            room: "bedroom",
            capabilities: ["switch"],
            supportedCommands: ["switch": ["on", "off"]],
            currentState: ["switch": "off"]
        )
    }

    static func frontDoorLock() -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: "front_door_lock",
            displayName: "Front Door Lock",
            deviceType: "lock",
            room: "entry",
            capabilities: ["lock"],
            supportedCommands: ["lock": ["lock", "unlock"]],
            riskLevel: .high
        )
    }

    func runMockExecutionGraph(contextStore: ResolutionContextStore) async -> GraphSchedulerResult {
        await contextStore.setDraft(
            HomeCommandDraft(
                intent: .turnOn,
                targetDeviceID: "bedroom_lamp",
                capability: "switch",
                command: "on",
                needsClarification: false,
                requiresConfirmation: false,
                confidence: 1
            )
        )
        await contextStore.setHydratedCandidates([Self.bedroomLamp()])

        let graph = OrchestrationGraph(
            id: "mock-execution-policy",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(id: AgentID.executionPlanning.rawValue, requirement: .byID(.executionPlanning)),
                GraphNode(
                    id: AgentID.mockExecution.rawValue,
                    requirement: .byID(.mockExecution),
                    executionPolicy: .safetyGate,
                    guardCondition: .canExecuteCommand
                )
            ],
            edges: [
                GraphEdge(from: AgentID.executionPlanning.rawValue, to: AgentID.mockExecution.rawValue)
            ],
            entryNodeIDs: [AgentID.executionPlanning.rawValue]
        )

        return await GraphScheduler().execute(
            graph,
            registry: AgentRegistry(agents: [
                ReadyExecutionGraphAgent(),
                ExecutedMockGraphAgent()
            ]),
            contextStore: contextStore,
            eventBus: AgentEventBus(),
            policy: OrchestratorPolicyEngine(isModelAvailable: { true }),
            circuitBreakers: CircuitBreakerRegistry(),
            runID: UUID()
        )
    }

    static func resolutionKind(_ resolution: HomeCommandResolution) -> String {
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
        case .automationDrafted:
            return "automationDrafted"
        case .automationRequiresConfirmation:
            return "automationRequiresConfirmation"
        }
    }
}
