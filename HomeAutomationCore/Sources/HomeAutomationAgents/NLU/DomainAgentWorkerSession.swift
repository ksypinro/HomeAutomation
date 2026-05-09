import Foundation
import FoundationModels
import HomeAutomationCore

public struct DomainAgentWorkerSession: Sendable {
    private let classify: (@Sendable (String) async throws -> HomeDomainClassificationResult)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let modelCallPolicy: NLUModelCallPolicy

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
        if let classify {
            return try await classify(text)
        }
        let deterministicState = AgentTextParser.deterministicState(for: text)
        let fallback = deterministicState.domain
        guard foundationModelAvailability() else { return fallback }
        guard modelCallPolicy.shouldUseModel(task: .domain, deterministicState: deterministicState) else { return fallback }

        let session = LanguageModelSession(instructions: Instructions("""
        Decide whether the text is a smart-home or home-automation command.
        Do not resolve devices. Classify only the domain.
        """))
        return try await session.respond(to: Prompt(text), generating: HomeDomainClassificationResult.self).content
    }
}
