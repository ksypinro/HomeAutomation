import Foundation
import HomeAutomationCore

/// Input types shared across Candidate agents.

/// Input for `CandidateRetrievalAgent` containing user text, NLU state,
/// retrieval limit, and optional conversation memory hints.
public struct CandidateRetrievalInput: Sendable {
    public let text: String
    public let state: HomeResolutionState
    public let limit: Int
    public let memoryHints: [MemoryHint]

    public init(
        text: String,
        state: HomeResolutionState,
        limit: Int = 80,
        memoryHints: [MemoryHint] = []
    ) {
        self.text = text
        self.state = state
        self.limit = limit
        self.memoryHints = memoryHints
    }
}

/// Input for `CandidateRankingAgent` with compact candidate views and memory hints.
public struct CandidateRankingInput: Sendable {
    public let text: String
    public let state: HomeResolutionState
    public let candidates: [HomeCompactCandidateView]
    public let memoryHints: [MemoryHint]

    public init(
        text: String,
        state: HomeResolutionState,
        candidates: [HomeCompactCandidateView],
        memoryHints: [MemoryHint] = []
    ) {
        self.text = text
        self.state = state
        self.candidates = candidates
        self.memoryHints = memoryHints
    }
}

/// Input for `CandidateShardAgent` containing one shard of candidates.
public struct CandidateShardInput: Sendable {
    public let text: String
    public let state: HomeResolutionState
    public let shard: [HomeCompactCandidateView]
    public let memoryHints: [MemoryHint]

    public init(
        text: String,
        state: HomeResolutionState,
        shard: [HomeCompactCandidateView],
        memoryHints: [MemoryHint] = []
    ) {
        self.text = text
        self.state = state
        self.shard = shard
        self.memoryHints = memoryHints
    }
}

/// Input for `CandidateHydrationAgent` with candidate IDs to hydrate into full records.
public struct CandidateHydrationInput: Sendable, Hashable {
    public let candidateIDs: [String]

    public init(candidateIDs: [String]) {
        self.candidateIDs = candidateIDs
    }
}
