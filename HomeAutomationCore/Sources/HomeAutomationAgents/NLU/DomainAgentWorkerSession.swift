import Foundation
import FoundationModels
import HomeAutomationCore
import os

public struct DomainAgentWorkerSession: Sendable {
    private let classify: (@Sendable (String) async throws -> HomeDomainClassificationResult)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let modelCallPolicy: NLUModelCallPolicy
    private let logger = Logger(subsystem: "HomeAutomation", category: "NLU.DomainAgent")

    public init(
        classify: (@Sendable (String) async throws -> HomeDomainClassificationResult)? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        modelCallPolicy: NLUModelCallPolicy = .default
    ) {
        self.classify = classify
        self.foundationModelAvailability = foundationModelAvailability
        self.modelCallPolicy = modelCallPolicy
    }

    public func classifyDomain(_ text: String) async throws -> HomeDomainClassificationResult {
        logger.debug("[Input] text: \(text, privacy: .public)")
        if let classify {
            let result = try await classify(text)
            logger.debug("[MockOutput] result: \(String(describing: result), privacy: .public)")
            return result
        }
        let deterministicState = AgentTextParser.deterministicState(for: text)
        let fallback = deterministicState.domain
        logger.debug("[DeterministicFallback] result: \(String(describing: fallback), privacy: .public)")
        guard foundationModelAvailability() else {
            logger.info("[Availability] Foundation model unavailable, using fallback.")
            return fallback
        }
        guard modelCallPolicy.shouldUseModel(task: .domain, deterministicState: deterministicState) else {
            logger.info("[Policy] Deterministic confidence (\(fallback.confidence, privacy: .public)) >= threshold, skipping model.")
            return fallback
        }

        let instructionsText = """
        Decide whether the text is a smart-home or home-automation command.
        Do not resolve devices. Classify only the domain.
        """
        logger.debug("[FoundationModelInput] System Instructions: \(instructionsText, privacy: .public)")
        logger.debug("[FoundationModelInput] Prompt: \(text, privacy: .public)")

        let session = LanguageModelSession(instructions: Instructions(instructionsText))
        do {
            let result = try await session.respond(to: Prompt(text), generating: HomeDomainClassificationResult.self).content
            logger.debug("[FoundationModelOutput] result: \(String(describing: result), privacy: .public)")
            return result
        } catch {
            logger.error("[FoundationModelError] error: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
