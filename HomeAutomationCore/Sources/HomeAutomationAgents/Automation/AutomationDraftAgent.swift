import Foundation
import HomeAutomationCore

public struct AutomationDraftAgent: HomeAgent {
    public typealias Input = AutomationDraftInput
    public typealias Output = AutomationDraftOutput

    public let id = AgentID.automationDraft
    public let capabilities: Set<AgentCapability> = [.automationDrafting]
    public let timeoutNanoseconds: UInt64 = 10_000_000_000
    private let worker: AutomationDraftWorkerSession

    public init(
        worker: AutomationDraftWorkerSession = AutomationDraftWorkerSession()
    ) {
        self.worker = worker
    }

    public func run(
        _ input: AutomationDraftInput,
        context: ResolutionContext
    ) async throws -> AutomationDraftOutput {
        let effectiveInput = input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AutomationDraftInput(text: context.request.text, operation: input.operation)
            : input
        return try await worker.createDraft(effectiveInput)
    }
}
