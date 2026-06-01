import Foundation
import HomeAutomationCore

public struct AutomationConditionClauseResolutionAgent: HomeAgent {
    public typealias Input = AutomationConditionClauseResolutionInput
    public typealias Output = AutomationConditionClauseResolutionResult

    public let id = AgentID.automationConditionClauseResolution
    public let capabilities: Set<AgentCapability> = [.automationConditionClauseResolution]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let worker: AutomationConditionClauseResolutionWorkerSession

    public init(worker: AutomationConditionClauseResolutionWorkerSession) {
        self.worker = worker
    }

    public func run(
        _ input: AutomationConditionClauseResolutionInput,
        context: ResolutionContext
    ) async throws -> AutomationConditionClauseResolutionResult {
        try await worker.resolve(input)
    }
}
