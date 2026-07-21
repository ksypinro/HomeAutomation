import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Orchestration run context")
struct OrchestrationRunContextTests {

    @Test("factory creates one run identity and stores selected automation strategy")
    func factoryCreatesRunIdentityAndStrategy() async {
        let request = CommandRequest(text: "turn on the bedroom lamp", executeLowRiskCommands: false)
        let prepared = await OrchestrationFeatureExtractor(registry: MockHomeDeviceRegistry())
            .prepare(.init(
                request: request,
                foundationModelAvailability: .available,
                ragAvailability: .unknown,
                gateDepth: .none,
                warmStateHint: .unknown
            ))
        let store = ResolutionContextStore(request: request)

        let context = OrchestrationRunContext.make(
            request: request,
            preparedRequest: prepared,
            contextStore: store,
            selectedArm: .graphWithTier1,
            executingArm: .graphWithTier1
        )
        await context.setAutomationActionStrategy()

        #expect(context.traceID == context.runID.uuidString)
        #expect(context.usageLedger.runID == context.runID.uuidString)
        #expect(await store.scopedValue(for: AutomationRuntimeContextKeys.actionResolutionStrategy) == .tier1MiniPipeline)
    }

    @Test("input and outcome helpers publish bounded terminal events")
    func eventHelpersPublishInputAndOutcome() async {
        let request = CommandRequest(text: "turn on the bedroom lamp", executeLowRiskCommands: false)
        let prepared = await OrchestrationFeatureExtractor(registry: MockHomeDeviceRegistry())
            .prepare(.init(
                request: request,
                foundationModelAvailability: .unavailable,
                ragAvailability: .unknown,
                gateDepth: .none,
                warmStateHint: .unknown
            ))
        let context = OrchestrationRunContext.make(
            request: request,
            preparedRequest: prepared,
            contextStore: ResolutionContextStore(request: request),
            selectedArm: .graph,
            executingArm: .graph
        )
        let stream = await context.eventBus.stream()

        await context.publishInputEvent(detail: request.text)
        let operation = HomeOperationDetectionResult(
            domain: .unsupported,
            operation: .unsupported,
            confidence: 0,
            reason: "test"
        )
        await context.publishOutcomeEvent(result: HomeAutomationResolverResult(
            state: HomeResolutionState.forOperation(text: request.text, operation: operation),
            retrievedCandidates: [],
            aggregation: HomeCandidateAggregationResult(finalCandidateIDs: [], needsClarification: false, confidence: 0),
            hydratedCandidates: [],
            draft: nil,
            resolution: .unsupported("test")
        ))
        await context.eventBus.finish()

        var stages: [String] = []
        for await event in stream {
            stages.append(event.stage)
        }

        #expect(stages == ["input", "outcome"])
    }
}
