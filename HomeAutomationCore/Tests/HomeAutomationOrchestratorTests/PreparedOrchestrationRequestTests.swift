import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Prepared orchestration request")
struct PreparedOrchestrationRequestTests {

    @Test("registry fingerprint is stable across device ordering")
    func registryFingerprintIsStableAcrossOrdering() {
        let lamp = HomeCandidateRecord(
            id: "lamp",
            displayName: "Bedroom Lamp",
            deviceType: "light",
            room: "bedroom",
            capabilities: ["switch"],
            supportedCommands: ["switch": ["on", "off"]]
        )
        let lock = HomeCandidateRecord(
            id: "lock",
            displayName: "Front Door",
            deviceType: "lock",
            room: "entry",
            capabilities: ["lock"],
            supportedCommands: ["lock": ["lock", "unlock"]]
        )

        let first = PreparedDeviceSnapshot(devices: [lamp, lock])
        let second = PreparedDeviceSnapshot(devices: [lock, lamp])

        #expect(first.version == second.version)
        #expect(first.freshness(comparedTo: second) == .fresh)
    }

    @Test("registry fingerprint changes when material device data changes")
    func registryFingerprintChangesForMaterialChange() {
        let lamp = HomeCandidateRecord(
            id: "lamp",
            displayName: "Bedroom Lamp",
            deviceType: "light",
            room: "bedroom",
            capabilities: ["switch"],
            supportedCommands: ["switch": ["on", "off"]]
        )
        let dimmer = HomeCandidateRecord(
            id: "lamp",
            displayName: "Bedroom Lamp",
            deviceType: "light",
            room: "bedroom",
            capabilities: ["switch", "switchLevel"],
            supportedCommands: ["switch": ["on", "off"], "switchLevel": ["setLevel"]]
        )

        let prepared = PreparedDeviceSnapshot(devices: [lamp])
        let current = PreparedDeviceSnapshot(devices: [dimmer])

        #expect(prepared.version != current.version)
        #expect(prepared.freshness(comparedTo: current) == .stale)
    }

    @Test("prepared request serializes reusable deterministic artifacts")
    func preparedRequestRoundTrips() async throws {
        let extractor = OrchestrationFeatureExtractor(
            registry: MockHomeDeviceRegistry(),
            clock: ManualFeatureClock(values: [1_000_000_000, 1_004_000_000])
        )
        let request = CommandRequest(text: "turn on the bedroom lamp", executeLowRiskCommands: false)
        let prepared = await extractor.prepare(
            OrchestrationFeatureExtractor.Input(
                request: request,
                memoryHints: [],
                foundationModelAvailability: .unavailable,
                ragAvailability: .unknown,
                gateDepth: .none,
                warmStateHint: .unknown
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(prepared)
        let decoded = try JSONDecoder().decode(PreparedOrchestrationRequest.self, from: data)

        #expect(decoded == prepared)
        #expect(decoded.registryFreshness(comparedTo: prepared.deviceSnapshot) == .fresh)
        #expect(decoded.deterministicEnvelope.command?.targetDeviceID == "bedroom_lamp")
    }
}

private final class ManualFeatureClock: FoundationModelMonotonicClock, @unchecked Sendable {
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
