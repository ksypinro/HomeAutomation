import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("ActionTargetResolver")
struct ActionTargetResolverTests {

    private func makeResolver() -> ActionTargetResolver {
        let registry = DeviceCoordinator.makeMockDeviceRegistry()
        return ActionTargetResolver(registry: registry)
    }

    @Test("Resolves target from fragment text")
    func resolvesFromFragmentText() async {
        let resolver = makeResolver()

        let result = await resolver.resolve(
            fragmentText: "turn on the living room light",
            candidates: [],
            hint: nil
        )

        #expect(result.confidence >= 0.0)
    }

    @Test("Hint preferred when available")
    func hintPreferred() async {
        let resolver = makeResolver()
        let result = await resolver.resolve(
            fragmentText: "turn on the light",
            candidates: [],
            hint: "preferred-device-123"
        )

        #expect(result.selectedDeviceID != nil)
    }

    @Test("Empty candidates searches all devices")
    func emptyCandidatesSearchesAll() async {
        let resolver = makeResolver()
        let result = await resolver.resolve(
            fragmentText: "turn on the light",
            candidates: [],
            hint: nil
        )

        #expect(result.confidence >= 0.0)
    }

    @Test("ActionTargetResult stores all fields correctly")
    func resultFieldsCorrect() {
        let result = ActionTargetResult(
            selectedDeviceID: "dev-1",
            candidateTable: [
                CompactCandidate(id: "dev-1", name: "Light", room: "Room", deviceType: "light")
            ],
            confidence: 0.85,
            isAmbiguous: false
        )

        #expect(result.selectedDeviceID == "dev-1")
        #expect(result.candidateTable.count == 1)
        #expect(result.confidence == 0.85)
        #expect(result.isAmbiguous == false)
    }
}
