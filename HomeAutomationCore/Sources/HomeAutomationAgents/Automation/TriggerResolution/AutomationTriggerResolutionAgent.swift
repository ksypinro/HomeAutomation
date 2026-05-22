import Foundation
import HomeAutomationCore

public struct AutomationTriggerResolutionAgent: HomeAgent {
    public typealias Input = AutomationTriggerResolutionInput
    public typealias Output = AutomationTriggerResolutionOutput

    public let id = AgentID.automationTriggerResolution
    public let capabilities: Set<AgentCapability> = [.automationTriggerResolution]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let worker: AutomationTriggerResolutionWorkerSession

    public init(worker: AutomationTriggerResolutionWorkerSession = AutomationTriggerResolutionWorkerSession()) {
        self.worker = worker
    }

    public func run(
        _ input: AutomationTriggerResolutionInput,
        context: ResolutionContext
    ) async throws -> AutomationTriggerResolutionOutput {
        try await worker.resolve(input)
    }
}
