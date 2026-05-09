import Foundation
import FoundationModels
import HomeAutomationCore

public struct DeviceTypeAgentWorkerSession: Sendable {
    private let classify: (@Sendable (String) async throws -> HomeDeviceTypeResult)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let modelCallPolicy: NLUModelCallPolicy

    public init(
        classify: (@Sendable (String) async throws -> HomeDeviceTypeResult)? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        modelCallPolicy: NLUModelCallPolicy = .default
    ) {
        self.classify = classify
        self.foundationModelAvailability = foundationModelAvailability
        self.modelCallPolicy = modelCallPolicy
    }

    public func classifyDeviceType(_ text: String) async throws -> HomeDeviceTypeResult {
        if let classify {
            return try await classify(text)
        }
        let deterministicState = AgentTextParser.deterministicState(for: text)
        let fallback = deterministicState.deviceType
        guard foundationModelAvailability() else { return fallback }
        guard modelCallPolicy.shouldUseModel(task: .deviceType, deterministicState: deterministicState) else { return fallback }

        let session = LanguageModelSession(instructions: Instructions("""
        Extract likely smart-home device types mentioned by the user.
        \(NLUInstructionContextProvider.deviceTypeContext(for: text))
        """))
        return try await session.respond(to: Prompt(text), generating: HomeDeviceTypeResult.self).content
    }
}
