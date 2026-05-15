import Foundation
import HomeAutomationCore

public struct AutomationDraftAgentOutput: Sendable, Hashable {
    public let draft: AutomationDraftOutput
    public let retrievalReports: [KnowledgeRetrievalReport]

    public init(
        draft: AutomationDraftOutput,
        retrievalReports: [KnowledgeRetrievalReport] = []
    ) {
        self.draft = draft
        self.retrievalReports = retrievalReports
    }
}

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
        try await runWithDiagnostics(input, context: context).draft
    }

    public func runWithDiagnostics(
        _ input: AutomationDraftInput,
        context: ResolutionContext
    ) async throws -> AutomationDraftAgentOutput {
        let effectiveInput = input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AutomationDraftInput(text: context.request.text, operation: input.operation)
            : input
        let result = try await worker.createDraftWithDiagnostics(effectiveInput)
        return AutomationDraftAgentOutput(
            draft: result.output,
            retrievalReports: result.retrievalReports
        )
    }
}
