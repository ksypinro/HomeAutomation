import Foundation
import HomeAutomationCore

public struct AutomationComponentSegmentationAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = AutomationComponentPlan

    public let id = AgentID.automationComponentSegmentation
    public let capabilities: Set<AgentCapability> = [.automationComponentSegmentation]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let worker: AutomationComponentSegmentationWorkerSession

    public init(worker: AutomationComponentSegmentationWorkerSession) {
        self.worker = worker
    }

    public func run(_ input: String, context: ResolutionContext) async throws -> AutomationComponentPlan {
        try await worker.segment(input)
    }
}
