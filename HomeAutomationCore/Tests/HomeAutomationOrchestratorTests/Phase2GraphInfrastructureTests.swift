import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite
struct Phase2GraphInfrastructureTests {
    @Test
    func registryExposesManifestsForDefaultAgents() {
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })

        let manifest = registry.manifest(for: .language)

        #expect(manifest?.id == .language)
        #expect(manifest?.capabilities.contains(.languageDetection) == true)
        #expect(manifest?.supportedOperations.contains(.executeDeviceCommand) == true)
        #expect(manifest?.produces.contains("language") == true)
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
                    id: .language,
                    capabilities: [.languageDetection],
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
                    id: .language,
                    capabilities: [.languageDetection],
                    operations: [.executeDeviceCommand],
                    priority: 0
                )
            ]
        )

        #expect(registry.agents(for: .automationCreation).map(\.id) == [.operationDetection, .automationDraft])
        #expect(registry.agents(for: .executeDeviceCommand).map(\.id) == [.operationDetection, .language])
    }

    @Test
    func validGraphPassesValidation() {
        let graph = OrchestrationGraph(
            id: "direct-command-minimal",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(id: "language", requirement: .byID(.language)),
                GraphNode(id: "intent", requirement: .byID(.intentFamily)),
                GraphNode(id: "draft", requirement: .byID(.draftGeneration))
            ],
            edges: [
                GraphEdge(from: "language", to: "intent"),
                GraphEdge(from: "intent", to: "draft")
            ],
            entryNodeIDs: ["language"]
        )

        #expect(GraphValidator().validate(graph).isEmpty)
    }

    @Test
    func graphValidatorDetectsDuplicateNodes() {
        let graph = OrchestrationGraph(
            id: "duplicate",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(id: "language", requirement: .byID(.language)),
                GraphNode(id: "language", requirement: .byID(.domain))
            ],
            edges: [],
            entryNodeIDs: ["language"]
        )

        #expect(GraphValidator().validate(graph).contains(.duplicateNodeID("language")))
    }

    @Test
    func graphValidatorDetectsMissingEdgeReferences() {
        let edge = GraphEdge(from: "language", to: "missing")
        let graph = OrchestrationGraph(
            id: "missing-ref",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(id: "language", requirement: .byID(.language))
            ],
            edges: [edge],
            entryNodeIDs: ["language"]
        )

        #expect(GraphValidator().validate(graph).contains(.missingEdgeEndpoint(edge: edge, missingNodeID: "missing")))
    }

    @Test
    func graphValidatorDetectsCycles() {
        let graph = OrchestrationGraph(
            id: "cycle",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(id: "a", requirement: .byID(.language)),
                GraphNode(id: "b", requirement: .byID(.domain))
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
                GraphNode(id: "start", requirement: .byID(.language)),
                GraphNode(id: "next", requirement: .byID(.domain)),
                GraphNode(id: "orphan", requirement: .byID(.intentFamily))
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
