import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Phase F — Automation Tier 1")
struct AutomationTier1Tests {

    // MARK: - F1: Mini-pipeline

    @Test
    func miniPipelineResolvesSimpleAction() async throws {
        let pipeline = AutomationActionMiniPipeline(
            registry: MockHomeDeviceRegistry(),
            validator: AgentCommandValidator(),
            fragmentNLU: FragmentNLUWorkerSession(foundationModelAvailability: { false }),
            capabilityWorker: CapabilityResolutionWorker(foundationModelAvailability: { false })
        )

        let result = await pipeline.resolve(
            "Turn on bedroom AC",
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        #expect(result.isResolved)
        #expect(result.draft?.capability == "switch")
        #expect(result.draft?.command == "on")
        #expect(result.draft?.targetDeviceID == "bedroom_ac")
    }

    @Test
    func miniPipelineZeroFMCalls() async throws {
        let fmCalled = LockIsolated(false)
        let pipeline = AutomationActionMiniPipeline(
            registry: MockHomeDeviceRegistry(),
            validator: AgentCommandValidator(),
            fragmentNLU: FragmentNLUWorkerSession(
                foundationModelAvailability: {
                    fmCalled.withLock { $0 = true }
                    return false
                }
            ),
            capabilityWorker: CapabilityResolutionWorker(
                foundationModelAvailability: {
                    fmCalled.withLock { $0 = true }
                    return false
                }
            )
        )

        let result = await pipeline.resolve(
            "Turn on bedroom AC",
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        #expect(result.isResolved)
        #expect(!fmCalled.value)
    }

    @Test
    func miniPipelineReturnsNilDraftForGibberish() async throws {
        let pipeline = AutomationActionMiniPipeline(
            registry: MockHomeDeviceRegistry(),
            validator: AgentCommandValidator(),
            fragmentNLU: FragmentNLUWorkerSession(foundationModelAvailability: { false }),
            capabilityWorker: CapabilityResolutionWorker(foundationModelAvailability: { false })
        )

        let result = await pipeline.resolve(
            "xyzzy flurble nonsense",
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        #expect(!result.isResolved)
        #expect(result.draft == nil)
    }

    @Test
    func resolverDispatchesToMiniPipelineWhenPresent() async throws {
        let pipeline = AutomationActionMiniPipeline(
            registry: MockHomeDeviceRegistry(),
            validator: AgentCommandValidator(),
            fragmentNLU: FragmentNLUWorkerSession(foundationModelAvailability: { false }),
            capabilityWorker: CapabilityResolutionWorker(foundationModelAvailability: { false })
        )
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })
        let scheduler = GraphScheduler()
        let resolver = AutomationActionResolver(
            registry: registry,
            graphPlanner: GraphPlanner(policy: OrchestratorPolicyEngine(isModelAvailable: { false })),
            policy: OrchestratorPolicyEngine(isModelAvailable: { false }),
            scheduler: scheduler,
            subgraphRunner: GraphSubgraphRunner(scheduler: scheduler),
            circuitBreakers: CircuitBreakerRegistry(),
            miniPipeline: pipeline
        )

        let result = await resolver.resolve(
            "Turn on bedroom AC",
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        #expect(result.isResolved)
        #expect(result.draft?.capability == "switch")
        #expect(result.subgraphRun == nil)
    }

    // MARK: - F2: τ-gate segmentation

    @Test
    func segmentationTauGateSkipsFMForHighConfidence() async throws {
        let fmCalled = LockIsolated(false)
        let worker = AutomationComponentSegmentationWorkerSession(
            foundationModelAvailability: {
                fmCalled.withLock { $0 = true }
                return false
            },
            deterministicAcceptThreshold: 0.88
        )

        let plan = try await worker.segment("Every day at 7 PM turn on the AC")
        #expect(!plan.actions.isEmpty)
        #expect(plan.confidence >= 0.88)
        #expect(!fmCalled.value)
    }

    @Test
    func segmentationFallsToFMPathForLowConfidence() async throws {
        let fmWouldBeChecked = LockIsolated(false)
        let worker = AutomationComponentSegmentationWorkerSession(
            foundationModelAvailability: {
                fmWouldBeChecked.withLock { $0 = true }
                return false
            },
            deterministicAcceptThreshold: 0.95
        )

        _ = try? await worker.segment("Every day at 7 PM turn on the AC")
        #expect(fmWouldBeChecked.value)
    }

    // MARK: - F2: τ-gate trigger resolution

    @Test
    func triggerTauGateSkipsFMForHighConfidence() async throws {
        let fmCalled = LockIsolated(false)
        let worker = AutomationTriggerResolutionWorkerSession(
            foundationModelAvailability: {
                fmCalled.withLock { $0 = true }
                return false
            },
            deterministicAcceptThreshold: 0.8
        )

        let input = AutomationTriggerResolutionInput(
            component: AutomationTriggerComponent(
                id: "t1",
                rawText: "every day at 7 PM",
                kindHint: .schedule
            ),
            fullUserText: "every day at 7 PM turn on the AC"
        )

        let result = try await worker.resolve(input)
        #expect(result.trigger != nil)
        #expect(result.confidence >= 0.8)
        #expect(!fmCalled.value)
    }

    // MARK: - F2: τ-gate condition resolution

    @Test
    func conditionTauGateSkipsFMForHighConfidence() async throws {
        let fmCalled = LockIsolated(false)
        let worker = AutomationConditionClauseResolutionWorkerSession(
            foundationModelAvailability: {
                fmCalled.withLock { $0 = true }
                return false
            },
            deterministicAcceptThreshold: 0.7
        )

        let input = AutomationConditionClauseResolutionInput(
            component: AutomationConditionComponent(
                id: "c1",
                rawText: "temperature is above 80",
                order: 0
            ),
            fullUserText: "when temperature is above 80 turn on AC",
            availableDevices: [
                HomeCandidateRecord(
                    id: "temp_sensor_1",
                    displayName: "Living Room Temperature Sensor",
                    deviceType: "temperatureSensor",
                    room: "Living Room",
                    capabilities: ["temperatureMeasurement"],
                    supportedCommands: [:]
                )
            ],
            triggerPolicy: .always
        )

        let result = try await worker.resolve(input)
        #expect(result.condition != nil)
        #expect(result.confidence >= 0.7)
        #expect(!fmCalled.value)
    }

    // MARK: - F3: Rule-level risk assessment

    @Test
    func assessFromActionsReturnsLowOrMediumForSafeActions() {
        let assessor = AutomationRiskAssessor()
        let risk = assessor.assessFromActions(["Turn on AC", "Turn off light"])
        #expect(risk.level == .low || risk.level == .medium)
        #expect(risk.level != .high)
        #expect(risk.level != .critical)
    }

    @Test
    func assessFromActionsRaisesForSecurityActions() {
        let assessor = AutomationRiskAssessor()
        let risk = assessor.assessFromActions(["Unlock front door", "Turn off alarm"])
        #expect(risk.level == .high || risk.level == .critical)
    }

    @Test
    func assessFromActionsHandlesEmptyList() {
        let assessor = AutomationRiskAssessor()
        let risk = assessor.assessFromActions([])
        #expect(risk.level == .low)
    }

    // MARK: - F4: Provider flag

    @Test
    func coordinatorMakeActionResolverWithMiniPipeline() {
        let coordinator = AutomationCoordinator(
            foundationModelAvailability: { false },
            useMiniPipeline: true
        )
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })
        let graphCoordinator = GraphCoordinator(
            foundationModelAvailability: { false }
        )
        let resolver = coordinator.makeActionResolver(
            agentRegistry: registry,
            graphCoordinator: graphCoordinator,
            deviceRegistry: MockHomeDeviceRegistry()
        )
        #expect(resolver.usesMiniPipeline)
    }

    @Test
    func coordinatorMakeActionResolverWithoutMiniPipeline() {
        let coordinator = AutomationCoordinator(
            foundationModelAvailability: { false },
            useMiniPipeline: false
        )
        let registry = DefaultAgentRegistryFactory.make(foundationModelAvailability: { false })
        let graphCoordinator = GraphCoordinator(
            foundationModelAvailability: { false }
        )
        let resolver = coordinator.makeActionResolver(
            agentRegistry: registry,
            graphCoordinator: graphCoordinator,
            deviceRegistry: MockHomeDeviceRegistry()
        )
        #expect(!resolver.usesMiniPipeline)
    }
}

private final class LockIsolated<Value>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()

    init(_ value: Value) { _value = value }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&_value)
    }
}
