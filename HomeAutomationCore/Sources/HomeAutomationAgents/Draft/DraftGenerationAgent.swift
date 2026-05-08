import Foundation
import HomeAutomationCore

/// Produces the primary `HomeCommandDraft` via Foundation Models.
public struct DraftGenerationAgent: HomeAgent {
    public typealias Input = HomeModelInstructionPackage
    public typealias Output = HomeCommandDraft

    public let id = AgentID.draftGeneration
    public let capabilities: Set<AgentCapability> = [.draftGeneration]
    public let timeoutNanoseconds: UInt64 = 20_000_000_000
    private let generate: @Sendable (HomeModelInstructionPackage) async throws -> HomeCommandDraft

    public init(generate: @escaping @Sendable (HomeModelInstructionPackage) async throws -> HomeCommandDraft) {
        self.generate = generate
    }

    public init(resolver: AgentDraftResolver = AgentDraftResolver()) {
        self.generate = resolver.resolveDraft
    }

    public func run(_ input: HomeModelInstructionPackage, context: ResolutionContext) async throws -> HomeCommandDraft {
        try await generate(input)
    }
}
