import Foundation
import HomeAutomationAgents
import HomeAutomationCore

// MARK: - VerifierShadowReport

public struct VerifierShadowReport: Sendable, Codable {
    public let totalCases: Int
    public let verifiedCases: Int
    public let skippedCases: Int
    public let acceptCount: Int
    public let rejectCount: Int
    public let acceptRate: Double
    public let falseAcceptCount: Int
    public let falseRejectCount: Int
    public let falseAcceptRate: Double
    public let falseRejectRate: Double
    public let perFieldConfusion: [String: FieldConfusion]
    public let caseResults: [VerifierShadowCaseResult]

    public init(
        totalCases: Int,
        verifiedCases: Int,
        skippedCases: Int,
        acceptCount: Int,
        rejectCount: Int,
        acceptRate: Double,
        falseAcceptCount: Int,
        falseRejectCount: Int,
        falseAcceptRate: Double,
        falseRejectRate: Double,
        perFieldConfusion: [String: FieldConfusion],
        caseResults: [VerifierShadowCaseResult]
    ) {
        self.totalCases = totalCases
        self.verifiedCases = verifiedCases
        self.skippedCases = skippedCases
        self.acceptCount = acceptCount
        self.rejectCount = rejectCount
        self.acceptRate = acceptRate
        self.falseAcceptCount = falseAcceptCount
        self.falseRejectCount = falseRejectCount
        self.falseAcceptRate = falseAcceptRate
        self.falseRejectRate = falseRejectRate
        self.perFieldConfusion = perFieldConfusion
        self.caseResults = caseResults
    }
}

public struct FieldConfusion: Sendable, Codable {
    public let disputed: Int
    public let correctlyDisputed: Int
    public let falselyDisputed: Int

    public init(disputed: Int, correctlyDisputed: Int, falselyDisputed: Int) {
        self.disputed = disputed
        self.correctlyDisputed = correctlyDisputed
        self.falselyDisputed = falselyDisputed
    }
}

public struct VerifierShadowCaseResult: Sendable, Codable {
    public let caseID: String
    public let userText: String
    public let envelopeAccepted: Bool
    public let verdictAccepted: Bool
    public let disputeCount: Int
    public let disputedFieldIDs: [String]
    public let expectedCorrect: Bool
    public let isFalseAccept: Bool
    public let isFalseReject: Bool
    public let skipped: Bool
    public let skipReason: String?

    public init(
        caseID: String,
        userText: String,
        envelopeAccepted: Bool,
        verdictAccepted: Bool,
        disputeCount: Int,
        disputedFieldIDs: [String],
        expectedCorrect: Bool,
        isFalseAccept: Bool,
        isFalseReject: Bool,
        skipped: Bool = false,
        skipReason: String? = nil
    ) {
        self.caseID = caseID
        self.userText = userText
        self.envelopeAccepted = envelopeAccepted
        self.verdictAccepted = verdictAccepted
        self.disputeCount = disputeCount
        self.disputedFieldIDs = disputedFieldIDs
        self.expectedCorrect = expectedCorrect
        self.isFalseAccept = isFalseAccept
        self.isFalseReject = isFalseReject
        self.skipped = skipped
        self.skipReason = skipReason
    }
}

// MARK: - VerifierShadowRunner

public struct VerifierShadowRunner: Sendable {
    private let pipeline: DeterministicDraftPipeline
    private let verifierSession: DraftVerifierWorkerSession
    private let promptBuilder: VerifierPromptBuilder

    public init(
        registry: any DeviceRegistryProtocol,
        verifierSession: DraftVerifierWorkerSession? = nil,
        promptBuilder: VerifierPromptBuilder = VerifierPromptBuilder()
    ) {
        self.pipeline = DeterministicDraftPipeline(registry: registry)
        self.verifierSession = verifierSession ?? DraftVerifierWorkerSession()
        self.promptBuilder = promptBuilder
    }

    public func run(
        cases: [EvaluationCase],
        caseLimit: Int? = nil
    ) async -> VerifierShadowReport {
        let selectedCases = Array(cases.prefix(caseLimit ?? cases.count))
        var caseResults: [VerifierShadowCaseResult] = []

        for evalCase in selectedCases {
            let result = await runCase(evalCase)
            caseResults.append(result)
        }

        return aggregateReport(caseResults: caseResults)
    }

    private func runCase(_ evalCase: EvaluationCase) async -> VerifierShadowCaseResult {
        let isAutomation = evalCase.expected.operation == .automationCreation
        let envelope: DraftEnvelope
        if isAutomation {
            envelope = await pipeline.makeAutomationEnvelope(text: evalCase.input)
        } else {
            envelope = await pipeline.makeCommandEnvelope(text: evalCase.input)
        }

        let prompt = promptBuilder.makeInitialPrompt(envelope: envelope)
        let session = verifierSession.makeSession()

        let verdict: DraftVerdict
        do {
            verdict = try await verifierSession.verify(
                envelope: envelope,
                prompt: prompt,
                session: session
            )
        } catch is VerifierUnavailable {
            return VerifierShadowCaseResult(
                caseID: evalCase.id,
                userText: evalCase.input,
                envelopeAccepted: true,
                verdictAccepted: true,
                disputeCount: 0,
                disputedFieldIDs: [],
                expectedCorrect: true,
                isFalseAccept: false,
                isFalseReject: false,
                skipped: true,
                skipReason: "Foundation model unavailable"
            )
        } catch {
            return VerifierShadowCaseResult(
                caseID: evalCase.id,
                userText: evalCase.input,
                envelopeAccepted: true,
                verdictAccepted: true,
                disputeCount: 0,
                disputedFieldIDs: [],
                expectedCorrect: true,
                isFalseAccept: false,
                isFalseReject: false,
                skipped: true,
                skipReason: "Verifier error: \(error.localizedDescription)"
            )
        }

        let expectedCorrect = isEnvelopeCorrect(envelope: envelope, expected: evalCase.expected)
        let isFalseAccept = verdict.accepted && !expectedCorrect
        let isFalseReject = !verdict.accepted && expectedCorrect

        return VerifierShadowCaseResult(
            caseID: evalCase.id,
            userText: evalCase.input,
            envelopeAccepted: expectedCorrect,
            verdictAccepted: verdict.accepted,
            disputeCount: verdict.disputes.count,
            disputedFieldIDs: verdict.disputes.map(\.fieldID),
            expectedCorrect: expectedCorrect,
            isFalseAccept: isFalseAccept,
            isFalseReject: isFalseReject
        )
    }

    private func isEnvelopeCorrect(
        envelope: DraftEnvelope,
        expected: EvaluationExpectedOutput
    ) -> Bool {
        if let expectedOp = expected.operation, envelope.operation != expectedOp {
            return false
        }
        if !expected.expectedDeviceIDs.isEmpty {
            let envelopeDeviceID = envelope.command?.targetDeviceID
                ?? envelope.automation?.actions.first?.command.targetDeviceID
            if let deviceID = envelopeDeviceID, !expected.expectedDeviceIDs.contains(deviceID) {
                return false
            }
            if envelopeDeviceID == nil {
                return false
            }
        }
        if let expectedCap = expected.capability {
            let envelopeCap = envelope.command?.capability
                ?? envelope.automation?.actions.first?.command.capability
            if envelopeCap != expectedCap {
                return false
            }
        }
        if let expectedCmd = expected.command {
            let envelopeCmd = envelope.command?.commandName
                ?? envelope.automation?.actions.first?.command.commandName
            if envelopeCmd != expectedCmd {
                return false
            }
        }
        return true
    }

    private func aggregateReport(
        caseResults: [VerifierShadowCaseResult]
    ) -> VerifierShadowReport {
        let verified = caseResults.filter { !$0.skipped }
        let skipped = caseResults.filter { $0.skipped }
        let accepted = verified.filter { $0.verdictAccepted }
        let falseAccepts = verified.filter { $0.isFalseAccept }
        let falseRejects = verified.filter { $0.isFalseReject }

        let verifiedCount = verified.count
        let acceptRate = verifiedCount > 0 ? Double(accepted.count) / Double(verifiedCount) : 0
        let falseAcceptRate = verifiedCount > 0 ? Double(falseAccepts.count) / Double(verifiedCount) : 0
        let falseRejectRate = verifiedCount > 0 ? Double(falseRejects.count) / Double(verifiedCount) : 0

        var fieldConfusion: [String: FieldConfusion] = [:]
        for result in verified {
            for fieldID in result.disputedFieldIDs {
                let existing = fieldConfusion[fieldID] ?? FieldConfusion(disputed: 0, correctlyDisputed: 0, falselyDisputed: 0)
                let correctlyDisputed = !result.expectedCorrect ? 1 : 0
                let falselyDisputed = result.expectedCorrect ? 1 : 0
                fieldConfusion[fieldID] = FieldConfusion(
                    disputed: existing.disputed + 1,
                    correctlyDisputed: existing.correctlyDisputed + correctlyDisputed,
                    falselyDisputed: existing.falselyDisputed + falselyDisputed
                )
            }
        }

        return VerifierShadowReport(
            totalCases: caseResults.count,
            verifiedCases: verifiedCount,
            skippedCases: skipped.count,
            acceptCount: accepted.count,
            rejectCount: verified.count - accepted.count,
            acceptRate: acceptRate,
            falseAcceptCount: falseAccepts.count,
            falseRejectCount: falseRejects.count,
            falseAcceptRate: falseAcceptRate,
            falseRejectRate: falseRejectRate,
            perFieldConfusion: fieldConfusion,
            caseResults: caseResults
        )
    }

    public static func writeReport(
        _ report: VerifierShadowReport,
        to directoryURL: URL
    ) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let summaryData = try encoder.encode(report)
        try summaryData.write(to: directoryURL.appendingPathComponent("verifier-shadow-report.json"))

        let caseLines = try report.caseResults.map { item -> String in
            let data = try encoder.encode(item)
            return String(data: data, encoding: .utf8) ?? "{}"
        }.joined(separator: "\n")
        try caseLines.write(
            to: directoryURL.appendingPathComponent("verifier-shadow-cases.jsonl"),
            atomically: true,
            encoding: .utf8
        )
    }
}
