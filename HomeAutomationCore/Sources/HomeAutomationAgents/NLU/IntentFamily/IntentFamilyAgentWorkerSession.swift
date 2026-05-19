import Foundation
import FoundationModels
import HomeAutomationCore
import os

public struct IntentFamilyAgentWorkerSession: Sendable {
    private let classify: (@Sendable (String) async throws -> HomeIntentFamilyResult)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let modelCallPolicy: NLUModelCallPolicy
    private let logger = Logger(subsystem: "HomeAutomation", category: "NLU.IntentFamilyAgent")

    public init(
        classify: (@Sendable (String) async throws -> HomeIntentFamilyResult)? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        modelCallPolicy: NLUModelCallPolicy = .default
    ) {
        self.classify = classify
        self.foundationModelAvailability = foundationModelAvailability
        self.modelCallPolicy = modelCallPolicy
    }

    public func classifyIntentFamily(_ text: String) async throws -> HomeIntentFamilyResult {
        logger.debug("[Input] text: \(text, privacy: .public)")
        if let classify {
            let result = try await classify(text)
            logger.debug("[MockOutput] result: \(String(describing: result), privacy: .public)")
            return result
        }
        let deterministicState = AgentTextParser.deterministicState(for: text)
        let fallback = deterministicState.intent
        logger.debug("[DeterministicFallback] result: \(String(describing: fallback), privacy: .public)")
        guard foundationModelAvailability() else {
            logger.info("[Availability] Foundation model unavailable, using fallback.")
            return fallback
        }

        let hintText: String
        if modelCallPolicy.shouldProvideHint(task: .intentFamily, deterministicState: deterministicState) {
            hintText = """
            
            Deterministic analysis suggests intent families: \(fallback.topFamilies), \
            confidence=\(fallback.confidence). Verify or correct this classification.
            """
            logger.info("[Hint] Providing deterministic hint to model (confidence: \(fallback.confidence, privacy: .public)).")
        } else {
            hintText = ""
        }

        let instructionsText = """
        Classify the command into broad smart-home intent families.
        Return the most likely families first. Do not choose a specific device.

        \(NLUInstructionContextProvider.intentFamilyContext(for: text))
        """
        logger.debug("[FoundationModelInput] System Instructions: \(instructionsText, privacy: .public)")
        logger.debug("[FoundationModelInput] Prompt: \(text, privacy: .public)")

        let session = LanguageModelSession(instructions: Instructions(instructionsText))
        do {
            let prompt = text + hintText
            let result = try await session.respond(to: Prompt(prompt), generating: HomeIntentFamilyResult.self).content
            logger.debug("[FoundationModelOutput] result: \(String(describing: result), privacy: .public)")
            return result
        } catch {
            logger.error("[FoundationModelError] error: \(error.localizedDescription, privacy: .public), using deterministic fallback.")
            return fallback
        }
    }
}
