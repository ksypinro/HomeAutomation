import Foundation
import HomeAutomationCore
import os

/// Produces the instruction package for Foundation Models draft generation.
public struct InstructionComposerAgent: HomeAgent {
    public typealias Input = HomeFinalResolutionInput
    public typealias Output = HomeModelInstructionPackage

    public let id = AgentID.instructionComposer
    public let capabilities: Set<AgentCapability> = [.instructionComposition]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let compose: @Sendable (HomeFinalResolutionInput) async throws -> HomeModelInstructionPackage
    private let logger = Logger(subsystem: "HomeAutomation", category: "Agent.InstructionComposer")

    public init(compose: @escaping @Sendable (HomeFinalResolutionInput) async throws -> HomeModelInstructionPackage) {
        self.compose = compose
    }

    public init(factory: AgentInstructionSetFactory) {
        self.compose = { input in await factory.makePackageWithRAG(from: input) }
    }

    public func run(_ input: HomeFinalResolutionInput, context: ResolutionContext) async throws -> HomeModelInstructionPackage {
        logger.debug("[run] Executing InstructionComposerAgent")
        return try await compose(input)
    }
}
