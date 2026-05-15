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
        #expect(plan.graph.edges.contains(GraphEdge(from: AgentID.retrievalJudge.rawValue, to: AgentID.candidateRanking.rawValue)))
        #expect(plan.graph.entryNodeIDs.contains(AgentID.language.rawValue))
    }

    @Test
    func graphSchedulerResolvesAgentByCapability() async {
        let graph = OrchestrationGraph(
            id: "capability-resolution",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(id: "detect-language", requirement: .byCapability(.languageDetection))
            ],
            edges: [],
            entryNodeIDs: ["detect-language"]
        )
        let registry = AgentRegistry(
            agents: [
                StubGraphAgent(
                    id: .language,
                    capabilities: [.languageDetection],
                    operations: [.executeDeviceCommand],
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
        #expect(context.trace.map(\.agentID) == [.language])
        #expect(result.metrics.nodeStatuses["detect-language"] == .completed)
        #expect(result.metrics.selectedAgents["detect-language"] == AgentID.language.rawValue)
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
    func graphRuntimeMatchesLegacyFallbackDirectCommand() async throws {
        let legacy = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false },
            runtimeMode: .legacy
        )
        let graph = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false },
            runtimeMode: .graph
        )

        let legacyResult = try await legacy.resolve("Turn on the bedroom lamp", executeLowRiskCommands: false)
        let graphResult = try await graph.resolve("Turn on the bedroom lamp", executeLowRiskCommands: false)

        #expect(graphResult.aggregation.finalCandidateIDs == legacyResult.aggregation.finalCandidateIDs)
        #expect(graphResult.draft == legacyResult.draft)
        guard case .readyToExecute(let legacyPlan) = legacyResult.resolution,
              case .readyToExecute(let graphPlan) = graphResult.resolution else {
            Issue.record("Expected both runtimes to produce ready-to-execute resolutions.")
            return
        }
        #expect(graphPlan.requiresConfirmation == legacyPlan.requiresConfirmation)
        #expect(graphPlan.steps.map(ComparableExecutionStep.init) == legacyPlan.steps.map(ComparableExecutionStep.init))
    }

    @Test
    func directCommandMatrixMatchesLegacyAndGraphRuntimes() async throws {
        let commands = [
            "Turn on the TV",
            "Set the bedroom lamp to 40 percent",
            "Make the bedroom AC cooler by 2 degrees",
            "Unlock the front door",
            "Run movie time"
        ]

        for command in commands {
            let legacy = HomeCommandOrchestrator(
                deviceRegistry: MockHomeDeviceRegistry(),
                foundationModelAvailability: { false },
                runtimeMode: .legacy
            )
            let graph = HomeCommandOrchestrator(
                deviceRegistry: MockHomeDeviceRegistry(),
                foundationModelAvailability: { false },
                runtimeMode: .graph
            )

            let legacyResult = try await legacy.resolve(command, executeLowRiskCommands: false)
            let graphResult = try await graph.resolve(command, executeLowRiskCommands: false)

            #expect(graphResult.aggregation.finalCandidateIDs == legacyResult.aggregation.finalCandidateIDs)
            #expect(graphResult.draft == legacyResult.draft)
            #expect(Self.resolutionKind(graphResult.resolution) == Self.resolutionKind(legacyResult.resolution))
        }
    }

    @Test
    func graphRuntimeMetricsCaptureNodeStatusesAndSelectedAgents() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false },
            runtimeMode: .graph
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
            foundationModelAvailability: { false },
            runtimeMode: .graph
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
            runtimeMode: .graph,
            conversationMemory: memory
        )

        _ = try await orchestrator.resolve("Turn on the bedroom AC", executeLowRiskCommands: false)
        let result = try await orchestrator.resolve("Make it warmer by 2 degrees", executeLowRiskCommands: false)

        #expect(result.draft?.targetDeviceID == "bedroom_ac")
        #expect(result.retrievedCandidates.contains { $0.id == "bedroom_ac" })
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
        self.manifest = AgentManifest(
            id: id,
            capabilities: capabilities,
            supportedOperations: operations,
            priority: priority
        )
    }

    func run(context: ResolutionContext) async -> AgentRunResult {
        .success(ResolutionContextPatch(agentID: id))
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
