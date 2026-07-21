import Foundation
import HomeAutomationCore

public struct AutomationActionResolutionAgent: HomeAgent {
    public typealias Input = [String]
    public typealias Output = AutomationActionResolutionAggregate

    public let id = AgentID.automationActionResolution
    public let capabilities: Set<AgentCapability> = [.automationActionResolution]
    public let timeoutNanoseconds: UInt64 = 240_000_000_000
    private let resolveActions: @Sendable ([String], AgentEventBus, UUID, AutomationActionResolutionStrategy?) async -> [AutomationActionResolutionResult]

    public init(
        resolveActions: @escaping @Sendable ([String], AgentEventBus, UUID, AutomationActionResolutionStrategy?) async -> [AutomationActionResolutionResult]
    ) {
        self.resolveActions = resolveActions
    }

    public func run(
        _ input: [String],
        context: ResolutionContext
    ) async throws -> AutomationActionResolutionAggregate {
        let bridge = context.scopedValue(for: AutomationRuntimeContextKeys.pipelineEventBridge)
        let strategy = context.scopedValue(for: AutomationRuntimeContextKeys.actionResolutionStrategy)
        let results = await resolveActions(
            input,
            bridge?.eventBus ?? AgentEventBus(),
            bridge?.runID ?? UUID(),
            strategy
        )
        return AutomationActionResolutionAggregate(
            actionDescriptions: input,
            results: results
        )
    }
}
