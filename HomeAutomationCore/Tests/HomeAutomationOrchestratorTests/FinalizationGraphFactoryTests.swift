import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Finalization graph fragments and seeds")
struct FinalizationGraphFactoryTests {
    @Test("direct-command finalizer preserves mandatory gate order")
    func directCommandFinalizerShape() {
        let graph = FinalizationGraphFactory.directCommandFinalizationGraph()

        #expect(graph.id == "direct-command-finalization-graph")
        #expect(graph.goal == .executeDeviceCommand)
        #expect(graph.entryNodeIDs == [AgentID.safetyValidation.rawValue])
        #expect(graph.nodes.map(\.id) == [
            AgentID.safetyValidation.rawValue,
            AgentID.parameterValidation.rawValue,
            AgentID.confirmationPolicy.rawValue,
            AgentID.executionPlanning.rawValue,
            AgentID.mockExecution.rawValue
        ])
        #expect(graph.edges == [
            GraphEdge(from: AgentID.safetyValidation.rawValue, to: AgentID.parameterValidation.rawValue),
            GraphEdge(from: AgentID.parameterValidation.rawValue, to: AgentID.confirmationPolicy.rawValue),
            GraphEdge(from: AgentID.confirmationPolicy.rawValue, to: AgentID.executionPlanning.rawValue),
            GraphEdge(from: AgentID.executionPlanning.rawValue, to: AgentID.mockExecution.rawValue)
        ])
        #expect(graph.nodes.allSatisfy { $0.executionPolicy == .safetyGate })
        #expect(graph.nodes.first { $0.id == AgentID.confirmationPolicy.rawValue }?.interrupt?.kind == .confirmation)
        #expect(graph.nodes.first { $0.id == AgentID.mockExecution.rawValue }?.guardCondition == .canExecuteCommand)
    }

    @Test("automation finalizer preserves validation, compilation, optional creation, and assembly order")
    func automationFinalizerShape() {
        let graph = FinalizationGraphFactory.automationFinalizationGraph()

        #expect(graph.id == "automation-finalization-graph")
        #expect(graph.goal == .automationCreation)
        #expect(graph.entryNodeIDs == [AgentID.automationValidation.rawValue])
        #expect(graph.nodes.map(\.id) == [
            AgentID.automationValidation.rawValue,
            AgentID.smartThingsCompilation.rawValue,
            AgentID.smartThingsRuleCreation.rawValue,
            AgentID.automationResultAssembly.rawValue
        ])
        #expect(graph.nodes.first?.executionPolicy == .safetyGate)
        #expect(graph.nodes.dropFirst().allSatisfy { $0.executionPolicy == .required })
        #expect(graph.nodes.first { $0.id == AgentID.smartThingsRuleCreation.rawValue }?.interrupt?.kind == .externalMutationApproval)
    }

    @Test("direct-command finalizer validates after seeding a loop command envelope")
    func directCommandFinalizerValidatesWithSeed() async throws {
        let registry = MockHomeDeviceRegistry()
        let envelope = await DeterministicDraftPipeline(registry: registry)
            .makeCommandEnvelope(text: "turn on the bedroom lamp")
        let store = ResolutionContextStore(request: CommandRequest(text: envelope.userText, executeLowRiskCommands: true))

        try await FinalizationSeedBuilder(deviceRegistry: registry)
            .seed(envelope: envelope, into: store)

        let errors = GraphValidator().validate(
            FinalizationGraphFactory.directCommandFinalizationGraph(),
            registry: HomeAutomationCoordinator(deviceRegistry: registry, foundationModelAvailability: { false })
                .makeRuntimeDependencies()
                .agentRegistry,
            initialContext: await store.snapshot()
        )

        #expect(errors.isEmpty)
        let context = await store.snapshot()
        #expect(context.draft?.targetDeviceID == "bedroom_lamp")
        #expect(context.aggregation?.finalCandidateIDs == ["bedroom_lamp"])
        #expect(context.capabilityDecision?.selectedCapability == "switch")
    }

    @Test("automation finalizer validates after seeding a loop automation envelope")
    func automationFinalizerValidatesWithSeed() async throws {
        let registry = MockHomeDeviceRegistry()
        let envelope = await DeterministicDraftPipeline(registry: registry)
            .makeAutomationEnvelope(text: "When the entry contact sensor opens, turn on the porch light")
        let store = ResolutionContextStore(request: CommandRequest(text: envelope.userText, executeLowRiskCommands: true))

        try await FinalizationSeedBuilder(deviceRegistry: registry)
            .seed(envelope: envelope, into: store)

        let errors = GraphValidator().validate(
            FinalizationGraphFactory.automationFinalizationGraph(),
            registry: HomeAutomationCoordinator(deviceRegistry: registry, foundationModelAvailability: { false })
                .makeRuntimeDependencies()
                .agentRegistry,
            initialContext: await store.snapshot()
        )

        #expect(errors.isEmpty)
        let context = await store.snapshot()
        let ruleDraft = try #require(context.artifact(for: ContextArtifactKeys.automationRuleDraft()))
        let aggregate = try #require(context.scopedValue(for: AutomationRuntimeContextKeys.actionResolutionAggregate))
        #expect(ruleDraft.actionDescriptions == ["Turn on the porch light"])
        #expect(aggregate.resolvedActions.first?.draft.targetDeviceID == "porch_light")
        #expect(context.scopedValue(for: AutomationRuntimeContextKeys.conditionOperandResolutionRecords)?.isEmpty == false)
    }

    @Test("seed builder rejects unsupported operations")
    func seedBuilderRejectsUnsupportedOperation() async {
        let envelope = DraftEnvelope(
            userText: "delete my morning routine",
            operation: .automationDeletion,
            operationConfidence: 0.9,
            risk: RiskSection(level: .low, floorReason: "test")
        )
        let store = ResolutionContextStore(request: CommandRequest(text: envelope.userText, executeLowRiskCommands: true))

        await #expect(throws: FinalizationSeedError.unsupportedOperation(.automationDeletion)) {
            try await FinalizationSeedBuilder(deviceRegistry: MockHomeDeviceRegistry())
                .seed(envelope: envelope, into: store)
        }
    }

    @Test("direct-command receipt reports missing gates as incomplete")
    func directCommandReceiptReportsMissingGates() {
        let receipt = ResolutionFinalizationReceipt.directCommand(
            graphRun: GraphRunMetrics(
                graphID: "direct-command-finalization-graph",
                goal: .executeDeviceCommand,
                nodeStatuses: [
                    AgentID.safetyValidation.rawValue: .completed,
                    AgentID.parameterValidation.rawValue: .completed,
                    AgentID.confirmationPolicy.rawValue: .completed
                ]
            ),
            resolution: .readyToExecute(
                HomeAutomationExecutionPlan(
                    steps: [],
                    requiresConfirmation: false
                )
            )
        )

        #expect(receipt?.status == .incomplete)
        #expect(receipt?.missingGateIDs == [
            AgentID.executionPlanning.rawValue,
            AgentID.mockExecution.rawValue
        ])
        #expect(receipt?.failedGateID == nil)
    }

    @Test("direct-command receipt reports failed gates")
    func directCommandReceiptReportsFailedGates() {
        let receipt = ResolutionFinalizationReceipt.directCommand(
            graphRun: GraphRunMetrics(
                graphID: "direct-command-finalization-graph",
                goal: .executeDeviceCommand,
                nodeStatuses: [
                    AgentID.safetyValidation.rawValue: .completed,
                    AgentID.parameterValidation.rawValue: .failed,
                    AgentID.confirmationPolicy.rawValue: .pending,
                    AgentID.executionPlanning.rawValue: .pending,
                    AgentID.mockExecution.rawValue: .pending
                ]
            ),
            resolution: .readyToExecute(
                HomeAutomationExecutionPlan(
                    steps: [],
                    requiresConfirmation: false
                )
            )
        )

        #expect(receipt?.status == .failed)
        #expect(receipt?.failedGateID == AgentID.parameterValidation.rawValue)
        #expect(receipt?.missingGateIDs.isEmpty == true)
    }

    @Test("automation draft receipt allows skipped dry-run creation gate")
    func automationReceiptAllowsSkippedDryRunCreationGate() {
        let plan = HomeAutomationCreationPlan(
            name: "Daily AC",
            ruleDraft: HomeAutomationRuleDraft(
                name: "Daily AC",
                trigger: .schedule(
                    HomeAutomationScheduleTrigger(
                        repeatRule: .everyDay,
                        timeOfDay: HomeAutomationTimeOfDay(hour: 7, minute: 0)
                    )
                ),
                condition: nil,
                actionDescriptions: ["Turn on bedroom AC"],
                confidence: 0.9
            ),
            resolvedActions: [],
            smartThingsRuleJSON: "{}",
            requiresConfirmation: false,
            unsupportedCompilationReason: nil
        )
        let receipt = ResolutionFinalizationReceipt.automationCreation(
            graphRun: GraphRunMetrics(
                graphID: "automation-finalization-graph",
                goal: .automationCreation,
                nodeStatuses: [
                    AgentID.automationValidation.rawValue: .completed,
                    AgentID.smartThingsCompilation.rawValue: .completed,
                    AgentID.smartThingsRuleCreation.rawValue: .skipped,
                    AgentID.automationResultAssembly.rawValue: .completed
                ]
            ),
            resolution: .automationDrafted(plan)
        )

        #expect(receipt?.status == .completed)
        #expect(receipt?.missingGateIDs.isEmpty == true)
        #expect(receipt?.failedGateID == nil)
    }
}
