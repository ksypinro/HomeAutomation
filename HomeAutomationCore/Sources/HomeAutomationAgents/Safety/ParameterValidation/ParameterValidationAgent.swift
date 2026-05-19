import Foundation
import HomeAutomationCore

/// Mandatory fail-closed gate that checks parameter ranges and enum values.
public struct ParameterValidationAgent: HomeAgent {
    public typealias Input = ParameterValidationInput
    public typealias Output = Bool

    public let id = AgentID.parameterValidation
    public let capabilities: Set<AgentCapability> = [.parameterValidation]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let validate: @Sendable (ParameterValidationInput) async throws -> Bool

    public init(validate: @escaping @Sendable (ParameterValidationInput) async throws -> Bool) {
        self.validate = validate
    }

    public init() {
        self.validate = { input in
            HomeParameterValidator.validate(
                input.parameters,
                capability: input.capability,
                command: input.command,
                device: input.device
            )
        }
    }

    public func run(_ input: ParameterValidationInput, context: ResolutionContext) async throws -> Bool {
        try await validate(input)
    }
}
