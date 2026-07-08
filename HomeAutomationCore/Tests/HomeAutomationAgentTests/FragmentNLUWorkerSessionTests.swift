import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import Testing

@Suite("FragmentNLUWorkerSession")
struct FragmentNLUWorkerSessionTests {

    @Test("Mock closure returns provided output")
    func mockClosureReturns() async throws {
        let expected = FragmentNLUOutput(
            intentFamilies: [.power],
            deviceTypes: ["light"],
            rooms: ["bedroom"],
            confidence: 0.95
        )

        let session = FragmentNLUWorkerSession(
            resolve: { @Sendable _ in expected }
        )

        let result = try await session.analyze("turn on the bedroom light")
        #expect(result == expected)
        #expect(result.confidence == 0.95)
        #expect(result.rooms == ["bedroom"])
    }

    @Test("Deterministic fallback when FM unavailable")
    func deterministicFallbackOnUnavailable() async throws {
        let session = FragmentNLUWorkerSession(
            foundationModelAvailability: { false }
        )

        let result = try await session.analyze("turn on the light")
        #expect(result.confidence >= 0.0)
    }

    @Test("FragmentNLUOutput defaults are empty")
    func outputDefaults() {
        let output = FragmentNLUOutput(confidence: 0.5)
        #expect(output.intentFamilies.isEmpty)
        #expect(output.deviceTypes.isEmpty)
        #expect(output.rooms.isEmpty)
        #expect(output.deviceNicknames.isEmpty)
        #expect(output.values.isEmpty)
        #expect(output.confidence == 0.5)
    }

    @Test("FragmentNLUOutput is Codable")
    func codableRoundTrip() throws {
        let output = FragmentNLUOutput(
            intentFamilies: [.power],
            deviceTypes: ["thermostat"],
            rooms: ["kitchen"],
            deviceNicknames: ["the heater"],
            confidence: 0.8
        )

        let data = try JSONEncoder().encode(output)
        let decoded = try JSONDecoder().decode(FragmentNLUOutput.self, from: data)
        #expect(decoded == output)
    }
}
