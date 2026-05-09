import Foundation
import FoundationModels
import HomeAutomationCore
import os

public struct RiskClassificationAgentWorkerSession: Sendable {
    private let classify: (@Sendable (String) async throws -> HomeRiskClassificationResult)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let modelCallPolicy: NLUModelCallPolicy
    private let logger = Logger(subsystem: "HomeAutomation", category: "NLU.RiskClassificationAgent")

    public init(
        classify: (@Sendable (String) async throws -> HomeRiskClassificationResult)? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        modelCallPolicy: NLUModelCallPolicy = .default
    ) {
        self.classify = classify
        self.foundationModelAvailability = foundationModelAvailability
        self.modelCallPolicy = modelCallPolicy
    }

    public func classifyRisk(_ text: String) async throws -> HomeRiskClassificationResult {
        logger.debug("[Input] text: \(text, privacy: .public)")
        if let classify {
            let result = try await classify(text)
            logger.debug("[MockOutput] result: \(String(describing: result), privacy: .public)")
            return result
        }
        let deterministicState = AgentTextParser.deterministicState(for: text)
        let fallback = deterministicState.risk
        logger.debug("[DeterministicFallback] result: \(String(describing: fallback), privacy: .public)")
        guard foundationModelAvailability() else {
            logger.info("[Availability] Foundation model unavailable, using fallback.")
            return fallback
        }
        guard modelCallPolicy.shouldUseModel(task: .riskClassification, deterministicState: deterministicState) else {
            logger.info("[Policy] Deterministic confidence (\(fallback.confidence, privacy: .public)) >= threshold, skipping model.")
            return fallback
        }

        let instructionsText = """
        Classify the risk level of this home-automation command.
        Unlocking, opening entry points, disabling cameras, starting ovens, or changing security state is high risk.
        Low risk includes lights, simple status queries, and harmless brightness changes.
        Temperature changes and appliances are medium risk.
        Critical risk includes security bypasses or unsafe automation.
        """
        logger.debug("[FoundationModelInput] System Instructions: \(instructionsText, privacy: .public)")
        logger.debug("[FoundationModelInput] Prompt: \(text, privacy: .public)")

        let session = LanguageModelSession(instructions: Instructions(instructionsText))
        do {
            let result = try await session.respond(to: Prompt(text), generating: HomeRiskClassificationResult.self).content
            logger.debug("[FoundationModelOutput] result: \(String(describing: result), privacy: .public)")
            return result
        } catch {
            logger.error("[FoundationModelError] error: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
