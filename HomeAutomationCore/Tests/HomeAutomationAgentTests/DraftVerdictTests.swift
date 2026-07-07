import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import Testing

@Suite("DraftVerdict Types")
struct DraftVerdictTests {

    // MARK: - Codable round-trip

    @Test("DraftVerdict round-trips through JSON")
    func verdictCodableRoundTrip() throws {
        let verdict = DraftVerdict(
            accepted: false,
            disputes: [
                DraftDispute(fieldID: "command.targetDeviceID", kind: .wrongTarget, evidence: "User said bedroom, not living room", suggestedValue: "bedroom_lamp"),
                DraftDispute(fieldID: "command.capability", kind: .wrongValue, evidence: "Should be switch not dimmer"),
            ],
            needsClarification: false,
            riskUnderstated: true
        )

        let data = try JSONEncoder().encode(verdict)
        let decoded = try JSONDecoder().decode(DraftVerdict.self, from: data)

        #expect(decoded == verdict)
        #expect(decoded.accepted == false)
        #expect(decoded.disputes.count == 2)
        #expect(decoded.disputes[0].kind == .wrongTarget)
        #expect(decoded.disputes[0].suggestedValue == "bedroom_lamp")
        #expect(decoded.disputes[1].kind == .wrongValue)
        #expect(decoded.riskUnderstated == true)
    }

    @Test("DraftDispute round-trips through JSON")
    func disputeCodableRoundTrip() throws {
        let dispute = DraftDispute(
            fieldID: "automation.actions[0].capability",
            kind: .missing,
            evidence: "No capability was resolved"
        )

        let data = try JSONEncoder().encode(dispute)
        let decoded = try JSONDecoder().decode(DraftDispute.self, from: data)

        #expect(decoded == dispute)
        #expect(decoded.suggestedValue == nil)
    }

    // MARK: - DisputeKind

    @Test("DisputeKind covers all expected cases")
    func disputeKindCases() {
        let allCases = DisputeKind.allCases
        #expect(allCases.count == 7)
        #expect(allCases.contains(.wrongValue))
        #expect(allCases.contains(.missing))
        #expect(allCases.contains(.extraneous))
        #expect(allCases.contains(.wrongTarget))
        #expect(allCases.contains(.wrongOperation))
        #expect(allCases.contains(.valueOutOfRange))
        #expect(allCases.contains(.wrongGrouping))
    }

    // MARK: - Constraint post-processing

    @Test("Accepted verdict clears disputes")
    func acceptedClearsDisputes() {
        let verdict = DraftVerdict(
            accepted: true,
            disputes: [
                DraftDispute(fieldID: "command.targetDeviceID", kind: .wrongTarget, evidence: "test")
            ]
        )

        let constrained = verdict.constrained(
            allowedFieldIDs: Set(["command.targetDeviceID"])
        )

        #expect(constrained.accepted == true)
        #expect(constrained.disputes.isEmpty)
    }

    @Test("Constraint drops disputes with unknown field IDs")
    func constraintDropsUnknownFieldIDs() {
        let verdict = DraftVerdict(
            accepted: false,
            disputes: [
                DraftDispute(fieldID: "command.targetDeviceID", kind: .wrongTarget, evidence: "valid"),
                DraftDispute(fieldID: "invented.field", kind: .wrongValue, evidence: "invalid"),
                DraftDispute(fieldID: "command.capability", kind: .wrongValue, evidence: "valid"),
            ]
        )

        let allowed = Set(["command.targetDeviceID", "command.capability", "command.commandName"])
        let constrained = verdict.constrained(allowedFieldIDs: allowed)

        #expect(constrained.disputes.count == 2)
        #expect(constrained.disputes.allSatisfy { allowed.contains($0.fieldID) })
    }

    @Test("Constraint removes duplicate field IDs")
    func constraintDeduplicates() {
        let verdict = DraftVerdict(
            accepted: false,
            disputes: [
                DraftDispute(fieldID: "command.targetDeviceID", kind: .wrongTarget, evidence: "first"),
                DraftDispute(fieldID: "command.targetDeviceID", kind: .wrongValue, evidence: "second"),
            ]
        )

        let constrained = verdict.constrained(
            allowedFieldIDs: Set(["command.targetDeviceID"])
        )

        #expect(constrained.disputes.count == 1)
        #expect(constrained.disputes[0].evidence == "first")
    }

    @Test("Constraint clamps dispute count to maxDisputes")
    func constraintClampsCount() {
        let disputes = (0..<10).map { i in
            DraftDispute(fieldID: "field\(i)", kind: .wrongValue, evidence: "test \(i)")
        }
        let allowed = Set(disputes.map(\.fieldID))
        let verdict = DraftVerdict(accepted: false, disputes: disputes)
        let constrained = verdict.constrained(allowedFieldIDs: allowed, maxDisputes: 3)

        #expect(constrained.disputes.count == 3)
    }

    // MARK: - Static helpers

    @Test("acceptedVerdict is a clean accept")
    func acceptedVerdictHelper() {
        let v = DraftVerdict.acceptedVerdict
        #expect(v.accepted == true)
        #expect(v.disputes.isEmpty)
        #expect(v.needsClarification == false)
        #expect(v.riskUnderstated == false)
    }
}
