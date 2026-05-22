import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite
struct Phase2GraphInfrastructureTests {
    @Test
    func registryExposesManifestsForDefaultAgents() {
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })

        let manifest = registry.manifest(for: .semanticNLU)

        #expect(manifest?.id == .semanticNLU)
        #expect(manifest?.capabilities.contains(.intentClassification) == true)
        #expect(manifest?.capabilities.contains(.deviceTypeExtraction) == true)
        #expect(manifest?.supportedOperations.contains(.executeDeviceCommand) == true)
        #expect(manifest?.produces.contains("intent") == true)
        #expect(manifest?.produces.contains("deviceType") == true)
    }

    @Test
    func registryFiltersAgentsByCapabilityAndOperation() {
        let registry = AgentRegistry(
            agents: [
                StubManifestAgent(
                    id: .operationDetection,
                    capabilities: [.operationDetection],
                    operations: [.executeDeviceCommand, .automationCreation],
                    priority: 20
                ),
                StubManifestAgent(
                    id: .automationDraft,
                    capabilities: [.automationDrafting],
                    operations: [.automationCreation],
                    priority: 10
                ),
                StubManifestAgent(
                    id: .semanticNLU,
                    capabilities: [.intentClassification, .deviceTypeExtraction],
                    operations: [.executeDeviceCommand],
                    priority: 0
                )
            ]
        )

        #expect(registry.agents(for: .operationDetection, operation: .automationCreation).map(\.id) == [.operationDetection])
        #expect(registry.agents(for: .automationDrafting, operation: .automationCreation).map(\.id) == [.automationDraft])
        #expect(registry.agents(for: .automationDrafting, operation: .executeDeviceCommand).isEmpty)
    }

    @Test
    func registryReturnsAgentsByOperationInPriorityOrder() {
        let registry = AgentRegistry(
            agents: [
                StubManifestAgent(
                    id: .automationDraft,
                    capabilities: [.automationDrafting],
                    operations: [.automationCreation],
                    priority: 10
                ),
                StubManifestAgent(
                    id: .operationDetection,
                    capabilities: [.operationDetection],
                    operations: [.executeDeviceCommand, .automationCreation],
                    priority: 20
                ),
                StubManifestAgent(
                    id: .semanticNLU,
                    capabilities: [.intentClassification, .deviceTypeExtraction],
                    operations: [.executeDeviceCommand],
                    priority: 0
                )
            ]
        )

        #expect(registry.agents(for: .automationCreation).map(\.id) == [.operationDetection, .automationDraft])
        #expect(registry.agents(for: .executeDeviceCommand).map(\.id) == [.operationDetection, .semanticNLU])
    }

    @Test
    func graphSchedulerRunsOperationDetectionNodeAndWritesContext() async {
        let graph = OrchestrationGraph(
            id: "operation-detection-only",
            goal: .rootRouting,
            nodes: [
                GraphNode(id: AgentID.operationDetection.rawValue, requirement: .byID(.operationDetection))
            ],
            edges: [],
            entryNodeIDs: [AgentID.operationDetection.rawValue]
        )
        let contextStore = ResolutionContextStore(
            request: CommandRequest(text: "Turn on AC everyday at 7 AM", executeLowRiskCommands: false)
        )

        let result = await GraphScheduler().execute(
            graph,
            registry: DefaultAgentRegistryFactory.make(foundationModelAvailability: { false }),
            contextStore: contextStore,
            eventBus: AgentEventBus(),
            policy: OrchestratorPolicyEngine(isModelAvailable: { false }),
            circuitBreakers: CircuitBreakerRegistry(),
            runID: UUID()
        )

        let context = await contextStore.snapshot()
        #expect(result.exit == nil)
        #expect(context.operation?.operation == .automationCreation)
        #expect(context.language?.languageCode == "en")
        #expect(context.domain?.domain == .homeAutomation)
        #expect(context.trace.map(\.agentID) == [.operationDetection])
        #expect(result.metrics.nodeStatuses[AgentID.operationDetection.rawValue] == .completed)
    }

    @Test
    func graphSchedulerWritesCheckpointAndCanResumeCompletedNodes() async throws {
        let graph = GraphPlanner.rootRoutingGraph()
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })
        let runID = UUID()
        let checkpointStore = InMemoryGraphCheckpointStore()
        let firstContextStore = ResolutionContextStore(
            request: CommandRequest(text: "Turn on AC everyday at 7 AM", executeLowRiskCommands: false)
        )

        _ = await GraphScheduler().execute(
            graph,
            registry: registry,
            contextStore: firstContextStore,
            eventBus: AgentEventBus(),
            policy: OrchestratorPolicyEngine(isModelAvailable: { false }),
            circuitBreakers: CircuitBreakerRegistry(),
            runID: runID,
            options: GraphSchedulerExecutionOptions(checkpointStore: checkpointStore)
        )

        let checkpoint = try #require(await checkpointStore.latest(runID: runID))
        #expect(checkpoint.completedNodeIDs == [AgentID.operationDetection.rawValue])
        #expect(checkpoint.lastCompletedNodeID == AgentID.operationDetection.rawValue)
        #expect(checkpoint.contextKeys.contains(ResolutionContextPatchKey.operation.rawValue))

        let resumedContextStore = ResolutionContextStore(
            request: CommandRequest(text: "Turn on AC everyday at 7 AM", executeLowRiskCommands: false)
        )
        let resumed = await GraphScheduler().execute(
            graph,
            registry: registry,
            contextStore: resumedContextStore,
            eventBus: AgentEventBus(),
            policy: OrchestratorPolicyEngine(isModelAvailable: { false }),
            circuitBreakers: CircuitBreakerRegistry(),
            runID: runID,
            options: GraphSchedulerExecutionOptions(
                checkpointStore: checkpointStore,
                resumeFromCheckpoint: checkpoint
            )
        )

        let resumedContext = await resumedContextStore.snapshot()
        #expect(resumedContext.trace.isEmpty)
        #expect(resumed.metrics.nodeStatuses[AgentID.operationDetection.rawValue] == .completed)
    }

    @Test
    func graphSchedulerCanPauseBeforeInterruptNode() async {
        let graph = OrchestrationGraph(
            id: "interrupt-before-operation",
            goal: .rootRouting,
            nodes: [
                GraphNode(
                    id: AgentID.operationDetection.rawValue,
                    requirement: .byID(.operationDetection),
                    interrupt: GraphInterrupt(kind: .confirmation, reason: "approval required")
                )
            ],
            edges: [],
            entryNodeIDs: [AgentID.operationDetection.rawValue]
        )
        let runID = UUID()
        let checkpointStore = InMemoryGraphCheckpointStore()
        let contextStore = ResolutionContextStore(
            request: CommandRequest(text: "Turn on the bedroom lamp", executeLowRiskCommands: false)
        )

        let result = await GraphScheduler().execute(
            graph,
            registry: DefaultAgentRegistryFactory.make(foundationModelAvailability: { false }),
            contextStore: contextStore,
            eventBus: AgentEventBus(),
            policy: OrchestratorPolicyEngine(isModelAvailable: { false }),
            circuitBreakers: CircuitBreakerRegistry(),
            runID: runID,
            options: GraphSchedulerExecutionOptions(
                checkpointStore: checkpointStore,
                pauseAtInterrupts: true
            )
        )

        let context = await contextStore.snapshot()
        #expect(context.trace.isEmpty)
        #expect(result.interruption?.interruptedBeforeNodeID == AgentID.operationDetection.rawValue)
        #expect(result.interruption?.interrupt?.kind == .confirmation)
        #expect(await checkpointStore.latest(runID: runID)?.interruptedBeforeNodeID == AgentID.operationDetection.rawValue)
    }

    @Test
    func fileGraphCheckpointStorePersistsLatestCheckpoint() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("home-automation-checkpoints-\(UUID().uuidString)", isDirectory: true)
        let store = FileGraphCheckpointStore(directoryURL: directory)
        let runID = UUID()
        let checkpoint = GraphCheckpointRecord(
            runID: runID.uuidString,
            graphID: "direct-command-graph",
            goal: OrchestrationGoal.executeDeviceCommand.rawValue,
            completedNodeIDs: ["language"],
            pendingNodeIDs: ["domain"],
            lastCompletedNodeID: "language",
            contextKeys: ["language"]
        )

        await store.save(checkpoint)

        let loaded = try #require(await store.latest(runID: runID))
        #expect(loaded.runID == checkpoint.runID)
        #expect(loaded.graphID == checkpoint.graphID)
        #expect(loaded.completedNodeIDs == checkpoint.completedNodeIDs)
        #expect(loaded.pendingNodeIDs == checkpoint.pendingNodeIDs)
        #expect(loaded.lastCompletedNodeID == checkpoint.lastCompletedNodeID)
        #expect(loaded.contextKeys == checkpoint.contextKeys)
    }

    @Test
    func defaultGraphsMarkHumanInterruptBoundaries() {
        let direct = GraphPlanner.directCommandGraph()
        let confirmation = direct.nodes.first { $0.id == AgentID.confirmationPolicy.rawValue }
        #expect(confirmation?.interrupt?.kind == .confirmation)

        let automation = GraphPlanner.automationCreationGraph()
        let smartThingsCreation = automation.nodes.first { $0.id == AgentID.smartThingsRuleCreation.rawValue }
        #expect(smartThingsCreation?.interrupt?.kind == .externalMutationApproval)
    }

    @Test
    func validGraphPassesValidation() {
        let graph = OrchestrationGraph(
            id: "direct-command-minimal",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(id: "semantic", requirement: .byID(.semanticNLU)),
                GraphNode(id: "slots", requirement: .byID(.slotExtraction)),
                GraphNode(id: "draft", requirement: .byID(.draftGeneration))
            ],
            edges: [
                GraphEdge(from: "semantic", to: "slots"),
                GraphEdge(from: "slots", to: "draft")
            ],
            entryNodeIDs: ["semantic"]
        )

        #expect(GraphValidator().validate(graph).isEmpty)
    }

    @Test
    func graphValidatorDetectsDuplicateNodes() {
        let graph = OrchestrationGraph(
            id: "duplicate",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(id: "semantic", requirement: .byID(.semanticNLU)),
                GraphNode(id: "semantic", requirement: .byID(.slotExtraction))
            ],
            edges: [],
            entryNodeIDs: ["semantic"]
        )

        #expect(GraphValidator().validate(graph).contains(.duplicateNodeID("semantic")))
    }

    @Test
    func graphValidatorDetectsMissingEdgeReferences() {
        let edge = GraphEdge(from: "semantic", to: "missing")
        let graph = OrchestrationGraph(
            id: "missing-ref",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(id: "semantic", requirement: .byID(.semanticNLU))
            ],
            edges: [edge],
            entryNodeIDs: ["semantic"]
        )

        #expect(GraphValidator().validate(graph).contains(.missingEdgeEndpoint(edge: edge, missingNodeID: "missing")))
    }

    @Test
    func graphValidatorDetectsCycles() {
        let graph = OrchestrationGraph(
            id: "cycle",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(id: "a", requirement: .byID(.semanticNLU)),
                GraphNode(id: "b", requirement: .byID(.slotExtraction))
            ],
            edges: [
                GraphEdge(from: "a", to: "b"),
                GraphEdge(from: "b", to: "a")
            ],
            entryNodeIDs: ["a"]
        )

        #expect(GraphValidator().validate(graph).contains(.cycleDetected))
    }

    @Test
    func graphValidatorDetectsUnreachableNodesFromExplicitEntry() {
        let graph = OrchestrationGraph(
            id: "unreachable",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(id: "start", requirement: .byID(.semanticNLU)),
                GraphNode(id: "next", requirement: .byID(.slotExtraction)),
                GraphNode(id: "orphan", requirement: .byID(.riskClassification))
            ],
            edges: [
                GraphEdge(from: "start", to: "next")
            ],
            entryNodeIDs: ["start"]
        )

        #expect(GraphValidator().validate(graph).contains(.unreachableNode("orphan")))
    }

    @Test
    func graphValidatorDetectsOptionalSafetyGateFromRegistry() {
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })
        let graph = OrchestrationGraph(
            id: "optional-safety-gate",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(
                    id: "safety",
                    requirement: .byID(.safetyValidation),
                    executionPolicy: .optional
                )
            ],
            edges: [],
            entryNodeIDs: ["safety"]
        )

        #expect(GraphValidator().validate(graph, registry: registry).contains(.optionalSafetyGateNode("safety")))
    }

    @Test
    func graphValidatorAcceptsDefaultGraphManifestDataFlow() {
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })

        #expect(GraphValidator().validate(GraphPlanner.rootRoutingGraph(), registry: registry).isEmpty)
        #expect(GraphValidator().validate(GraphPlanner.directCommandGraph(), registry: registry).isEmpty)
        #expect(GraphValidator().validate(GraphPlanner.automationCreationGraph(), registry: registry).isEmpty)
        #expect(GraphValidator().validate(GraphPlanner.unsupportedGraph(), registry: registry).isEmpty)
    }

    @Test
    func graphValidatorDetectsMissingManifestInputs() {
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })
        let graph = OrchestrationGraph(
            id: "missing-input",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(id: AgentID.draftGeneration.rawValue, requirement: .byID(.draftGeneration))
            ],
            edges: [],
            entryNodeIDs: [AgentID.draftGeneration.rawValue]
        )

        let errors = GraphValidator().validate(graph, registry: registry)

        #expect(errors.contains {
            if case let .missingManifestInput(_, nodeID, key, _) = $0 {
                return nodeID == AgentID.draftGeneration.rawValue &&
                    key == ResolutionContextPatchKey.instructionPackage.rawValue
            }
            return false
        })
    }

    @Test
    func graphValidatorDetectsMissingTerminalOutputs() {
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })
        let graph = OrchestrationGraph(
            id: "language-only",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(id: AgentID.semanticNLU.rawValue, requirement: .byID(.semanticNLU))
            ],
            edges: [],
            entryNodeIDs: [AgentID.semanticNLU.rawValue]
        )

        let errors = GraphValidator().validate(graph, registry: registry)

        #expect(errors.contains {
            if case let .missingTerminalOutput(graphID, nodeID, _, _) = $0 {
                return graphID == "language-only" && nodeID == AgentID.semanticNLU.rawValue
            }
            return false
        })
    }
}

private struct StubManifestAgent: AnyHomeAgent {
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
