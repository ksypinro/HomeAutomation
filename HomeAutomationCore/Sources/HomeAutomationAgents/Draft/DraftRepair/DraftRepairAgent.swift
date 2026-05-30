import Foundation
import HomeAutomationCore
import os

/// Attempts draft repair or lower-confidence draft selection.
public struct DraftRepairAgent: HomeAgent {
    public typealias Input = HomeModelInstructionPackage
    public typealias Output = AgentDraftResolutionOutput

    public let id = AgentID.draftRepair
    public let capabilities: Set<AgentCapability> = [.draftRepair]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let repair: @Sendable (HomeModelInstructionPackage) async throws -> AgentDraftResolutionOutput
    private let logger = Logger(subsystem: "HomeAutomation", category: "Agent.DraftRepair")

    public init(repair: @escaping @Sendable (HomeModelInstructionPackage) async throws -> AgentDraftResolutionOutput) {
        self.repair = repair
    }

    public init(resolver: AgentDraftResolver) {
        self.repair = resolver.resolveDraftWithReport
    }

    public func run(_ input: HomeModelInstructionPackage, context: ResolutionContext) async throws -> AgentDraftResolutionOutput {
        logger.debug("[run] Executing DraftRepairAgent")
        return try await repair(input)
    }
}
