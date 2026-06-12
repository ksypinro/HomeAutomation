import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import Testing

@Suite
struct CapabilityResolutionWorkerTests {
    @Test
    func workerAcceptsValidatedFoundationModelCapabilityDecision() async throws {
        let tv = try await Self.device(id: "living_room_tv")
        let input = Self.input(
            text: "move to next channel in living room TV",
            device: tv
        )
        let worker = CapabilityResolutionWorker(resolve: { _ in
            CapabilityResolutionFMOutput(
                topCapabilities: [
                    CapabilityResolutionFMCapabilityHypothesis(
                        capability: "channel",
                        likelyDeviceIDs: ["living_room_tv"],
                        score: 0.94,
                        evidence: ["The user asks for the next channel."]
                    )
                ],
                selectedTriplet: CapabilityResolutionFMTriplet(
                    deviceID: "living_room_tv",
                    capability: "channel",
                    command: "channelUp",
                    score: 0.91,
                    evidence: ["Tool output showed living_room_tv supports channel.channelUp."]
                ),
                alternativeTriplets: []
            )
        })

        let decision = try await worker.resolve(input)

        #expect(decision.targetDeviceID == "living_room_tv")
        #expect(decision.selectedCapability == "channel")
        #expect(decision.selectedCommand == "channelUp")
        #expect(decision.confidence == 0.91)
    }

    @Test
    func workerRejectsInvalidFoundationModelCapabilityAndFallsBack() async throws {
        let tv = try await Self.device(id: "living_room_tv")
        let input = Self.input(
            text: "turn up volume on living room TV",
            device: tv
        )
        let worker = CapabilityResolutionWorker(resolve: { _ in
            CapabilityResolutionFMOutput(
                topCapabilities: [
                    CapabilityResolutionFMCapabilityHypothesis(
                        capability: "volume",
                        likelyDeviceIDs: ["living_room_tv"],
                        score: 0.99,
                        evidence: ["Invalid natural-language capability that should not be accepted."]
                    )
                ],
                selectedTriplet: CapabilityResolutionFMTriplet(
                    deviceID: "living_room_tv",
                    capability: "volume",
                    command: "increase",
                    score: 0.99,
                    evidence: ["Invalid natural-language capability that should not be accepted."]
                ),
                alternativeTriplets: []
            )
        })

        let decision = try await worker.resolve(input)

        #expect(decision.targetDeviceID == "living_room_tv")
        #expect(decision.selectedCapability == "audioVolume")
        #expect(decision.selectedCommand == "volumeUp")
        #expect(decision.evidence.contains { $0.contains("failed validation") })
    }

    @Test
    func capabilityResolutionToolsExposeCandidateDetailsAndDeviceCapabilities() async throws {
        let tv = try await Self.device(id: "living_room_tv")
        let detailsTool = CapabilityCandidateDeviceDetailsTool(candidates: [tv])
        let capabilitiesTool = CapabilityDeviceCapabilitiesTool(candidates: [tv])
        let allCapabilitiesTool = CapabilityAllCapabilitiesTool(candidates: [tv])

        let details = try await detailsTool.call(
            arguments: CapabilityCandidateDeviceDetailsTool.Arguments(candidateIDs: ["living_room_tv"])
        )
        let capabilities = try await capabilitiesTool.call(
            arguments: CapabilityDeviceCapabilitiesTool.Arguments(deviceID: "living_room_tv")
        )
        let allCapabilities = try await allCapabilitiesTool.call(
            arguments: CapabilityAllCapabilitiesTool.Arguments(candidateDeviceIDs: ["living_room_tv"])
        )

        #expect(details.contains(#""id":"living_room_tv""#))
        #expect(details.contains("channel"))
        #expect(capabilities.contains(#""capability":"channel""#))
        #expect(capabilities.contains("channelUp"))
        #expect(capabilities.contains("audioVolume"))
        #expect(allCapabilities.contains(#""deviceID":"living_room_tv""#))
        #expect(allCapabilities.contains(#""capability":"channel""#))
        #expect(allCapabilities.contains("channelUp"))
        #expect(allCapabilities.contains(#""capability":"audioVolume""#))
    }

    private static func input(text: String, device: HomeCandidateRecord) -> CapabilityResolutionInput {
        CapabilityResolutionInput(
            rawText: text,
            resolutionState: AgentTextParser.deterministicState(for: text, confidence: 1),
            hydratedCandidates: [device],
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: [device.id],
                needsClarification: false,
                confidence: 0.95
            ),
            knowledgeSnippets: []
        )
    }

    private static func device(id: String) async throws -> HomeCandidateRecord {
        let devices = await MockHomeDeviceRegistry().allDevices()
        return try #require(devices.first { $0.id == id })
    }
}
