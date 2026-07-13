import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Phase 8 — Residual batching and session lifecycle")
struct ResidualBatchingTests {

    @Test("Condition batch maps outputs by itemID, not position")
    func conditionBatchMapsByItemID() async {
        let resolver = BatchedConditionClauseResolver(
            singleResolver: AutomationConditionClauseResolutionWorkerSession(foundationModelAvailability: { false }),
            foundationModelAvailability: { true },
            resolveBatchOutput: { _ in
                BatchedConditionClauseFMOutput(items: [
                    BatchedConditionClauseItemOutput(
                        itemID: "cond_2",
                        condition: nil,
                        deviceID: nil,
                        capability: nil,
                        attribute: nil,
                        confidence: 0.91
                    ),
                    BatchedConditionClauseItemOutput(
                        itemID: "cond_1",
                        condition: nil,
                        deviceID: nil,
                        capability: nil,
                        attribute: nil,
                        confidence: 0.61
                    ),
                ])
            },
            deterministicAcceptThreshold: 1.0
        )

        let results = await resolver.resolveAll(conditionInputs())

        #expect(results.map(\.id) == ["cond_1", "cond_2"])
        #expect(results.map(\.confidence) == [0.61, 0.91])
    }

    @Test("Condition batch falls back per missing duplicate and unknown item IDs")
    func conditionBatchFallsBackPerBadItemID() async {
        let resolver = BatchedConditionClauseResolver(
            singleResolver: AutomationConditionClauseResolutionWorkerSession(foundationModelAvailability: { false }),
            foundationModelAvailability: { true },
            resolveBatchOutput: { _ in
                BatchedConditionClauseFMOutput(items: [
                    BatchedConditionClauseItemOutput(
                        itemID: "cond_1",
                        condition: nil,
                        deviceID: nil,
                        capability: nil,
                        attribute: nil,
                        confidence: 0.94
                    ),
                    BatchedConditionClauseItemOutput(
                        itemID: "cond_1",
                        condition: nil,
                        deviceID: nil,
                        capability: nil,
                        attribute: nil,
                        confidence: 0.95
                    ),
                    BatchedConditionClauseItemOutput(
                        itemID: "unknown",
                        condition: nil,
                        deviceID: nil,
                        capability: nil,
                        attribute: nil,
                        confidence: 0.99
                    ),
                ])
            },
            deterministicAcceptThreshold: 1.0
        )

        let results = await resolver.resolveAll(conditionInputs())

        #expect(results.count == 2)
        #expect(results[0].id == "cond_1")
        #expect(results[1].id == "cond_2")
        #expect(results[0].confidence == 0.72)
        #expect(results[1].confidence == 0.72)
    }

    @Test("Batched action capability preserves item IDs and falls back missing items")
    func batchedActionCapabilityFallsBackPerItem() async throws {
        let devices = [device(id: "lamp_1")]
        let first = capabilityInput(text: "turn on lamp", devices: devices)
        let second = capabilityInput(text: "switch off lamp", devices: devices)
        let worker = CapabilityResolutionWorker(resolve: { input in
            CapabilityResolutionFMOutput(
                topCapabilities: [
                    CapabilityResolutionFMCapabilityHypothesis(
                        capability: "switch",
                        likelyDeviceIDs: ["lamp_1"],
                        score: 0.8,
                        evidence: ["fallback \(input.rawText)"]
                    )
                ],
                selectedTriplet: CapabilityResolutionFMTriplet(
                    deviceID: "lamp_1",
                    capability: "switch",
                    command: input.rawText.contains("off") ? "off" : "on",
                    score: 0.8,
                    evidence: ["fallback \(input.rawText)"]
                ),
                alternativeTriplets: []
            )
        })
        let resolver = BatchedActionCapabilityResolver(
            worker: worker,
            resolveBatch: { requests in
                [
                    requests[1].itemID: HomeCapabilityDecision(
                        selectedCapability: "switch",
                        selectedCommand: "off",
                        targetDeviceID: "lamp_1",
                        alternatives: [],
                        evidence: ["batched"],
                        confidence: 0.93
                    )
                ]
            }
        )

        let output = await resolver.resolveAll([
            BatchedActionCapabilityRequest(itemID: FoundationModelBatchItemID("a1"), input: first),
            BatchedActionCapabilityRequest(itemID: FoundationModelBatchItemID("a2"), input: second),
        ])

        #expect(output[FoundationModelBatchItemID("a2")]?.confidence == 0.93)
        #expect(output[FoundationModelBatchItemID("a1")]?.selectedCommand == "on")
    }

    @Test("Session pool compatibility facade does not retain released transcripts")
    func sessionPoolDoesNotRetainReleasedTranscripts() async {
        let pool = FoundationModelSessionPool(maxPoolSize: 2)
        await pool.register(kind: .conditionClause, instructions: "Test instructions")

        let first = await pool.acquire(kind: .conditionClause, runID: "run-1")
        await pool.release(kind: .conditionClause, session: first)
        let second = await pool.acquire(kind: .conditionClause, runID: "run-2")
        await pool.release(kind: .conditionClause, session: second)
        let snapshot = await pool.snapshot()

        #expect(await pool.poolSize(for: .conditionClause) == 0)
        #expect(snapshot.createdCount == 2)
        #expect(snapshot.discardedCount == 2)
    }

    @Test("Session factory prewarm records real prefix prewarm metadata")
    func sessionFactoryPrewarmRecordsPrefixMetadata() async {
        let pool = FoundationModelSessionPool(maxPoolSize: 2)
        await pool.register(
            kind: .triggerResolution,
            instructions: "Trigger instructions",
            promptPrefix: "immutable trigger prefix"
        )

        await pool.prewarm(kinds: [.triggerResolution])
        let snapshot = await pool.snapshot()

        #expect(snapshot.prewarmCount == 1)
        #expect(snapshot.prewarmDigests["triggerResolution"] == FoundationModelBatchCompatibilityKey.stableDigest("immutable trigger prefix"))
        #expect(await pool.poolSize(for: .triggerResolution) == 0)
    }

    @Test("Batch coalescer bypasses zero-slack and safety work")
    func coalescerBypassesUnsafeWaits() {
        let coalescer = FoundationModelBatchCoalescer(windowNanoseconds: 10_000)

        #expect(!coalescer.decision(criticalPathSlackMs: 0, isSafetyOrFinalization: false).shouldWait)
        #expect(!coalescer.decision(criticalPathSlackMs: 100, isSafetyOrFinalization: true).shouldWait)
        #expect(coalescer.decision(criticalPathSlackMs: 100, isSafetyOrFinalization: false).shouldWait)
    }

    private func conditionInputs() -> [AutomationConditionClauseResolutionInput] {
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
            HomeCandidateRecord(
                id: "motion_sensor",
                displayName: "Motion Sensor",
                deviceType: "motionSensor",
                room: "hallway",
                capabilities: ["motionSensor"],
                supportedCommands: [:],
                currentState: ["motion": "inactive"]
            ),
        ]
        return [
            AutomationConditionClauseResolutionInput(
                component: AutomationConditionComponent(id: "cond_1", rawText: "front door is locked", order: 0),
                fullUserText: "Turn on lamp if front door is locked and motion sensor inactive",
                availableDevices: devices,
                triggerPolicy: .never
            ),
            AutomationConditionClauseResolutionInput(
                component: AutomationConditionComponent(id: "cond_2", rawText: "motion sensor is inactive", order: 1),
                fullUserText: "Turn on lamp if front door is locked and motion sensor inactive",
                availableDevices: devices,
                triggerPolicy: .never
            ),
        ]
    }

    private func device(id: String) -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: id,
            displayName: "Lamp",
            deviceType: "light",
            room: "bedroom",
            capabilities: ["switch"],
            supportedCommands: ["switch": ["on", "off"]],
            currentState: ["switch": "off"]
        )
    }

    private func capabilityInput(text: String, devices: [HomeCandidateRecord]) -> CapabilityResolutionInput {
        CapabilityResolutionInput(
            rawText: text,
            resolutionState: AgentTextParser.deterministicState(for: text),
            hydratedCandidates: devices,
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: devices.map(\.id),
                needsClarification: false,
                confidence: 0.8
            ),
            knowledgeSnippets: []
        )
    }
}
