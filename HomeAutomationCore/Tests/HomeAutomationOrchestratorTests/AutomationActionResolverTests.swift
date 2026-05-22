import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite
struct AutomationActionResolverTests {

    // MARK: - AutomationActionResolver Tests

    @Test
    func singleActionResolvesToSwitchOnCommand() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on bedroom AC everyday at 7 AM",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.resolvedActions.count == 1)
        #expect(plan.resolvedActions[0].draft.capability == "switch")
        #expect(plan.resolvedActions[0].draft.command == "on")
        #expect(plan.resolvedActions[0].originalText.lowercased().contains("turn on"))
    }

    @Test
    func singleActionResolvesTargetDevice() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on bedroom AC everyday at 7 AM",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.resolvedActions[0].device?.id == "bedroom_ac")
    }

    @Test
    func directGraphActionResolutionSeedsRoutingState() async throws {
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })
        let resolver = AutomationActionResolver(
            registry: registry,
            graphPlanner: GraphPlanner(policy: OrchestratorPolicyEngine(isModelAvailable: { true })),
            policy: OrchestratorPolicyEngine(isModelAvailable: { true })
        )

        let result = await resolver.resolve(
            "Turn on bedroom AC",
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        #expect(result.isResolved)
        #expect(result.draft?.targetDeviceID == "bedroom_ac")
        #expect(result.draft?.capability == "switch")
        #expect(result.draft?.command == "on")
    }

    @Test
    func allActionsStartConcurrentlyByDefault() async throws {
        let graph = OrchestrationGraph(
            id: "slow-test-direct-command-graph",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(
                    id: AgentID.ruleFallback.rawValue,
                    requirement: .byID(.ruleFallback)
                )
            ],
            edges: [],
            entryNodeIDs: [AgentID.ruleFallback.rawValue]
        )
        let registry = AgentRegistry(
            agents: [SlowSuccessAgent(delayNanoseconds: 200_000_000)]
        )
        let resolver = AutomationActionResolver(
            registry: registry,
            graphPlanner: GraphPlanner(
                catalog: OperationGraphCatalog(
                    providers: [StaticDirectCommandGraphProvider(graph: graph)]
                )
            ),
            policy: OrchestratorPolicyEngine(isModelAvailable: { true })
        )
        let eventBus = AgentEventBus()
        let runID = UUID()

        _ = await resolver.resolveAll(
            ["Turn on bedroom AC", "Turn off bedroom lamp", "Turn on kitchen strip light"],
            eventBus: eventBus,
            runID: runID
        )
        await eventBus.finish()

        var events: [OrchestratorPipelineEvent] = []
        for await event in await eventBus.stream() {
            events.append(event)
        }

        let a1Running = try #require(events.firstIndex {
            $0.stage == "automationActionResolution:a1" && $0.status == .running
        })
        let a2Running = try #require(events.firstIndex {
            $0.stage == "automationActionResolution:a2" && $0.status == .running
        })
        let a3Running = try #require(events.firstIndex {
            $0.stage == "automationActionResolution:a3" && $0.status == .running
        })
        let a1Finished = try #require(events.firstIndex {
            $0.stage == "automationActionResolution:a1" &&
                ($0.status == .completed || $0.status == .failed)
        })

        #expect(a1Running < a1Finished)
        #expect(a2Running < a1Finished)
        #expect(a3Running < a1Finished)
    }

    @Test
    func multipleActionDescriptionsResolveIndependently() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on AC and turn off the bedroom lamp every day at 7 AM",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.resolvedActions.count >= 1)
        // First action should always be present and resolved
        let first = plan.resolvedActions.first
        #expect(first?.draft.capability != nil)
        #expect(first?.draft.command != nil)
    }

    @Test
    func resolvedActionDoesNotMockExecute() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on bedroom lamp everyday at 7 AM",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(result.resolution.displaySummary)")
            return
        }
        // The action should NOT have been executed — it should be draft-only.
        // An executed resolution would be `.executed(...)`, not `.automationDrafted(...)`.
        #expect(plan.resolvedActions.count == 1)
        #expect(plan.resolvedActions[0].draft.capability == "switch")
    }

    @Test
    func automationDraftContainsSmartThingsJSON() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on bedroom AC everyday at 7 AM",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.smartThingsRuleJSON != nil)
        #expect(plan.smartThingsRuleJSON?.contains("\"every\"") == true)
        #expect(plan.smartThingsRuleJSON?.contains("\"command\"") == true)
    }

    @Test
    func automationDraftContainsTriggerInfo() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on bedroom AC everyday at 7 AM",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(result.resolution.displaySummary)")
            return
        }
        guard case .schedule(let schedule) = plan.ruleDraft.trigger else {
            Issue.record("Expected schedule trigger")
            return
        }
        #expect(schedule.repeatRule == .everyDay)
        #expect(schedule.timeOfDay?.hour == 7)
        #expect(schedule.timeOfDay?.minute == 0)
    }

    @Test
    func unsupportedWeekdayScheduleProducesCompilationReason() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on AC every Monday at 7 AM",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted with unsupported compilation reason")
            return
        }
        #expect(plan.smartThingsRuleJSON == nil)
        #expect(plan.unsupportedCompilationReason != nil)
    }

    // MARK: - Direct Command Regression

    @Test
    func directCommandStillWorksAfterRefactor() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on the bedroom lamp",
            executeLowRiskCommands: false
        )

        guard case .readyToExecute = result.resolution else {
            Issue.record("Expected direct command readyToExecute, got \(result.resolution.displaySummary)")
            return
        }
        #expect(result.draft?.targetDeviceID == "bedroom_lamp")
    }

    // MARK: - AutomationActionResolutionResult Model Tests

    @Test
    func resultNeedsClarificationProperty() {
        let result = AutomationActionResolutionResult(
            resolvedAction: nil,
            retrievedCandidates: [],
            hydratedCandidates: [],
            selectedCandidateIDs: [],
            draft: nil,
            resolution: .needsClarification("Which AC?"),
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: [],
                needsClarification: true,
                confidence: 0
            )
        )
        #expect(result.needsClarification == true)
        #expect(result.isResolved == false)
        #expect(result.isUnsupported == false)
    }

    @Test
    func resultUnsupportedProperty() {
        let result = AutomationActionResolutionResult(
            resolvedAction: nil,
            retrievedCandidates: [],
            hydratedCandidates: [],
            selectedCandidateIDs: [],
            draft: nil,
            resolution: .unsupported("Not supported"),
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: [],
                needsClarification: false,
                confidence: 0
            )
        )
        #expect(result.isUnsupported == true)
        #expect(result.isResolved == false)
        #expect(result.needsClarification == false)
    }

    @Test
    func resultRequiresConfirmationProperty() {
        let result = AutomationActionResolutionResult(
            resolvedAction: nil,
            retrievedCandidates: [],
            hydratedCandidates: [],
            selectedCandidateIDs: [],
            draft: nil,
            resolution: .requiresConfirmation(
                HomeCommandDraft(
                    intent: .lock,
                    targetDeviceID: "lock",
                    capability: "lock",
                    command: "lock",
                    needsClarification: false,
                    requiresConfirmation: true,
                    confidence: 0.9
                )
            ),
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: [],
                needsClarification: false,
                confidence: 0.9
            )
        )
        #expect(result.requiresConfirmation == true)
    }

    // MARK: - Operation Detection Regression

    @Test
    func operationDetectorRoutesDailySchedule() {
        let detector = HomeOperationDetectionService()
        let result = detector.detect("Turn on AC everyday at 7 AM")
        #expect(result.operation == .automationCreation)
    }

    @Test
    func operationDetectorRoutesDirectCommand() {
        let detector = HomeOperationDetectionService()
        let result = detector.detect("Turn on the TV")
        #expect(result.operation == .executeDeviceCommand)
    }

    @Test
    func operationDetectorRoutesDeviceTrigger() {
        let detector = HomeOperationDetectionService()
        let result = detector.detect("When motion is detected turn on the hallway light")
        #expect(result.operation == .automationCreation)
    }
}

private struct StaticDirectCommandGraphProvider: OperationGraphProvider {
    let operation = HomeAutomationOperationKind.executeDeviceCommand
    let graph: OrchestrationGraph

    func makePlan(context: ResolutionContext) -> GraphExecutionPlan {
        GraphExecutionPlan(graph: graph)
    }
}

private struct SlowSuccessAgent: AnyHomeAgent {
    let id = AgentID.ruleFallback
    let capabilities: Set<AgentCapability> = [.ruleFallback]
    let timeoutNanoseconds: UInt64 = 5_000_000_000
    let delayNanoseconds: UInt64

    func run(context: ResolutionContext) async -> AgentRunResult {
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        return .success(ResolutionContextPatch(agentID: id))
    }
}
