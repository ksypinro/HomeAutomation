import Foundation
import HomeAutomationCore

public struct AutomationComponentFanOutAgent: HomeAgent {
    public typealias Input = AutomationComponentPlan
    public typealias Output = AutomationResolvedComponentSet

    public let id = AgentID.automationComponentFanOut
    public let capabilities: Set<AgentCapability> = [.automationComponentFanOut]
    public let timeoutNanoseconds: UInt64 = 300_000_000_000
    private let resolveComponents: @Sendable (AutomationComponentPlan, ResolutionContext) async -> AutomationResolvedComponentSet

    public init(
        resolveComponents: @escaping @Sendable (AutomationComponentPlan, ResolutionContext) async -> AutomationResolvedComponentSet
    ) {
        self.resolveComponents = resolveComponents
    }

    public func run(
        _ input: AutomationComponentPlan,
        context: ResolutionContext
    ) async throws -> AutomationResolvedComponentSet {
        await resolveComponents(input, context)
    }
}
