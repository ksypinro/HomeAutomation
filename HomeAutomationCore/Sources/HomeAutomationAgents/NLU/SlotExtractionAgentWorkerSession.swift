import Foundation
import FoundationModels
import HomeAutomationCore

public struct SlotExtractionAgentWorkerSession: Sendable {
    private let extract: (@Sendable (String) async throws -> HomeSlotExtractionResult)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let modelCallPolicy: NLUModelCallPolicy

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
        if let extract {
            return try await extract(text)
        }
        let deterministicState = AgentTextParser.deterministicState(for: text)
        let fallback = deterministicState.slots
        guard foundationModelAvailability() else { return fallback }
        guard modelCallPolicy.shouldUseModel(task: .slotExtraction, deterministicState: deterministicState) else { return fallback }

        let session = LanguageModelSession(instructions: Instructions("""
        Extract rooms, device nicknames, values, units, durations, and modes from a smart-home command.
        Keep internal values in English even when the input is multilingual.
        Do not resolve devices or commands.
        Understand Bixby Home Studio slot language: device, deviceType, location, mode, predefinedMode, temperature,
        duration, number, compartment, and channel should be extracted when present.
        """))
		
        return try await session
			.respond(
				to: Prompt(text),
				generating: HomeSlotExtractionResult.self
			)
			.content
    }
}
