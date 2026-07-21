import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Dependency-minimal graph compiler")
struct DependencyMinimalGraphCompilerTests {
    @Test("approved templates preserve current graph shapes")
    func approvedTemplatesPreserveCurrentGraphShapes() {
        #expect(GraphTemplateCatalog.rootRouting().graph == GraphPlanner.rootRoutingGraph())
        #expect(GraphTemplateCatalog.directCommand().graph == GraphPlanner.directCommandGraph())
        #expect(GraphTemplateCatalog.fallback().graph == GraphPlanner.fallbackGraph())
        #expect(GraphTemplateCatalog.automationCreation().graph == GraphPlanner.automationCreationGraph())
        #expect(GraphTemplateCatalog.unsupported().graph == GraphPlanner.unsupportedGraph())
        #expect(GraphTemplateCatalog.directCommandFinalization().graph == FinalizationGraphFactory.directCommandFinalizationGraph())
        #expect(GraphTemplateCatalog.automationFinalization().graph == FinalizationGraphFactory.automationFinalizationGraph())
    }

    @Test("valid prepared seed prunes only satisfied deterministic producers")
    func validSeedPrunesSatisfiedDeterministicProducers() {
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })
        let context = seededDirectCommandContext()
        let plan = DependencyMinimalGraphCompiler().makePlan(
            template: GraphTemplateCatalog.directCommand(),
            registry: registry,
            seed: GraphCompilationSeed.from(context: context),
            mode: .active,
            initialContext: context
        )

        let report = plan.compilationReport
        #expect(report?.didCompile == true)
        #expect(report?.didExecuteCompiledGraph == true)
        #expect(report?.fallbackReason == GraphCompilationFallbackReason.none)
        #expect(report?.prunedNodeIDs.contains(AgentID.semanticNLU.rawValue) == true)
        #expect(report?.prunedNodeIDs.contains(AgentID.slotExtraction.rawValue) == true)
        #expect(report?.prunedNodeIDs.contains(AgentID.riskClassification.rawValue) == true)
        #expect(plan.graph.nodes.count < GraphPlanner.directCommandGraph().nodes.count)
        #expect(plan.graph.nodes.contains { $0.id == AgentID.safetyValidation.rawValue })
        #expect(plan.graph.nodes.contains { $0.id == AgentID.confirmationPolicy.rawValue })
        #expect(GraphValidator().validate(plan.graph, registry: registry, initialContext: context).isEmpty)
    }

    @Test("shadow mode compiles but executes the static template graph")
    func shadowModeCompilesButExecutesStaticTemplate() {
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })
        let context = seededDirectCommandContext()
        let plan = DependencyMinimalGraphCompiler().makePlan(
            template: GraphTemplateCatalog.directCommand(),
            registry: registry,
            seed: GraphCompilationSeed.from(context: context),
            mode: .shadow,
            initialContext: context
        )

        #expect(plan.graph == GraphPlanner.directCommandGraph())
        #expect(plan.compilationReport?.didCompile == true)
        #expect(plan.compilationReport?.didExecuteCompiledGraph == false)
        #expect(plan.compilationReport?.compiledGraphID == "direct-command-graph-compiled-v1")
        #expect(plan.compilationReport?.fallbackReason == GraphCompilationFallbackReason.none)
    }

    @Test("invalid seed falls back to static graph")
    func invalidSeedFallsBackToStaticGraph() {
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })
        let seed = GraphCompilationSeed(
            availableKeys: ["request.text", ResolutionContextPatchKey.resolutionState.rawValue],
            isTrustedFresh: false,
            diagnostics: ["stale registry"]
        )
        let plan = DependencyMinimalGraphCompiler().makePlan(
            template: GraphTemplateCatalog.directCommand(),
            registry: registry,
            seed: seed,
            mode: .active
        )

        #expect(plan.graph == GraphPlanner.directCommandGraph())
        #expect(plan.compilationReport?.fallbackReason == .invalidSeed)
        #expect(plan.compilationReport?.didExecuteCompiledGraph == false)
        #expect(plan.compilationReport?.validationErrors == ["stale registry"])
    }

    @Test("safety and mutation approval nodes are non-prunable")
    func safetyAndMutationNodesAreNonPrunable() {
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })
        var context = ResolutionContext(
            request: CommandRequest(
                text: "Create a routine to turn on the lamp every day at 7 PM",
                executeLowRiskCommands: false
            )
        )
        context.operation = HomeOperationDetectionResult(
            domain: .homeAutomation,
            operation: .automationCreation,
            confidence: 0.95,
            reason: "test"
        )
        context.resolutionState = HomeResolutionState.forOperation(
            text: context.request.text,
            operation: context.operation!
        )
        let seed = GraphCompilationSeed(
            availableKeys: Set(ResolutionContextPatchKey.allCases.map(\.rawValue))
                .union(["request.text", "request.executeLowRiskCommands", "request.automationCreationOptions"]),
            isTrustedFresh: true
        )
        let plan = DependencyMinimalGraphCompiler().makePlan(
            template: GraphTemplateCatalog.automationCreation(),
            registry: registry,
            seed: seed,
            mode: .active,
            initialContext: context
        )

        let nodeIDs = Set(plan.graph.nodes.map { $0.id })
        #expect(nodeIDs.contains(AgentID.automationValidation.rawValue))
        #expect(nodeIDs.contains(AgentID.smartThingsRuleCreation.rawValue))
        #expect(plan.compilationReport?.prunedNodeIDs.contains(AgentID.automationValidation.rawValue) == false)
        #expect(plan.compilationReport?.prunedNodeIDs.contains(AgentID.smartThingsRuleCreation.rawValue) == false)
    }

    @Test("automation seed prunes only valid prepared producers")
    func automationSeedPrunesOnlyValidPreparedProducers() {
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })
        var context = ResolutionContext(
            request: CommandRequest(
                text: "Create a routine to turn on the lamp every day at 7 PM",
                executeLowRiskCommands: false
            )
        )
        context.operation = HomeOperationDetectionResult(
            domain: .homeAutomation,
            operation: .automationCreation,
            confidence: 0.96,
            reason: "test"
        )
        context.resolutionState = HomeResolutionState.forOperation(
            text: context.request.text,
            operation: context.operation!
        )
        context.setArtifact(
            AutomationComponentPlan(
                trigger: AutomationTriggerComponent(id: "t1", rawText: "every day at 7 PM", kindHint: .schedule),
                actions: [AutomationActionComponent(id: "a1", rawText: "turn on lamp", order: 0)],
                conditions: [],
                conditionTree: nil,
                unsupportedFragments: [],
                confidence: 0.9
            ),
            for: ContextArtifactKeys.automationComponentPlan()
        )

        let plan = DependencyMinimalGraphCompiler().makePlan(
            template: GraphTemplateCatalog.automationCreation(),
            registry: registry,
            seed: GraphCompilationSeed.from(context: context),
            mode: .active,
            initialContext: context
        )

        #expect(plan.compilationReport?.fallbackReason == GraphCompilationFallbackReason.none)
        #expect(plan.compilationReport?.prunedNodeIDs == [AgentID.automationComponentSegmentation.rawValue])
        #expect(plan.graph.nodes.contains { $0.id == AgentID.automationComponentFanOut.rawValue })
        #expect(plan.graph.nodes.contains { $0.id == AgentID.automationValidation.rawValue })
    }

    @Test("validation failures fall back to static graph with report")
    func validationFailuresFallBackToStaticGraphWithReport() {
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })
        let badGraph = OrchestrationGraph(
            id: "bad-cycle-template",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(id: AgentID.semanticNLU.rawValue, requirement: .byID(.semanticNLU)),
                GraphNode(id: AgentID.slotExtraction.rawValue, requirement: .byID(.slotExtraction))
            ],
            edges: [
                GraphEdge(from: AgentID.semanticNLU.rawValue, to: AgentID.slotExtraction.rawValue),
                GraphEdge(from: AgentID.slotExtraction.rawValue, to: AgentID.semanticNLU.rawValue)
            ],
            entryNodeIDs: [AgentID.semanticNLU.rawValue]
        )
        let template = GraphTemplate(
            templateID: .directCommand,
            graph: badGraph,
            intentionalEdges: Set(badGraph.edges)
        )
        let context = ResolutionContext(
            request: CommandRequest(text: "Turn on the living room lamp", executeLowRiskCommands: false)
        )
        let seed = GraphCompilationSeed(
            availableKeys: [
                "request.text",
                "request.executeLowRiskCommands",
                "request.automationCreationOptions"
            ],
            isTrustedFresh: true
        )

        let plan = DependencyMinimalGraphCompiler().makePlan(
            template: template,
            registry: registry,
            seed: seed,
            mode: .active,
            initialContext: context
        )

        #expect(plan.graph == badGraph)
        #expect(plan.compilationReport?.fallbackReason == .validationFailed)
        #expect(plan.compilationReport?.didExecuteCompiledGraph == false)
        #expect(plan.compilationReport?.validationErrors.isEmpty == false)
    }

    @Test("critical path metadata is deterministic and external to graph identity")
    func criticalPathMetadataIsDeterministicAndExternalToGraphIdentity() {
        let graph = GraphPlanner.directCommandGraph()
        let first = CriticalPathAnalyzer().analyze(graph)
        let second = CriticalPathAnalyzer().analyze(graph)

        #expect(first == second)
        #expect(first.graphID == graph.id)
        #expect(first.nodeMetadata[AgentID.semanticNLU.rawValue]?.downstreamNodeIDs.isEmpty == false)
        #expect(GraphPlanner.directCommandGraph() == graph)
    }

    @Test("runtime dependencies keep compiler disabled by default")
    func runtimeDependenciesKeepCompilerDisabledByDefault() {
        let coordinator = HomeAutomationCoordinator(foundationModelAvailability: { false })
        let defaultDeps = coordinator.makeRuntimeDependencies()
        let explicitDeps = coordinator.makeRuntimeDependencies(graphCompilationMode: .shadow)

        #expect(defaultDeps.graphCompilationMode == .disabled)
        #expect(explicitDeps.graphCompilationMode == .shadow)
    }

    private func seededDirectCommandContext() -> ResolutionContext {
        var context = ResolutionContext(
            request: CommandRequest(text: "Turn on the living room lamp", executeLowRiskCommands: false)
        )
        context.intent = HomeIntentFamilyResult(topFamilies: [.power], confidence: 0.95)
        context.deviceType = HomeDeviceTypeResult(deviceTypes: ["light"], confidence: 0.95)
        context.slots = HomeSlotExtractionResult(
            rooms: ["living room"],
            deviceNicknames: ["lamp"],
            values: [
                HomeExtractedSlot(name: "action", rawValue: "turn on", confidence: 0.96),
                HomeExtractedSlot(name: "target", rawValue: "living room lamp", confidence: 0.94)
            ],
            modes: [],
            confidence: 0.95
        )
        context.risk = HomeRiskClassificationResult(
            riskLevel: .low,
            requiresConfirmation: false,
            reason: "low-risk test command",
            confidence: 0.95
        )
        context.resolutionState = HomeResolutionState.forOperation(
            text: context.request.text,
            operation: HomeOperationDetectionResult(
                domain: .homeAutomation,
                operation: .executeDeviceCommand,
                confidence: 0.95,
                reason: "test"
            )
        )
        return context
    }
}
