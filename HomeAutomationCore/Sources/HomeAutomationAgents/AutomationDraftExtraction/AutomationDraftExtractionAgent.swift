import Foundation
import HomeAutomationCore

public struct AutomationDraftExtractionAgent: HomeAgent {
    public typealias Input = AutomationDraftInput
    public typealias Output = AutomationDraftExtractionOutput

    public let id = AgentID.automationDraft
    public let capabilities: Set<AgentCapability> = [.automationDrafting]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let draftAgent: AutomationDraftAgent

    public init(draftAgent: AutomationDraftAgent) {
        self.draftAgent = draftAgent
    }

    public func run(
        _ input: AutomationDraftInput,
        context: ResolutionContext
    ) async throws -> AutomationDraftExtractionOutput {
        let output = try await draftAgent.runWithDiagnostics(input, context: context)
        return try AutomationDraftExtractionOutput(
            ruleDraft: output.draft.makeRuleDraft(),
            retrievalReports: output.retrievalReports
        )
    }
}
