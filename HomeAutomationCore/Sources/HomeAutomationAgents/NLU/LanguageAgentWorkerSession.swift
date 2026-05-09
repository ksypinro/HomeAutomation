import Foundation
import FoundationModels
import HomeAutomationCore

public struct LanguageAgentWorkerSession: Sendable {
    private let detect: (@Sendable (String) async throws -> HomeLanguageDetectionResult)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let modelCallPolicy: NLUModelCallPolicy

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
        if let detect {
            return try await detect(text)
        }
        let deterministicState = AgentTextParser.deterministicState(for: text)
        let fallback = deterministicState.language
        guard foundationModelAvailability() else { return fallback }
        guard modelCallPolicy.shouldUseModel(task: .language, deterministicState: deterministicState) else { return fallback }

        let session = LanguageModelSession(instructions: Instructions("""
        Detect the language of this user command.
        Return compact structured output only.
        Use BCP-47-style language codes such as en, es, fr, ja, bn, or mixed_bn_en.
        """))
        return try await session.respond(to: Prompt(text), generating: HomeLanguageDetectionResult.self).content
    }
}
