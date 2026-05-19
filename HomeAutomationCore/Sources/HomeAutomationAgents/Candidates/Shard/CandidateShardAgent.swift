import Foundation
import HomeAutomationCore
import os

/// Selects candidates within a single shard for large candidate lists (>20 devices).
public struct CandidateShardAgent: HomeAgent {
    public typealias Input = CandidateShardInput
    public typealias Output = HomeCandidateShardSelection

    public let id = AgentID.candidateShard
    public let capabilities: Set<AgentCapability> = [.candidateSharding]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let shard: @Sendable (CandidateShardInput) async throws -> HomeCandidateShardSelection
    private let logger = Logger(subsystem: "HomeAutomation", category: "Agent.CandidateShard")

    public init(shard: @escaping @Sendable (CandidateShardInput) async throws -> HomeCandidateShardSelection) {
        self.shard = shard
    }

    public init(resolver: HomeCandidateResolverSupport = HomeCandidateResolverSupport()) {
        self.shard = { input in
            try await resolver.resolveShard(
                userText: input.text,
                resolutionState: input.state,
                shard: input.shard,
                memoryHints: input.memoryHints
            )
        }
    }

    public func run(_ input: CandidateShardInput, context: ResolutionContext) async throws -> HomeCandidateShardSelection {
        logger.debug("[run] Executing CandidateShardAgent with shard size \(input.shard.count)")
        return try await shard(input)
    }
}
