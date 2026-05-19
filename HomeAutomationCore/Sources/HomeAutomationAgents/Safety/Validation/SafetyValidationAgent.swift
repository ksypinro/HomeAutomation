import Foundation
import HomeAutomationCore

/// Mandatory fail-closed gate that validates the draft against the hydrated candidate set.
public struct SafetyValidationAgent: HomeAgent {
    public typealias Input = SafetyValidationInput
    public typealias Output = HomeCommandResolution

    public let id = AgentID.safetyValidation
    public let capabilities: Set<AgentCapability> = [.safetyValidation]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let validate: @Sendable (SafetyValidationInput) async throws -> HomeCommandResolution

    public init(validate: @escaping @Sendable (SafetyValidationInput) async throws -> HomeCommandResolution) {
        self.validate = validate
    }

    public init(validator: AgentCommandValidator = AgentCommandValidator()) {
        self.validate = { input in
            validator.validate(input.draft, input: input.finalInput)
        }
    }

    public func run(_ input: SafetyValidationInput, context: ResolutionContext) async throws -> HomeCommandResolution {
        try await validate(input)
    }
}
