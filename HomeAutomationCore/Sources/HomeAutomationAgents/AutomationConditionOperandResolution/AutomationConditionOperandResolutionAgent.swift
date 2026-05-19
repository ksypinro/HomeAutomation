import Foundation
import HomeAutomationCore

public struct AutomationConditionOperandResolutionAgent: HomeAgent {
    public typealias Input = HomeAutomationRuleDraft
    public typealias Output = AutomationConditionResolutionOutput

    public let id = AgentID.automationConditionOperandResolution
    public let capabilities: Set<AgentCapability> = [.automationConditionOperandResolution]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let resolveDraft: @Sendable (HomeAutomationRuleDraft) async -> AutomationConditionResolutionOutput

    public init(
        resolveDraft: @escaping @Sendable (HomeAutomationRuleDraft) async -> AutomationConditionResolutionOutput
    ) {
        self.resolveDraft = resolveDraft
    }

    public func run(
        _ input: HomeAutomationRuleDraft,
        context: ResolutionContext
    ) async throws -> AutomationConditionResolutionOutput {
        await resolveDraft(input)
    }
}
