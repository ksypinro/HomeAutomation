import Foundation
import HomeAutomationCore
import os

/// Scores and ranks candidates, selects final IDs, or triggers clarification when ambiguous.
public struct CandidateRankingAgent: HomeAgent {
    public typealias Input = CandidateRankingInput
    public typealias Output = HomeCandidateAggregationResult

    public let id = AgentID.candidateRanking
    public let capabilities: Set<AgentCapability> = [.candidateRanking]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let rank: @Sendable (CandidateRankingInput) async throws -> HomeCandidateAggregationResult
    private let logger = Logger(subsystem: "HomeAutomation", category: "Agent.CandidateRanking")

    public init(rank: @escaping @Sendable (CandidateRankingInput) async throws -> HomeCandidateAggregationResult) {
        self.rank = rank
    }

    public init(resolver: HomeCandidateResolverSupport = HomeCandidateResolverSupport()) {
        self.rank = { input in
            try await resolver.resolveCandidates(
                userText: input.text,
                resolutionState: input.state,
                candidates: input.candidates,
                memoryHints: input.memoryHints
            )
        }
    }

    public func run(_ input: CandidateRankingInput, context: ResolutionContext) async throws -> HomeCandidateAggregationResult {
        logger.debug("[run] Executing CandidateRankingAgent with \(input.candidates.count) candidates")
        return try await rank(input)
    }
}
