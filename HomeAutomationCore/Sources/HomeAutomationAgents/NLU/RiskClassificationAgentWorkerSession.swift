import Foundation
import FoundationModels
import HomeAutomationCore

public struct RiskClassificationAgentWorkerSession: Sendable {
    private let classify: (@Sendable (String) async throws -> HomeRiskClassificationResult)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let modelCallPolicy: NLUModelCallPolicy

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
        if let classify {
            return try await classify(text)
        }
        let deterministicState = AgentTextParser.deterministicState(for: text)
        let fallback = deterministicState.risk
        guard foundationModelAvailability() else { return fallback }
        guard modelCallPolicy.shouldUseModel(task: .riskClassification, deterministicState: deterministicState) else { return fallback }

        let session = LanguageModelSession(instructions: Instructions("""
        Classify the risk level of this home-automation command.
        Unlocking, opening entry points, disabling cameras, starting ovens, or changing security state is high risk.
        Low risk includes lights, simple status queries, and harmless brightness changes.
        Temperature changes and appliances are medium risk.
        Critical risk includes security bypasses or unsafe automation.
        """))
        return try await session.respond(to: Prompt(text), generating: HomeRiskClassificationResult.self).content
    }
}
