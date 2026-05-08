import Foundation
import HomeAutomationCore

/// Converts validated drafts into execution plans.
public struct ExecutionPlanningAgent: HomeAgent {
    public typealias Input = ExecutionPlanningInput
    public typealias Output = HomeAutomationExecutionPlan

    public let id = AgentID.executionPlanning
    public let capabilities: Set<AgentCapability> = [.executionPlanning]
    public let timeoutNanoseconds: UInt64 = 5_000_000_000
    private let plan: @Sendable (ExecutionPlanningInput) async throws -> HomeAutomationExecutionPlan

    public init(plan: @escaping @Sendable (ExecutionPlanningInput) async throws -> HomeAutomationExecutionPlan) {
        self.plan = plan
    }

    public init() {
        self.plan = { input in
            AgentExecutionPlanner.plan(from: input.draft, device: input.device)
        }
    }

    public func run(_ input: ExecutionPlanningInput, context: ResolutionContext) async throws -> HomeAutomationExecutionPlan {
        try await plan(input)
    }
}
