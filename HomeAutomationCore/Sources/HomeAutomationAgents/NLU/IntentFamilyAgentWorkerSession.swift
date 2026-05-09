import Foundation
import FoundationModels
import HomeAutomationCore

public struct IntentFamilyAgentWorkerSession: Sendable {
    private let classify: (@Sendable (String) async throws -> HomeIntentFamilyResult)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let modelCallPolicy: NLUModelCallPolicy

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
        if let classify {
            return try await classify(text)
        }
        let deterministicState = AgentTextParser.deterministicState(for: text)
        let fallback = deterministicState.intent
        guard foundationModelAvailability() else { return fallback }
        guard modelCallPolicy.shouldUseModel(task: .intentFamily, deterministicState: deterministicState) else { return fallback }

        let session = LanguageModelSession(instructions: Instructions("""
        Classify the command into broad smart-home intent families.
        Return the most likely families first. Do not choose a specific device.

        \(NLUInstructionContextProvider.intentFamilyContext(for: text))
        """))
        return try await session.respond(to: Prompt(text), generating: HomeIntentFamilyResult.self).content
    }
}
