import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import Testing

@Suite("DraftVerifierWorkerSession")
struct DraftVerifierWorkerSessionTests {

    // MARK: - Mock closure

    @Test("Mock closure returns provided verdict")
    func mockClosureReturnsVerdict() async throws {
        let expected = DraftVerdict(
            accepted: false,
            disputes: [
                DraftDispute(fieldID: "command.targetDeviceID", kind: .wrongTarget, evidence: "test")
            ]
        )

        let session = DraftVerifierWorkerSession(
            verify: { _, _ in expected },
            foundationModelAvailability: { false }
        )

        let envelope = makeEnvelope()
        let prompt = VerifierPromptBuilder().makeInitialPrompt(envelope: envelope)
        let result = try await session.verify(
            envelope: envelope,
            prompt: prompt,
            session: session.makeSession()
        )

        #expect(result.disputes.count == 1)
        #expect(result.disputes[0].kind == .wrongTarget)
    }

    // MARK: - FM unavailable

    @Test("Throws VerifierUnavailable when FM is unavailable and no mock")
    func unavailableThrows() async {
        let session = DraftVerifierWorkerSession(
            verify: nil,
            foundationModelAvailability: { false }
        )

        let envelope = makeEnvelope()
        let prompt = VerifierPromptBuilder().makeInitialPrompt(envelope: envelope)

        do {
            _ = try await session.verify(
                envelope: envelope,
                prompt: prompt,
                session: session.makeSession()
            )
            #expect(Bool(false), "Should have thrown VerifierUnavailable")
        } catch is VerifierUnavailable {
            // expected
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    // MARK: - Constraint: invented field ID removed

    @Test("Constraint drops disputes with invented field IDs")
    func constraintDropsInventedFields() async throws {
        let session = DraftVerifierWorkerSession(
            verify: { _, _ in
                DraftVerdict(
                    accepted: false,
                    disputes: [
                        DraftDispute(fieldID: "command.targetDeviceID", kind: .wrongTarget, evidence: "valid"),
                        DraftDispute(fieldID: "invented.nonsense", kind: .wrongValue, evidence: "invalid"),
                    ]
                )
            },
            foundationModelAvailability: { false }
        )

        let envelope = makeEnvelope()
        let prompt = VerifierPromptBuilder().makeInitialPrompt(envelope: envelope)
        let result = try await session.verify(
            envelope: envelope,
            prompt: prompt,
            session: session.makeSession()
        )

        #expect(result.disputes.count == 1)
        #expect(result.disputes[0].fieldID == "command.targetDeviceID")
    }

    // MARK: - Constraint: accepted clears disputes

    @Test("Accepted verdict from mock still clears disputes after constraint")
    func acceptedClearsDisputes() async throws {
        let session = DraftVerifierWorkerSession(
            verify: { _, _ in
                DraftVerdict(
                    accepted: true,
                    disputes: [
                        DraftDispute(fieldID: "command.targetDeviceID", kind: .wrongTarget, evidence: "stale")
                    ]
                )
            },
            foundationModelAvailability: { false }
        )

        let envelope = makeEnvelope()
        let prompt = VerifierPromptBuilder().makeInitialPrompt(envelope: envelope)
        let result = try await session.verify(
            envelope: envelope,
            prompt: prompt,
            session: session.makeSession()
        )

        #expect(result.accepted == true)
        #expect(result.disputes.isEmpty)
    }

    // MARK: - Helpers

    private func makeEnvelope() -> DraftEnvelope {
        DraftEnvelope(
            userText: "turn on the bedroom lamp",
            operation: .executeDeviceCommand,
            operationConfidence: 0.92,
            command: CommandDraftSection(
                targetDeviceID: "bedroom_lamp",
                candidateTable: [
                    CompactCandidate(id: "bedroom_lamp", name: "Bedroom Lamp", room: "bedroom", deviceType: "light")
                ],
                capability: "switch",
                commandName: "on",
                parameters: [],
                room: "bedroom"
            ),
            risk: RiskSection(level: .low, floorReason: "test"),
            provenance: [.operation: .rules, .command(.targetDeviceID): .rules],
            fieldConfidence: [.operation: 0.92, .command(.targetDeviceID): 0.88]
        )
    }
}
