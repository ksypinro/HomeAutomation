import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Phase III — Call Reduction (Batching & Session Pools)")
struct PhaseIIICallReductionTests {

    // MARK: - Batched Condition Resolution

    @Test("Multi-condition automation uses batched resolution path")
    func multiConditionBatchedResolution() async throws {
        let registry = MockHomeDeviceRegistry(devices: [
            HomeCandidateRecord(
                id: "bedroom_lamp",
                displayName: "Bedroom Lamp",
                deviceType: "light",
                room: "bedroom",
                capabilities: ["switch", "switchLevel"],
                supportedCommands: ["switch": ["on", "off"], "switchLevel": ["setLevel"]],
                currentState: ["switch": "off", "level": "50"]
            ),
            HomeCandidateRecord(
                id: "front_door_lock",
                displayName: "Front Door Lock",
                deviceType: "lock",
                room: "hallway",
                capabilities: ["lock"],
                supportedCommands: ["lock": ["lock", "unlock"]],
                currentState: ["lock": "locked"]
            ),
            HomeCandidateRecord(
                id: "motion_sensor",
                displayName: "Bedroom Motion Sensor",
                deviceType: "motionSensor",
                room: "bedroom",
                capabilities: ["motionSensor"],
                supportedCommands: [:],
                currentState: ["motion": "inactive"]
            ),
        ])
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: registry,
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Every day at 7 PM turn on bedroom lamp if front door is locked and motion sensor is inactive",
            executeLowRiskCommands: false
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.resolvedActions.count >= 1)
    }

    @Test("Single-condition automation falls back to individual resolution")
    func singleConditionUsesIndividualResolution() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Every day at 7 PM turn on bedroom lamp if bedroom lamp is off",
            executeLowRiskCommands: false
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.resolvedActions.count == 1)
    }

    // MARK: - Session Pool

    @Test("Session pool manages acquire/release lifecycle")
    func sessionPoolAcquireRelease() async {
        let pool = FoundationModelSessionPool(maxPoolSize: 2)
        await pool.register(kind: .conditionClause, instructions: "Test instructions")

        let session1 = await pool.acquire(kind: .conditionClause)
        #expect(await pool.poolSize(for: .conditionClause) == 0)

        await pool.release(kind: .conditionClause, session: session1)
        #expect(await pool.poolSize(for: .conditionClause) == 1)

        let session2 = await pool.acquire(kind: .conditionClause)
        #expect(await pool.poolSize(for: .conditionClause) == 0)
        _ = session2
    }

    @Test("Session pool respects max pool size")
    func sessionPoolMaxSize() async {
        let pool = FoundationModelSessionPool(maxPoolSize: 1)
        await pool.register(kind: .triggerResolution, instructions: "Test instructions")

        let s1 = await pool.acquire(kind: .triggerResolution)
        let s2 = await pool.acquire(kind: .triggerResolution)

        await pool.release(kind: .triggerResolution, session: s1)
        #expect(await pool.poolSize(for: .triggerResolution) == 1)

        await pool.release(kind: .triggerResolution, session: s2)
        #expect(await pool.poolSize(for: .triggerResolution) == 1)
    }

    @Test("Pre-warming populates pool up to max size")
    func prewarmPopulatesPool() async {
        let pool = FoundationModelSessionPool(maxPoolSize: 2)
        await pool.register(kind: .conditionClause, instructions: "Test instructions")
        await pool.register(kind: .triggerResolution, instructions: "Test instructions")

        await pool.prewarm(kinds: [.conditionClause, .triggerResolution])

        #expect(await pool.poolSize(for: .conditionClause) == 1)
        #expect(await pool.poolSize(for: .triggerResolution) == 1)
    }

    @Test("SessionKind raw values match expected identifiers")
    func sessionKindRawValues() {
        #expect(FoundationModelSessionPool.SessionKind.conditionClause.rawValue == "conditionClause")
        #expect(FoundationModelSessionPool.SessionKind.triggerResolution.rawValue == "triggerResolution")
        #expect(FoundationModelSessionPool.SessionKind.verifier.rawValue == "verifier")
    }

    // MARK: - Batched Condition Resolver Unit

    @Test("BatchedConditionClauseResolver resolves deterministic conditions without FM")
    func batchedResolverDeterministicPath() async {
        let singleResolver = AutomationConditionClauseResolutionWorkerSession(
            foundationModelAvailability: { false }
        )
        let resolver = BatchedConditionClauseResolver(
            singleResolver: singleResolver,
            foundationModelAvailability: { false }
        )

        let devices = [
            HomeCandidateRecord(
                id: "front_door_lock",
                displayName: "Front Door Lock",
                deviceType: "lock",
                room: "hallway",
                capabilities: ["lock"],
                supportedCommands: ["lock": ["lock", "unlock"]],
                currentState: ["lock": "locked"]
            ),
        ]
        let inputs = [
            AutomationConditionClauseResolutionInput(
                component: AutomationConditionComponent(
                    id: "cond_1",
                    rawText: "front door is locked",
                    order: 0
                ),
                fullUserText: "Turn on lamp if front door is locked",
                availableDevices: devices,
                triggerPolicy: .never
            ),
        ]

        let results = await resolver.resolveAll(inputs)
        #expect(results.count == 1)
        #expect(results[0].condition != nil)
    }
}
