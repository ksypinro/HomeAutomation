import Foundation
import FoundationModels
import HomeAutomationCore
import os

public struct LanguageAgentWorkerSession: Sendable {
    private let detect: (@Sendable (String) async throws -> HomeLanguageDetectionResult)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let modelCallPolicy: NLUModelCallPolicy
    private let logger = Logger(subsystem: "HomeAutomation", category: "NLU.LanguageAgent")

    public init(
        detect: (@Sendable (String) async throws -> HomeLanguageDetectionResult)? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        modelCallPolicy: NLUModelCallPolicy = .default
    ) {
        self.detect = detect
        self.foundationModelAvailability = foundationModelAvailability
        self.modelCallPolicy = modelCallPolicy
    }

    public func detectLanguage(_ text: String) async throws -> HomeLanguageDetectionResult {
        logger.debug("[Input] text: \(text, privacy: .public)")
        if let detect {
            let result = try await detect(text)
            logger.debug("[MockOutput] result: \(String(describing: result), privacy: .public)")
            return result
        }
        let deterministicState = AgentTextParser.deterministicState(for: text)
        let fallback = deterministicState.language
        logger.debug("[DeterministicFallback] result: \(String(describing: fallback), privacy: .public)")
        guard foundationModelAvailability() else {
            logger.info("[Availability] Foundation model unavailable, using fallback.")
            return fallback
        }

        let hintText: String
        if modelCallPolicy.shouldProvideHint(task: .language, deterministicState: deterministicState) {
            hintText = """
            
            Deterministic analysis suggests: languageCode=\(fallback.languageCode), \
            isMixedLanguage=\(fallback.isMixedLanguage), confidence=\(fallback.confidence). \
            Verify or correct this classification.
            """
            logger.info("[Hint] Providing deterministic hint to model (confidence: \(fallback.confidence, privacy: .public)).")
        } else {
            hintText = ""
        }

        let instructionsText = """
        Detect the language of this user command.
        Return compact structured output only.
        Use BCP-47-style language codes such as en, es, fr, ja, bn, or mixed_bn_en.
        """
        logger.debug("[FoundationModelInput] System Instructions: \(instructionsText, privacy: .public)")
        logger.debug("[FoundationModelInput] Prompt: \(text, privacy: .public)")
        
        let session = LanguageModelSession(instructions: Instructions(instructionsText))
        do {
            let prompt = text + hintText
            let result = try await session.respond(to: Prompt(prompt), generating: HomeLanguageDetectionResult.self).content
            logger.debug("[FoundationModelOutput] result: \(String(describing: result), privacy: .public)")
            return result
        } catch {
            logger.error("[FoundationModelError] error: \(error.localizedDescription, privacy: .public), using deterministic fallback.")
            return fallback
        }
    }
}
