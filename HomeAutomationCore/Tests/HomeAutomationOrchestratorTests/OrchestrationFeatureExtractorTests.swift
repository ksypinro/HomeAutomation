import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Orchestration feature extractor")
struct OrchestrationFeatureExtractorTests {

    @Test("direct command preparation is deterministic and records no model calls")
    func directCommandPreparationIsDeterministicAndNoModelCalls() async throws {
        let registry = MockHomeDeviceRegistry()
        let request = CommandRequest(text: "turn on the bedroom lamp", executeLowRiskCommands: false)
        let firstExtractor = OrchestrationFeatureExtractor(
            registry: registry,
            clock: ManualExtractorClock(values: [10_000_000_000, 10_003_000_000])
        )
        let secondExtractor = OrchestrationFeatureExtractor(
            registry: registry,
            clock: ManualExtractorClock(values: [10_000_000_000, 10_003_000_000])
        )
        let ledger = FoundationModelUsageLedger(runID: "phase3-prep")

        let first = await FoundationModelUsageLedgerScope.$current.withValue(ledger) {
            await firstExtractor.prepare(.init(
                request: request,
                foundationModelAvailability: .unavailable,
                ragAvailability: .unknown,
                gateDepth: .none,
                warmStateHint: .likelyCold
            ))
        }
        let second = await secondExtractor.prepare(.init(
            request: request,
            foundationModelAvailability: .unavailable,
            ragAvailability: .unknown,
            gateDepth: .none,
            warmStateHint: .likelyCold
        ))
        let usage = await ledger.snapshot()

        #expect(first.featureSnapshot == second.featureSnapshot)
        #expect(first.deterministicEnvelope.command?.targetDeviceID == "bedroom_lamp")
        #expect(first.featureSnapshot.operation.value == .executeDeviceCommand)
        #expect(first.featureSnapshot.exactTemplateMatch.value == true)
        #expect(first.featureSnapshot.candidateTopTwoMargin.value ?? 0 > 0)
        #expect(usage.summary.actualCallCount == 0)
        #expect(usage.entries.isEmpty)
    }

    @Test("memory reference and hints are preserved")
    func memoryReferenceAndHintsArePreserved() async {
        let extractor = OrchestrationFeatureExtractor(
            registry: MockHomeDeviceRegistry(),
            clock: ManualExtractorClock(values: [1, 1])
        )
        let hint = MemoryHint(
            deviceID: "bedroom_lamp",
            capability: "switch",
            confidence: 0.9,
            reason: "previous turn"
        )

        let prepared = await extractor.prepare(.init(
            request: CommandRequest(text: "turn it off", executeLowRiskCommands: false),
            memoryHints: [hint],
            foundationModelAvailability: .unavailable,
            ragAvailability: .unknown,
            gateDepth: .none,
            warmStateHint: .likelyWarm
        ))

        #expect(prepared.memoryReferenceDetected)
        #expect(prepared.memoryHints == [hint])
        #expect(prepared.featureSnapshot.memoryReference.value == true)
        #expect(prepared.featureSnapshot.warmStateHint.value == .likelyWarm)
    }

    @Test("automation preparation encodes action condition and ambiguity features")
    func automationPreparationEncodesCoverageFeatures() async {
        let extractor = OrchestrationFeatureExtractor(
            registry: MockHomeDeviceRegistry(),
            clock: ManualExtractorClock(values: [1_000, 2_000])
        )
        let prepared = await extractor.prepare(.init(
            request: CommandRequest(
                text: "turn on the bedroom AC and turn off the living room blinds every day at 7 PM if the living room ceiling light is on and the bedroom AC is off or the living room TV is off",
                executeLowRiskCommands: false
            ),
            foundationModelAvailability: .unavailable,
            ragAvailability: .unknown,
            gateDepth: .moderate,
            warmStateHint: .unknown
        ))

        #expect(prepared.featureSnapshot.operation.value == .automationCreation)
        #expect(prepared.featureSnapshot.actionCount.value ?? 0 >= 2)
        #expect(prepared.featureSnapshot.conditionCount.value ?? 0 >= 1)
        #expect(prepared.featureSnapshot.precedenceAmbiguity.value == true)
        #expect(prepared.featureSnapshot.unsupportedFragmentCount.value == 0)
    }

    @Test("encoded feature snapshot omits raw private text and device names")
    func encodedFeatureSnapshotOmitsRawPrivateTextAndDeviceNames() async throws {
        let extractor = OrchestrationFeatureExtractor(
            registry: MockHomeDeviceRegistry(),
            clock: ManualExtractorClock(values: [5, 5])
        )
        let prepared = await extractor.prepare(.init(
            request: CommandRequest(text: "turn on the bedroom lamp", executeLowRiskCommands: false),
            foundationModelAvailability: .unavailable,
            ragAvailability: .unknown,
            gateDepth: .none,
            warmStateHint: .unknown
        ))

        let data = try JSONEncoder().encode(prepared.featureSnapshot)
        let encoded = String(decoding: data, as: UTF8.self)

        #expect(!encoded.contains("turn on the bedroom lamp"))
        #expect(!encoded.contains("Bedroom Lamp"))
        #expect(!encoded.contains("bedroom_lamp"))
        #expect(!encoded.contains("Prompt"))
    }
}

private final class ManualExtractorClock: FoundationModelMonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UInt64]
    private var fallback: UInt64

    init(values: [UInt64]) {
        self.values = values
        self.fallback = values.last ?? 0
    }

    func nowNanoseconds() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        if !values.isEmpty {
            fallback = values.removeFirst()
        }
        return fallback
    }
}
