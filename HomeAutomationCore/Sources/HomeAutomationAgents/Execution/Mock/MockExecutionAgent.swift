import Foundation
import HomeAutomationCore

/// Executes low-risk command steps against the configured device registry.
/// This is the only agent permitted to mutate device state.
public struct MockExecutionAgent: HomeAgent {
    public typealias Input = HomeAutomationExecutionPlan
    public typealias Output = HomeCandidateRecord

    public let id = AgentID.mockExecution
    public let capabilities: Set<AgentCapability> = [.execution]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let execute: @Sendable (HomeAutomationExecutionPlan) async throws -> HomeCandidateRecord

    public init(execute: @escaping @Sendable (HomeAutomationExecutionPlan) async throws -> HomeCandidateRecord) {
        self.execute = execute
    }

    public init(registry: any DeviceRegistryProtocol = MockHomeDeviceRegistry()) {
        let executor = AgentPlanExecutor(registry: registry)
        self.execute = executor.executeLowRiskPlan
    }

    public func run(_ input: HomeAutomationExecutionPlan, context: ResolutionContext) async throws -> HomeCandidateRecord {
        try await execute(input)
    }
}
