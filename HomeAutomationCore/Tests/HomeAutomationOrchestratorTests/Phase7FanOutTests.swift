import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite
struct Phase7FanOutTests {

    // MARK: - Parallel Action Fan-Out

    @Test
    func automationActionResolutionHasAggregateTimeoutBudget() {
        let agent = AutomationActionResolutionAgent(resolverProvider: { nil })

        #expect(agent.timeoutNanoseconds >= 240_000_000_000)
    }

    @Test
    func multipleActionsResolveWithStableOrdering() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on bedroom AC and turn off the bedroom lamp every day at 7 AM",
            executeLowRiskCommands: false
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(String(describing: result.resolution.displaySummary))")
            return
        }
        // Actions must be present and ordered consistently.
        #expect(plan.resolvedActions.count == 2)
        // First action should be the "turn on AC" action.
        let firstAction = plan.resolvedActions[0]
        #expect(firstAction.originalText.lowercased().contains("turn on"))
        #expect(firstAction.device?.id == "bedroom_ac")
        #expect(firstAction.draft.capability == "switch")
        #expect(firstAction.draft.command == "on")
        let secondAction = plan.resolvedActions[1]
        #expect(secondAction.device?.id == "bedroom_lamp")
        #expect(secondAction.draft.command == "off")
    }

    @Test
    func actionScopedOutputsAreIsolatedDuringFanOut() async {
        let store = ResolutionContextStore(
            request: CommandRequest(text: "Turn on lamp and turn off AC every day at 7 AM", executeLowRiskCommands: false)
        )
        let actionOne = HomeCommandDraft(
            intent: .turnOn,
            targetDeviceID: "bedroom_lamp",
            capability: "switch",
            command: "on",
            needsClarification: false,
            requiresConfirmation: false,
            confidence: 0.93
        )
        let actionTwo = HomeCommandDraft(
            intent: .turnOff,
            targetDeviceID: "bedroom_ac",
            capability: "switch",
            command: "off",
            needsClarification: false,
            requiresConfirmation: false,
            confidence: 0.9
        )
        let resolvedActionOne = HomeAutomationResolvedAction(
            originalText: "Turn on lamp",
            draft: actionOne,
            device: HomeCandidateRecord(
                id: "bedroom_lamp", displayName: "Bedroom Lamp",
                deviceType: "light", room: "bedroom",
                capabilities: ["switch"],
                supportedCommands: ["switch": ["on", "off"]]
            ),
            confidence: 0.93
        )
        let resolvedActionTwo = HomeAutomationResolvedAction(
            originalText: "Turn off AC",
            draft: actionTwo,
            device: HomeCandidateRecord(
                id: "bedroom_ac", displayName: "Bedroom AC",
                deviceType: "airConditioner", room: "bedroom",
                capabilities: ["switch"],
                supportedCommands: ["switch": ["on", "off"]]
            ),
            confidence: 0.9
        )

        let aggregate = AutomationActionResolutionAggregate(
            actionDescriptions: ["Turn on lamp", "Turn off AC"],
            results: [
                AutomationActionResolutionResult(
                    resolvedAction: resolvedActionOne,
                    retrievedCandidates: [],
                    hydratedCandidates: [],
                    selectedCandidateIDs: ["bedroom_lamp"],
                    draft: actionOne,
                    resolution: .readyToExecute(
                        HomeAutomationExecutionPlan(
                            steps: [],
                            requiresConfirmation: false
                        )
                    ),
                    aggregation: HomeCandidateAggregationResult(
                        finalCandidateIDs: ["bedroom_lamp"],
                        needsClarification: false,
                        confidence: 0.93
                    )
                ),
                AutomationActionResolutionResult(
                    resolvedAction: resolvedActionTwo,
                    retrievedCandidates: [],
                    hydratedCandidates: [],
                    selectedCandidateIDs: ["bedroom_ac"],
                    draft: actionTwo,
                    resolution: .readyToExecute(
                        HomeAutomationExecutionPlan(
                            steps: [],
                            requiresConfirmation: false
                        )
                    ),
                    aggregation: HomeCandidateAggregationResult(
                        finalCandidateIDs: ["bedroom_ac"],
                        needsClarification: false,
                        confidence: 0.9
                    )
                )
            ]
        )

        // Apply the scoped patch exactly as the contextual adapter does.
        var scopedUpdates: [ContextScope: [String: AnySendableValue]] = [
            .root: [
                AutomationRuntimeContextKeys.actionResolutionAggregate.name: AnySendableValue(aggregate)
            ]
        ]
        for (index, result) in aggregate.results.enumerated() {
            let scope = ContextScope.action("a\(index + 1)")
            var values: [String: AnySendableValue] = [
                "resolution": AnySendableValue(result.resolution)
            ]
            if let draft = result.draft {
                values[ScopedContextKeys.commandDraft(in: scope).name] = AnySendableValue(draft)
            }
            if let resolvedAction = result.resolvedAction {
                values[ScopedContextKeys.resolvedAction(in: scope).name] = AnySendableValue(resolvedAction)
            }
            scopedUpdates[scope] = values
        }

        await store.apply(
            ResolutionContextPatch(
                agentID: .automationActionResolution,
                scopedUpdates: scopedUpdates
            )
        )

        let snapshot = await store.snapshot()

        // Actions are isolated: a1 and a2 have different scoped drafts.
        let a1Draft = snapshot.scopedValue(for: ScopedContextKeys.commandDraft(in: .action("a1")))
        let a2Draft = snapshot.scopedValue(for: ScopedContextKeys.commandDraft(in: .action("a2")))
        #expect(a1Draft?.targetDeviceID == "bedroom_lamp")
        #expect(a2Draft?.targetDeviceID == "bedroom_ac")
        #expect(a1Draft?.command == "on")
        #expect(a2Draft?.command == "off")

        // Resolved actions are also scoped.
        let a1Resolved = snapshot.scopedValue(for: ScopedContextKeys.resolvedAction(in: .action("a1")))
        let a2Resolved = snapshot.scopedValue(for: ScopedContextKeys.resolvedAction(in: .action("a2")))
        #expect(a1Resolved?.device?.id == "bedroom_lamp")
        #expect(a2Resolved?.device?.id == "bedroom_ac")

        // Root draft should NOT be set by scoped action patches.
        #expect(snapshot.draft == nil)
    }

    // MARK: - Condition Operand Scope Isolation

    @Test
    func conditionScopedOutputsAreIsolatedDuringFanOut() async {
        let store = ResolutionContextStore(
            request: CommandRequest(
                text: "Turn on light if door is closed and motion is active",
                executeLowRiskCommands: false
            )
        )

        let recordOne = AutomationConditionOperandResolutionRecord(
            id: "c1", order: 0,
            path: "condition.0.left",
            description: "front door",
            input: .deviceAttribute(description: "front door", deviceID: nil, capability: nil, attribute: nil),
            output: .deviceAttribute(
                description: "front door",
                deviceID: "front_door_sensor",
                capability: "contactSensor",
                attribute: "contact"
            )
        )
        let recordTwo = AutomationConditionOperandResolutionRecord(
            id: "c2", order: 1,
            path: "condition.1.left",
            description: "hallway motion",
            input: .deviceAttribute(description: "hallway motion", deviceID: nil, capability: nil, attribute: nil),
            output: .deviceAttribute(
                description: "hallway motion",
                deviceID: "hallway_motion",
                capability: "motionSensor",
                attribute: "motion"
            )
        )

        // Apply scoped condition patches.
        let key1 = AutomationRuntimeContextKeys.conditionOperandResolution(in: .condition("c1"))
        let key2 = AutomationRuntimeContextKeys.conditionOperandResolution(in: .condition("c2"))

        await store.apply(
            ResolutionContextPatch(
                agentID: .automationConditionOperandResolution,
                scopedUpdates: [
                    .root: [
                        AutomationRuntimeContextKeys.conditionOperandResolutionRecords.name:
                            AnySendableValue([recordOne, recordTwo])
                    ],
                    .condition("c1"): [key1.name: AnySendableValue(recordOne)],
                    .condition("c2"): [key2.name: AnySendableValue(recordTwo)]
                ]
            )
        )

        let snapshot = await store.snapshot()

        // Each condition scope is isolated.
        let c1 = snapshot.scopedValue(for: key1)
        let c2 = snapshot.scopedValue(for: key2)
        #expect(c1?.id == "c1")
        #expect(c2?.id == "c2")
        #expect(c1?.output != c2?.output)

        // Root aggregation available.
        let records = snapshot.scopedValue(for: AutomationRuntimeContextKeys.conditionOperandResolutionRecords)
        #expect(records?.count == 2)
    }

    // MARK: - Clarification Propagation

    @Test
    func unresolvedActionProducesClarificationNotSilentFailure() {
        let clarificationResult = AutomationActionResolutionResult(
            resolvedAction: nil,
            retrievedCandidates: [],
            hydratedCandidates: [],
            selectedCandidateIDs: [],
            draft: nil,
            resolution: .needsClarification("Which AC did you mean?"),
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: [],
                needsClarification: true,
                clarificationQuestion: "Which AC did you mean?",
                confidence: 0
            )
        )

        let aggregate = AutomationActionResolutionAggregate(
            actionDescriptions: ["Turn on AC"],
            results: [clarificationResult]
        )

        #expect(aggregate.firstBlockingResolution != nil)
        if case .needsClarification(let question) = aggregate.firstBlockingResolution {
            #expect(question == "Which AC did you mean?")
        } else {
            Issue.record("Expected needsClarification, got \(String(describing: aggregate.firstBlockingResolution))")
        }
    }

    @Test
    func unresolvedConditionOperandProducesClarification() {
        let record = AutomationConditionOperandResolutionRecord(
            id: "c1", order: 0,
            path: "condition.left",
            description: "temperature sensor",
            input: .deviceAttribute(description: "temperature sensor", deviceID: nil, capability: nil, attribute: nil),
            output: .unsupported(rawValue: "Could not resolve 'temperature sensor'")
        )

        #expect(record.isResolved == false)
    }

    // MARK: - Graph Metrics Enrichment

    @Test
    func graphMetricsContainPerActionAndPerConditionNodeStatuses() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on bedroom AC everyday at 7 AM",
            executeLowRiskCommands: false
        )

        guard case .automationDrafted = result.resolution else {
            Issue.record("Expected automationDrafted, got \(String(describing: result.resolution.displaySummary))")
            return
        }

        let metrics = try #require(await orchestrator.lastMetrics())
        #expect(metrics.automationMetrics.automationActionCount >= 1)
        #expect(metrics.automationMetrics.graphNodeStatuses["automationActionResolution:a1"] == GraphNodeRunStatus.completed.rawValue)
    }

    // MARK: - Aggregate Properties

    @Test
    func aggregateResolvedActionsPreservesStableOrder() {
        let actions = (1...3).map { index in
            AutomationActionResolutionResult(
                resolvedAction: HomeAutomationResolvedAction(
                    originalText: "Action \(index)",
                    draft: HomeCommandDraft(
                        intent: .turnOn,
                        targetDeviceID: "device_\(index)",
                        capability: "switch",
                        command: "on",
                        needsClarification: false,
                        requiresConfirmation: false,
                        confidence: 0.9
                    ),
                    device: HomeCandidateRecord(
                        id: "device_\(index)", displayName: "Device \(index)",
                        deviceType: "switch", room: nil,
                        capabilities: ["switch"],
                        supportedCommands: ["switch": ["on"]]
                    ),
                    confidence: 0.9
                ),
                retrievedCandidates: [],
                hydratedCandidates: [],
                selectedCandidateIDs: ["device_\(index)"],
                draft: HomeCommandDraft(
                    intent: .turnOn,
                    targetDeviceID: "device_\(index)",
                    capability: "switch",
                    command: "on",
                    needsClarification: false,
                    requiresConfirmation: false,
                    confidence: 0.9
                ),
                resolution: .readyToExecute(
                    HomeAutomationExecutionPlan(
                        steps: [],
                        requiresConfirmation: false
                    )
                ),
                aggregation: HomeCandidateAggregationResult(
                    finalCandidateIDs: ["device_\(index)"],
                    needsClarification: false,
                    confidence: 0.9
                )
            )
        }

        let aggregate = AutomationActionResolutionAggregate(
            actionDescriptions: ["Action 1", "Action 2", "Action 3"],
            results: actions
        )

        #expect(aggregate.resolvedActions.count == 3)
        #expect(aggregate.resolvedActions.map { $0.device?.id } == ["device_1", "device_2", "device_3"])
        #expect(aggregate.requiresConfirmation == false)
        #expect(aggregate.firstBlockingResolution == nil)
    }

    @Test
    func aggregateDeduplicatesCandidatesAcrossActions() {
        let sharedDevice = HomeCandidateRecord(
            id: "shared_switch", displayName: "Shared Switch",
            deviceType: "switch", room: nil,
            capabilities: ["switch"],
            supportedCommands: ["switch": ["on", "off"]]
        )
        let results = [
            AutomationActionResolutionResult(
                resolvedAction: nil,
                retrievedCandidates: [sharedDevice],
                hydratedCandidates: [sharedDevice],
                selectedCandidateIDs: ["shared_switch"],
                draft: nil,
                resolution: .unsupported("test"),
                aggregation: HomeCandidateAggregationResult(
                    finalCandidateIDs: ["shared_switch"],
                    needsClarification: false, confidence: 0.5
                )
            ),
            AutomationActionResolutionResult(
                resolvedAction: nil,
                retrievedCandidates: [sharedDevice],
                hydratedCandidates: [sharedDevice],
                selectedCandidateIDs: ["shared_switch"],
                draft: nil,
                resolution: .unsupported("test"),
                aggregation: HomeCandidateAggregationResult(
                    finalCandidateIDs: ["shared_switch"],
                    needsClarification: false, confidence: 0.5
                )
            )
        ]

        let aggregate = AutomationActionResolutionAggregate(
            actionDescriptions: ["A", "B"],
            results: results
        )

        // Shared device should appear only once after deduplication.
        #expect(aggregate.retrievedCandidates.count == 1)
        #expect(aggregate.hydratedCandidates.count == 1)
        #expect(aggregate.selectedCandidateIDs.count == 1)
    }
}
