import Foundation
import HomeAutomationCore

/// Attempts draft repair or lower-confidence draft selection.
public struct DraftRepairAgent: HomeAgent {
    public typealias Input = HomeModelInstructionPackage
    public typealias Output = AgentDraftResolutionOutput

    public let id = AgentID.draftRepair
    public let capabilities: Set<AgentCapability> = [.draftRepair]
    public let timeoutNanoseconds: UInt64 = 25_000_000_000
    private let repair: @Sendable (HomeModelInstructionPackage) async throws -> AgentDraftResolutionOutput

    public init(repair: @escaping @Sendable (HomeModelInstructionPackage) async throws -> AgentDraftResolutionOutput) {
        self.repair = repair
    }

    public init(resolver: AgentDraftResolver = AgentDraftResolver()) {
        self.repair = resolver.resolveDraftWithReport
    }

    public func run(_ input: HomeModelInstructionPackage, context: ResolutionContext) async throws -> AgentDraftResolutionOutput {
        try await repair(input)
    }
}
