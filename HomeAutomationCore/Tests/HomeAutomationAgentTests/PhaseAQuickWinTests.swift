import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationRAG
import Testing

/// Tests for the Phase A quick wins from `Docs/LoopOrchestrationImplementationPlan.md`:
/// NLU soft-timeout parity (A1/A2), scoped threshold-gating (A3),
/// few-shot enrichment skipping (A4), and windowShade verb coverage (A7).
@Suite("Phase A Quick Win Tests")
struct PhaseAQuickWinTests {

    private actor CallCounter {
        private(set) var count = 0

        func increment() {
            count += 1
        }
    }

    private static func markerSemanticResult() -> HomeSemanticNLUResult {
        HomeSemanticNLUResult(
            intent: HomeIntentFamilyResult(topFamilies: [.temperature], confidence: 0.99),
            deviceType: HomeDeviceTypeResult(deviceTypes: ["marker-device"], confidence: 0.99)
        )
    }

    private static func markerSlotResult() -> HomeSlotExtractionResult {
        HomeSlotExtractionResult(
            rooms: ["marker-room"],
            deviceNicknames: [],
            values: [],
            modes: [],
            confidence: 0.99
        )
    }

    // MARK: - A1: Semantic NLU soft timeout

    @Test("Semantic NLU soft timeout falls back to the deterministic result")
    func semanticNLUSoftTimeoutFallsBack() async throws {
        let worker = SemanticNLUWorkerSession(
            modelClassify: { _ in
                try await Task.sleep(nanoseconds: 500_000_000)
                return Self.markerSemanticResult()
            },
            foundationModelAvailability: { true },
            modelSoftTimeoutNanoseconds: 50_000_000
        )

        let result = try await worker.classifySemanticNLU("Turn on the bedroom lamp")

        #expect(!result.deviceType.deviceTypes.contains("marker-device"))
        #expect(result.intent.topFamilies.contains(.power))
    }

    @Test("Semantic NLU agent node timeout is aligned with the other NLU agents")
    func semanticNLUNodeTimeoutAligned() {
        #expect(SemanticNLUAgent(classify: { _ in Self.markerSemanticResult() }).timeoutNanoseconds == 60_000_000_000)
    }

    // MARK: - A3: Threshold-gated model-call override

    @Test("thresholdGated override skips the model for confident deterministic parses")
    func thresholdGatedOverrideSkipsModel() async throws {
        let counter = CallCounter()
        let worker = SemanticNLUWorkerSession(
            modelClassify: { _ in
                await counter.increment()
                return Self.markerSemanticResult()
            },
            foundationModelAvailability: { true }
        )

        let gated = try await worker.classifySemanticNLU(
            "Turn on the bedroom lamp",
            modeOverride: .thresholdGated
        )
        #expect(await counter.count == 0)
        #expect(!gated.deviceType.deviceTypes.contains("marker-device"))

        _ = try await worker.classifySemanticNLU("Turn on the bedroom lamp")
        #expect(await counter.count == 1)
    }

    @Test("thresholdGated override still calls the model for low-confidence parses")
    func thresholdGatedOverrideCallsModelWhenUncertain() async throws {
        let counter = CallCounter()
        let worker = SemanticNLUWorkerSession(
            modelClassify: { _ in
                await counter.increment()
                return Self.markerSemanticResult()
            },
            foundationModelAvailability: { true }
        )

        _ = try await worker.classifySemanticNLU(
            "please handle that thing from before",
            modeOverride: .thresholdGated
        )
        #expect(await counter.count == 1)
    }

    @Test("nluPolicyOverride context artifact threshold-gates the slot extraction agent")
    func artifactOverrideGatesSlotExtractionAgent() async throws {
        let counter = CallCounter()
        let worker = SlotExtractionAgentWorkerSession(
            modelExtract: { _ in
                await counter.increment()
                return Self.markerSlotResult()
            },
            foundationModelAvailability: { true }
        )
        let agent = SlotExtractionAgent(worker: worker)
        let text = "Turn on the bedroom lamp"

        var gatedContext = ResolutionContext(
            request: CommandRequest(text: text, executeLowRiskCommands: false)
        )
        gatedContext.setArtifact(
            NLUModelCallMode.thresholdGated,
            for: ContextArtifactKeys.nluPolicyOverride()
        )
        let gated = try await agent.run(text, context: gatedContext)
        #expect(await counter.count == 0)
        #expect(!gated.rooms.contains("marker-room"))

        let plainContext = ResolutionContext(
            request: CommandRequest(text: text, executeLowRiskCommands: false)
        )
        _ = try await agent.run(text, context: plainContext)
        #expect(await counter.count == 1)
    }

    // MARK: - A4: Few-shot enrichment skipping

    private struct CountingEmbeddingProvider: EmbeddingProviding {
        let counter: CallCounter

        func embed(_ text: String) async -> [Float] {
            await counter.increment()
            return [0, 0, 0]
        }

        func embedBatch(_ texts: [String]) async -> [[Float]] {
            var results: [[Float]] = []
            for text in texts {
                results.append(await embed(text))
            }
            return results
        }
    }

    @Test("Short fragments skip few-shot retrieval; long uncertain inputs still retrieve")
    func fewShotRetrievalSkipsShortFragments() async throws {
        let embedCounter = CallCounter()
        let retriever = ContextRetriever(
            embeddingProvider: CountingEmbeddingProvider(counter: embedCounter),
            vectorStore: VectorStore()
        )
        let agent = SlotExtractionAgent(
            worker: SlotExtractionAgentWorkerSession(extract: { _ in Self.markerSlotResult() }),
            contextRetriever: retriever
        )

        let shortText = "turn on lamp"
        let shortContext = ResolutionContext(
            request: CommandRequest(text: shortText, executeLowRiskCommands: false)
        )
        _ = try await agent.run(shortText, context: shortContext)
        #expect(await embedCounter.count == 0)

        let vagueText = "please do something rather vague for me right now"
        let vagueContext = ResolutionContext(
            request: CommandRequest(text: vagueText, executeLowRiskCommands: false)
        )
        _ = try await agent.run(vagueText, context: vagueContext)
        #expect(await embedCounter.count >= 1)
    }

    // MARK: - A7: windowShade verb coverage

    @Test("Power verbs bind windowShade devices to open/close")
    func powerVerbsBindWindowShade() async throws {
        let registry = MockHomeDeviceRegistry()
        let resolver = AgentRuleBasedResolver(
            registry: registry,
            validator: AgentCommandValidator(),
            executor: AgentPlanExecutor(registry: registry),
            bixbyFallbackMapper: AgentBixbyFallbackMapper()
        )

        let off = try await resolver.resolve("Turn off the living room blinds", executeLowRiskCommands: false)
        #expect(off.draft?.targetDeviceID == "living_room_blinds")
        #expect(off.draft?.capability == "windowShade")
        #expect(off.draft?.command == "close")

        let on = try await resolver.resolve("Turn on the living room blinds", executeLowRiskCommands: false)
        #expect(on.draft?.targetDeviceID == "living_room_blinds")
        #expect(on.draft?.capability == "windowShade")
        #expect(on.draft?.command == "open")
    }

    @Test("Power verbs still bind switch devices to on/off")
    func powerVerbsStillBindSwitchDevices() async throws {
        let registry = MockHomeDeviceRegistry()
        let resolver = AgentRuleBasedResolver(
            registry: registry,
            validator: AgentCommandValidator(),
            executor: AgentPlanExecutor(registry: registry),
            bixbyFallbackMapper: AgentBixbyFallbackMapper()
        )

        let result = try await resolver.resolve("Turn off the bedroom lamp", executeLowRiskCommands: false)
        #expect(result.draft?.capability == "switch")
        #expect(result.draft?.command == "off")
    }
}
