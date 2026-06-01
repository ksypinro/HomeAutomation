import Foundation
import HomeAutomationCore
import os

/// Produces the primary `HomeCommandDraft` via Foundation Models.
public struct DraftGenerationAgent: HomeAgent {
    public typealias Input = HomeModelInstructionPackage
    public typealias Output = HomeCommandDraft

    public let id = AgentID.draftGeneration
    public let capabilities: Set<AgentCapability> = [.draftGeneration]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let generate: @Sendable (HomeModelInstructionPackage) async throws -> HomeCommandDraft
    private let logger = Logger(subsystem: "HomeAutomation", category: "Agent.DraftGeneration")

    public init(generate: @escaping @Sendable (HomeModelInstructionPackage) async throws -> HomeCommandDraft) {
        self.generate = generate
    }

    public init(resolver: AgentDraftResolver) {
        self.generate = resolver.resolveDraft
    }

    public func run(_ input: HomeModelInstructionPackage, context: ResolutionContext) async throws -> HomeCommandDraft {
        logger.debug("[run] Executing DraftGenerationAgent")
        return try await generate(input)
    }
}
