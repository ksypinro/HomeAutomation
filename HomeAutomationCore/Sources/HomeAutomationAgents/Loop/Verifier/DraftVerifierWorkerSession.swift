import Foundation
import FoundationModels
import HomeAutomationCore
import os

public struct DraftVerifierWorkerSession: Sendable {
    private let verify: (@Sendable (DraftEnvelope, VerifierPrompt) async throws -> DraftVerdict)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let softTimeoutNanoseconds: UInt64
    private let logger = Logger(subsystem: "HomeAutomation", category: "Loop.DraftVerifier")

    public init(
        verify: (@Sendable (DraftEnvelope, VerifierPrompt) async throws -> DraftVerdict)? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        softTimeoutNanoseconds: UInt64 = 8_000_000_000
    ) {
        self.verify = verify
        self.foundationModelAvailability = foundationModelAvailability
        self.softTimeoutNanoseconds = softTimeoutNanoseconds
    }

    public func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: Instructions(VerifierPromptBuilder.instructions))
    }

    public func verify(
        envelope: DraftEnvelope,
        prompt: VerifierPrompt,
        session: LanguageModelSession
    ) async throws -> DraftVerdict {
        logger.debug("[Input] userText: \(envelope.userText, privacy: .public), promptChars: \(prompt.characterCount)")

        if let verify {
            let result = try await verify(envelope, prompt)
            logger.debug("[MockOutput] accepted: \(result.accepted), disputes: \(result.disputes.count)")
            return constrain(result, envelope: envelope)
        }

        guard foundationModelAvailability() else {
            logger.info("[Availability] Foundation model unavailable, throwing VerifierUnavailable.")
            throw VerifierUnavailable()
        }

        let allowedFieldIDs = envelope.disputableFieldIDs().map(\.rawValue)

        let modelVerdict = try await withNLUModelSoftTimeout(
            agentID: .draftVerifier,
            timeoutNanoseconds: softTimeoutNanoseconds
        ) {
            try await FoundationModelCallRecorder.record(
                agentID: AgentID.draftVerifier.rawValue,
                policyMode: "verifier",
                modelAvailability: "available",
                promptCharacterCount: VerifierPromptBuilder.instructions.count + prompt.characterCount
            ) {
                let schema = try DraftVerdictSchema.schema(allowedFieldIDs: allowedFieldIDs)
                let response = try await session.respond(to: Prompt(prompt.text), schema: schema)
                return try DraftVerdictSchema.verdict(from: response.content)
            }
        }

        logger.debug("[FoundationModelOutput] accepted: \(modelVerdict.accepted), disputes: \(modelVerdict.disputes.count)")
        return constrain(modelVerdict, envelope: envelope)
    }

    private func constrain(_ verdict: DraftVerdict, envelope: DraftEnvelope) -> DraftVerdict {
        let allowedFieldIDs = Set(envelope.disputableFieldIDs().map(\.rawValue))
        let constrained = verdict.constrained(allowedFieldIDs: allowedFieldIDs)
        if constrained.disputes.count != verdict.disputes.count {
            logger.info("[Constraint] Dropped \(verdict.disputes.count - constrained.disputes.count) invalid dispute(s).")
        }
        return constrained
    }
}
