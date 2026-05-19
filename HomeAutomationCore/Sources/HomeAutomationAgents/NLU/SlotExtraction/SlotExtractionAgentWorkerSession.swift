import Foundation
import FoundationModels
import HomeAutomationCore
import os

public struct SlotExtractionAgentWorkerSession: Sendable {
    private let extract: (@Sendable (String) async throws -> HomeSlotExtractionResult)?
    private let modelExtract: (@Sendable (String) async throws -> HomeSlotExtractionResult)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let modelCallPolicy: NLUModelCallPolicy
    private let logger = Logger(subsystem: "HomeAutomation", category: "NLU.SlotExtractionAgent")

    public init(
        extract: (@Sendable (String) async throws -> HomeSlotExtractionResult)? = nil,
        modelExtract: (@Sendable (String) async throws -> HomeSlotExtractionResult)? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        modelCallPolicy: NLUModelCallPolicy = .default
    ) {
        self.extract = extract
        self.modelExtract = modelExtract
        self.foundationModelAvailability = foundationModelAvailability
        self.modelCallPolicy = modelCallPolicy
    }

    public func extractSlots(_ text: String) async throws -> HomeSlotExtractionResult {
        try await extractSlots(text, modelPrompt: text)
    }

    public func extractSlots(_ text: String, modelPrompt: String) async throws -> HomeSlotExtractionResult {
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

        let hintText: String
        if modelCallPolicy.shouldProvideHint(task: .slotExtraction, deterministicState: deterministicState) {
            hintText = """

            Deterministic slot extraction suggests:
            - rooms: \(fallback.rooms)
            - deviceNicknames: \(fallback.deviceNicknames)
            - values: \(fallback.values.map { "\($0.name)=\($0.rawValue)" })
            - modes: \(fallback.modes)
            - confidence: \(fallback.confidence)
            Verify and correct these extractions. Add any slots the deterministic analysis missed.
            """
            logger.info("[Hint] Providing deterministic slot hint to model (confidence: \(fallback.confidence, privacy: .public)).")
        } else {
            hintText = ""
        }

        let instructionsText = """
        Extract rooms, device nicknames, values, units, durations, and modes from a smart-home command.
        Keep internal values in English even when the input is multilingual.
        Do not resolve devices or commands.
        If the prompt includes examples, use them only as context. Extract slots only from the text after "User command:".
        Understand Bixby Home Studio slot language: device, deviceType, location, mode, predefinedMode, temperature,
        duration, number, compartment, and channel should be extracted when present.
        """
        logger.debug("[FoundationModelInput] System Instructions: \(instructionsText, privacy: .public)")
        logger.debug("[FoundationModelInput] Prompt: \(modelPrompt, privacy: .public)")

        do {
            let result: HomeSlotExtractionResult
            if let modelExtract {
                result = try await modelExtract(modelPrompt + hintText)
            } else {
                let session = LanguageModelSession(instructions: Instructions(instructionsText))
                result = try await session
                    .respond(
                        to: Prompt(modelPrompt + hintText),
                        generating: HomeSlotExtractionResult.self
                    )
                    .content
            }
            logger.debug("[FoundationModelOutput] result: \(String(describing: result), privacy: .public)")

            // Post-model validation: if deterministic had high-confidence slots, cross-validate
            let needsConfirmation = Self.needsModelConfirmation(fallback)
            if needsConfirmation {
                let confirmed = Self.confirmedFallback(fallback, with: result)
                logger.debug("[PostValidation] Confirmed result after cross-validation: \(String(describing: confirmed), privacy: .public)")
                return confirmed
            }
            return result
        } catch {
            logger.error("[FoundationModelError] error: \(error.localizedDescription, privacy: .public), using deterministic fallback.")
            return fallback
        }
    }

    private static func needsModelConfirmation(_ result: HomeSlotExtractionResult) -> Bool {
        result.rooms.count > 1 ||
            result.deviceNicknames.count > 1 ||
            result.modes.count > 1 ||
            result.values.count > 1
    }

    private static func confirmedFallback(
        _ fallback: HomeSlotExtractionResult,
        with model: HomeSlotExtractionResult,
        confidenceThreshold: Double = 0.55
    ) -> HomeSlotExtractionResult {
        guard model.confidence >= confidenceThreshold else {
            return fallback
        }

        let rooms = confirmedStrings(fallback.rooms, by: model.rooms)
        let deviceNicknames = confirmedStrings(fallback.deviceNicknames, by: model.deviceNicknames)
        let modes = confirmedStrings(fallback.modes, by: model.modes)
        let values = confirmedValues(fallback.values, by: model.values)

        return HomeSlotExtractionResult(
            rooms: rooms,
            deviceNicknames: deviceNicknames,
            values: values,
            modes: modes,
            confidence: min(fallback.confidence, model.confidence)
        )
    }

    private static func confirmedStrings(_ fallback: [String], by model: [String]) -> [String] {
        guard !fallback.isEmpty else { return model }
        let modelSet = Set(model.map(\.agentNormalizedHomeTokenString))
        guard !modelSet.isEmpty else { return [] }
        return fallback.filter { modelSet.contains($0.agentNormalizedHomeTokenString) }
    }

    private static func confirmedValues(
        _ fallback: [HomeExtractedSlot],
        by model: [HomeExtractedSlot]
    ) -> [HomeExtractedSlot] {
        guard !fallback.isEmpty else { return model }
        guard !model.isEmpty else { return [] }
        return fallback.filter { candidate in
            model.contains { confirmedValue(candidate, matches: $0) }
        }
    }

    private static func confirmedValue(_ lhs: HomeExtractedSlot, matches rhs: HomeExtractedSlot) -> Bool {
        if let lhsNumber = lhs.numericValue, let rhsNumber = rhs.numericValue, lhsNumber == rhsNumber {
            return true
        }
        return lhs.name.agentNormalizedHomeTokenString == rhs.name.agentNormalizedHomeTokenString &&
            lhs.rawValue.agentNormalizedHomeTokenString == rhs.rawValue.agentNormalizedHomeTokenString
    }
}
