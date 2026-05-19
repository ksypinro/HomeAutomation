import Foundation
import HomeAutomationCore

public struct AutomationActionResolutionAgent: HomeAgent {
    public typealias Input = [String]
    public typealias Output = AutomationActionResolutionAggregate

    public let id = AgentID.automationActionResolution
    public let capabilities: Set<AgentCapability> = [.automationActionResolution]
    public let timeoutNanoseconds: UInt64 = 240_000_000_000
    private let resolveActions: @Sendable ([String], AgentEventBus, UUID) async -> [AutomationActionResolutionResult]

    public init(
        resolveActions: @escaping @Sendable ([String], AgentEventBus, UUID) async -> [AutomationActionResolutionResult]
    ) {
        self.resolveActions = resolveActions
    }

    public func run(
        _ input: [String],
        context: ResolutionContext
    ) async throws -> AutomationActionResolutionAggregate {
        let bridge = context.scopedValue(for: AutomationRuntimeContextKeys.pipelineEventBridge)
        let results = await resolveActions(
            input,
            bridge?.eventBus ?? AgentEventBus(),
            bridge?.runID ?? UUID()
        )
        return AutomationActionResolutionAggregate(
            actionDescriptions: input,
            results: results
        )
    }
}
