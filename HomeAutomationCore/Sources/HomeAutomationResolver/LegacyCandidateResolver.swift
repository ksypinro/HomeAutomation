import Foundation
import FoundationModels
import HomeAutomationCore

public actor LegacyCandidateResolverMetrics {
    public private(set) var lastStrategy = "none"
    public private(set) var lastCandidateCount = 0

    public init() {}

    func record(strategy: String, candidateCount: Int) {
        lastStrategy = strategy
        lastCandidateCount = candidateCount
    }
}

public struct LegacyCandidateResolver: HomeCandidateResolving {
    private let shardSize: Int
    private let metrics: LegacyCandidateResolverMetrics?

    public init(
        shardSize: Int = 20,
        metrics: LegacyCandidateResolverMetrics? = nil
    ) {
        self.shardSize = shardSize
        self.metrics = metrics
    }

    public func resolveCandidates(
        userText: String,
        resolutionState: HomeResolutionState,
        candidates: [HomeCompactCandidateView]
    ) async throws -> HomeCandidateAggregationResult {
        guard !candidates.isEmpty else {
            await metrics?.record(strategy: "empty", candidateCount: 0)
            return HomeCandidateAggregationResult(
                finalCandidateIDs: [],
                needsClarification: true,
                clarificationQuestion: "Which device do you want to control?",
                confidence: 0
            )
        }

        if candidates.count <= shardSize {
            await metrics?.record(strategy: "direct", candidateCount: candidates.count)
            return try await resolveDirectly(
                userText: userText,
                resolutionState: resolutionState,
                candidates: candidates
            )
        }

        await metrics?.record(strategy: "sharded", candidateCount: candidates.count)
        let shards = shardHomeCandidates(candidates, shardSize: shardSize)
        let selections = try await withThrowingTaskGroup(of: HomeCandidateShardSelection.self) { group in
            for shard in shards {
                group.addTask {
                    try await resolveShard(
                        userText: userText,
                        resolutionState: resolutionState,
                        shard: shard
                    )
                }
            }

            var results: [HomeCandidateShardSelection] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        return try await aggregate(
            userText: userText,
            shardSelections: selections
        )
    }

    private func resolveDirectly(
        userText: String,
        resolutionState: HomeResolutionState,
        candidates: [HomeCompactCandidateView]
    ) async throws -> HomeCandidateAggregationResult {
        if let deterministic = deterministicAggregation(
            userText: userText,
            resolutionState: resolutionState,
            candidates: candidates
        ) {
            return deterministic
        }

        let session = LanguageModelSession(instructions: Instructions("""
        Select the best candidate IDs for the user's smart-home command.
        Use only the provided candidate IDs.
        If no candidate matches, return an empty finalCandidateIDs list and ask a clarification question.
        If multiple candidates are equally plausible, set needsClarification true.
        """))

        let prompt = """
        User command: \(userText)

        Resolution hints:
        - Intent families: \(resolutionState.intent.topFamilies)
        - Device types: \(resolutionState.deviceType.deviceTypes)
        - Rooms: \(resolutionState.slots.rooms)
        - Device nicknames: \(resolutionState.slots.deviceNicknames)
        - Values: \(resolutionState.slots.values)

        Candidates:
        \(candidates.map(\.description).joined(separator: "\n"))
        """

        let response = try await session.respond(
            to: Prompt(prompt),
            generating: HomeCandidateAggregationResult.self
        )
        return response.content
    }

    private func deterministicAggregation(
        userText: String,
        resolutionState: HomeResolutionState,
        candidates: [HomeCompactCandidateView]
    ) -> HomeCandidateAggregationResult? {
        let normalized = userText.legacyNormalizedHomeTokenString
        let rooms = Set(resolutionState.slots.rooms.map(\.legacyNormalizedHomeTokenString))
        let types = Set(resolutionState.deviceType.deviceTypes.map(\.legacyNormalizedHomeTokenString))

        let scored = candidates.map { candidate in
            var score = 0
            let label = candidate.label.legacyNormalizedHomeTokenString
            let type = candidate.deviceType.legacyNormalizedHomeTokenString
            let room = candidate.room?.legacyNormalizedHomeTokenString

            if normalized.contains(label) { score += 20 }
            if normalized.contains(type) || types.contains(type) { score += 8 }
            if let room, normalized.contains(room) || rooms.contains(room) { score += 8 }

            let overlap = normalized.legacyTokenSet.intersection(label.legacyTokenSet).count
            score += min(overlap * 2, 8)

            if resolutionState.intent.topFamilies.contains(.power),
               candidate.shortCapabilities.contains("switch") {
                score += 4
            }
            if resolutionState.intent.topFamilies.contains(.brightness),
               candidate.shortCapabilities.contains("switchLevel") {
                score += 4
            }
            if resolutionState.intent.topFamilies.contains(.lockUnlock),
               candidate.shortCapabilities.contains("lock") {
                score += 6
            }
            if resolutionState.intent.topFamilies.contains(.routine),
               candidate.shortCapabilities.contains("routine") {
                score += 8
            }

            return (candidate: candidate, score: score)
        }
        .filter { $0.score > 0 }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.candidate.label < rhs.candidate.label
            }
            return lhs.score > rhs.score
        }

        guard let best = scored.first else {
            return HomeCandidateAggregationResult(
                finalCandidateIDs: [],
                needsClarification: true,
                clarificationQuestion: "Which device do you want to control?",
                confidence: 0.2
            )
        }

        let second = scored.dropFirst().first?.score ?? 0
        if second > 0 && best.score - second < 2 {
            return HomeCandidateAggregationResult(
                finalCandidateIDs: scored.prefix(3).map(\.candidate.id),
                needsClarification: true,
                clarificationQuestion: "Which device do you mean?",
                confidence: 0.45
            )
        }

        guard best.score >= 12 else { return nil }
        return HomeCandidateAggregationResult(
            finalCandidateIDs: [best.candidate.id],
            needsClarification: false,
            confidence: min(0.95, Double(best.score) / 28.0)
        )
    }

    private func resolveShard(
        userText: String,
        resolutionState: HomeResolutionState,
        shard: [HomeCompactCandidateView]
    ) async throws -> HomeCandidateShardSelection {
        let session = LanguageModelSession(instructions: Instructions("""
        Rank only the candidates in this shard for the user's smart-home command.
        Return candidate IDs only.
        Do not invent IDs.
        If no candidate matches, return an empty selectedCandidateIDs list.
        """))

        let prompt = """
        User command: \(userText)

        Resolution hints:
        - Intent families: \(resolutionState.intent.topFamilies)
        - Device types: \(resolutionState.deviceType.deviceTypes)
        - Rooms: \(resolutionState.slots.rooms)
        - Device nicknames: \(resolutionState.slots.deviceNicknames)
        - Values: \(resolutionState.slots.values)

        Candidate shard:
        \(shard.map(\.description).joined(separator: "\n"))
        """

        let response = try await session.respond(
            to: Prompt(prompt),
            generating: HomeCandidateShardSelection.self
        )
        return response.content
    }

    private func aggregate(
        userText: String,
        shardSelections: [HomeCandidateShardSelection]
    ) async throws -> HomeCandidateAggregationResult {
        let selectedIDs = shardSelections.flatMap(\.selectedCandidateIDs)
        guard !selectedIDs.isEmpty else {
            return HomeCandidateAggregationResult(
                finalCandidateIDs: [],
                needsClarification: true,
                clarificationQuestion: "Which device do you want to control?",
                confidence: 0
            )
        }

        let session = LanguageModelSession(instructions: Instructions("""
        Merge candidate IDs selected by shard resolver sessions.
        Choose the most likely final candidates for the user's smart-home command.
        If multiple candidates remain equally plausible, mark needsClarification true.
        Return IDs only and never invent an ID.
        """))

        let prompt = """
        User command: \(userText)
        Shard selections:
        \(shardSelections)
        """

        let response = try await session.respond(
            to: Prompt(prompt),
            generating: HomeCandidateAggregationResult.self
        )
        return response.content
    }
}
