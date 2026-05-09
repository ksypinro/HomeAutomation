import Foundation
import FoundationModels
import HomeAutomationCore
import os

public struct SlotExtractionAgentWorkerSession: Sendable {
    private let extract: (@Sendable (String) async throws -> HomeSlotExtractionResult)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let modelCallPolicy: NLUModelCallPolicy
    private let logger = Logger(subsystem: "HomeAutomation", category: "NLU.SlotExtractionAgent")

    public init(
        extract: (@Sendable (String) async throws -> HomeSlotExtractionResult)? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        modelCallPolicy: NLUModelCallPolicy = .default
    ) {
        self.extract = extract
        self.foundationModelAvailability = foundationModelAvailability
        self.modelCallPolicy = modelCallPolicy
    }

    public func extractSlots(_ text: String) async throws -> HomeSlotExtractionResult {
        logger.debug("[Input] text: \(text, privacy: .public)")
        if let extract {
            let result = try await extract(text)
            logger.debug("[MockOutput] result: \(String(describing: result), privacy: .public)")
            return result
        }
        let deterministicState = AgentTextParser.deterministicState(for: text)
        let fallback = deterministicState.slots
        logger.debug("[DeterministicFallback] result: \(String(describing: fallback), privacy: .public)")
        guard foundationModelAvailability() else {
            logger.info("[Availability] Foundation model unavailable, using fallback.")
            return fallback
        }
        guard modelCallPolicy.shouldUseModel(task: .slotExtraction, deterministicState: deterministicState) else {
            logger.info("[Policy] Deterministic confidence (\(fallback.confidence, privacy: .public)) >= threshold, skipping model.")
            return fallback
        }

        let instructionsText = """
        Extract rooms, device nicknames, values, units, durations, and modes from a smart-home command.
        Keep internal values in English even when the input is multilingual.
        Do not resolve devices or commands.
        Understand Bixby Home Studio slot language: device, deviceType, location, mode, predefinedMode, temperature,
        duration, number, compartment, and channel should be extracted when present.
        """
        logger.debug("[FoundationModelInput] System Instructions: \(instructionsText, privacy: .public)")
        logger.debug("[FoundationModelInput] Prompt: \(text, privacy: .public)")

        let session = LanguageModelSession(instructions: Instructions(instructionsText))
        do {
            let result = try await session
                .respond(
                    to: Prompt(text),
                    generating: HomeSlotExtractionResult.self
                )
                .content
            logger.debug("[FoundationModelOutput] result: \(String(describing: result), privacy: .public)")
            return result
        } catch {
            logger.error("[FoundationModelError] error: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
