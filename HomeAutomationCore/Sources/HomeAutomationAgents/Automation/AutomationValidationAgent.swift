import Foundation
import HomeAutomationCore

public struct AutomationValidationAgent: HomeAgent {
    public typealias Input = AutomationValidationInput
    public typealias Output = AutomationValidationResult

    public let id = AgentID.automationValidation
    public let capabilities: Set<AgentCapability> = [.automationValidation]
    public let timeoutNanoseconds: UInt64 = 2_000_000_000
    private let policy: AutomationValidationPolicy

    public init(policy: AutomationValidationPolicy = AutomationValidationPolicy()) {
        self.policy = policy
    }

    public func run(
        _ input: AutomationValidationInput,
        context: ResolutionContext
    ) async throws -> AutomationValidationResult {
        policy.validate(
            draft: input.ruleDraft,
            resolvedActions: input.resolvedActions
        )
    }
}
