import Foundation
import FoundationModels
import HomeAutomationCore
import HomeAutomationRAG

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

public struct CandidateHydrationInput: Sendable, Hashable {
    public let candidateIDs: [String]

    public init(candidateIDs: [String]) {
        self.candidateIDs = candidateIDs
    }
}

public actor HomeCandidateResolverMetrics {
    public private(set) var lastStrategy = "none"
    public private(set) var lastCandidateCount = 0
    public private(set) var lastShardCount = 0
    public private(set) var lastParallelTaskCount = 0
    public private(set) var lastShardWinnerCount = 0

    public init() {}

    public func record(
        strategy: String,
        candidateCount: Int,
        shardCount: Int = 0,
        parallelTaskCount: Int = 0,
        shardWinnerCount: Int = 0
    ) {
        lastStrategy = strategy
        lastCandidateCount = candidateCount
        lastShardCount = shardCount
        lastParallelTaskCount = parallelTaskCount
        lastShardWinnerCount = shardWinnerCount
    }
}

public struct HomeCandidateResolverSupport: Sendable {
    private let shardSize: Int
    private let metrics: HomeCandidateResolverMetrics?
    private let foundationModelAvailability: @Sendable () -> Bool

    public init(
        shardSize: Int = 20,
        metrics: HomeCandidateResolverMetrics? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        }
    ) {
        self.shardSize = shardSize
        self.metrics = metrics
        self.foundationModelAvailability = foundationModelAvailability
    }

    public func resolveCandidates(
        userText: String,
        resolutionState: HomeResolutionState,
        candidates: [HomeCompactCandidateView],
        memoryHints: [MemoryHint] = []
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
            let result = try await resolveDirectly(
                userText: userText,
                resolutionState: resolutionState,
                candidates: candidates,
                memoryHints: memoryHints
            )
            await metrics?.record(
                strategy: "direct",
                candidateCount: candidates.count,
                shardWinnerCount: result.finalCandidateIDs.count
            )
            return result
        }

        let shards = stride(from: 0, to: candidates.count, by: shardSize).map {
            Array(candidates[$0..<min($0 + shardSize, candidates.count)])
        }
        let selections = try await resolveShardsInParallel(
            userText: userText,
            resolutionState: resolutionState,
            shards: shards,
            memoryHints: memoryHints
        )
        let result = try await aggregate(
            userText: userText,
            shardSelections: selections
        )
        await metrics?.record(
            strategy: "parallel-sharded",
            candidateCount: candidates.count,
            shardCount: shards.count,
            parallelTaskCount: shards.count,
            shardWinnerCount: selections.flatMap(\.selectedCandidateIDs).count
        )
        return result
    }

    private func resolveDirectly(
        userText: String,
        resolutionState: HomeResolutionState,
        candidates: [HomeCompactCandidateView],
        memoryHints: [MemoryHint]
    ) async throws -> HomeCandidateAggregationResult {
        let deterministic = deterministicAggregation(
            userText: userText,
            resolutionState: resolutionState,
            candidates: candidates,
            memoryHints: memoryHints
        )
        guard foundationModelAvailability(),
              deterministic.needsClarification || deterministic.confidence < 0.7 else {
            return deterministic
        }

        do {
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
            - Memory hints: \(memoryHints)

            Candidates:
            \(candidates.map(\.description).joined(separator: "\n"))
            """

            let response = try await session.respond(
                to: Prompt(prompt),
                generating: HomeCandidateAggregationResult.self
            )
            return Self.constrainAggregation(
                response.content,
                allowedIDs: candidates.map(\.id),
                fallback: deterministic
            )
        } catch {
            return deterministic
        }
    }

    private func resolveShardsInParallel(
        userText: String,
        resolutionState: HomeResolutionState,
        shards: [[HomeCompactCandidateView]],
        memoryHints: [MemoryHint]
    ) async throws -> [HomeCandidateShardSelection] {
        try await withThrowingTaskGroup(of: IndexedShardSelection.self) { group in
            for (index, shard) in shards.enumerated() {
                group.addTask {
                    let selection = try await resolveShard(
                        userText: userText,
                        resolutionState: resolutionState,
                        shard: shard,
                        memoryHints: memoryHints
                    )
                    return IndexedShardSelection(index: index, selection: selection)
                }
            }

            var selections: [IndexedShardSelection] = []
            for try await selection in group {
                selections.append(selection)
            }
            return selections
                .sorted { $0.index < $1.index }
                .map(\.selection)
        }
    }

    public func resolveShard(
        userText: String,
        resolutionState: HomeResolutionState,
        shard: [HomeCompactCandidateView],
        memoryHints: [MemoryHint] = []
    ) async throws -> HomeCandidateShardSelection {
        let aggregation = deterministicAggregation(
            userText: userText,
            resolutionState: resolutionState,
            candidates: shard,
            memoryHints: memoryHints
        )
        let selected = Array(aggregation.finalCandidateIDs.prefix(3))
        let rejected = shard.map(\.id).filter { !selected.contains($0) }
        let deterministic = HomeCandidateShardSelection(
            selectedCandidateIDs: selected,
            rejectedCandidateIDs: rejected,
            confidence: aggregation.confidence,
            reason: aggregation.needsClarification ? "Deterministic shard selection is ambiguous" : "Deterministic shard selection"
        )
        guard foundationModelAvailability(),
              deterministic.confidence < 0.7 || selected.count != 1 else {
            return deterministic
        }

        do {
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
            - Memory hints: \(memoryHints)

            Candidate shard:
            \(shard.map(\.description).joined(separator: "\n"))
            """

            let response = try await session.respond(
                to: Prompt(prompt),
                generating: HomeCandidateShardSelection.self
            )
            return Self.constrainShardSelection(
                response.content,
                allowedIDs: shard.map(\.id),
                fallback: deterministic
            )
        } catch {
            return deterministic
        }
    }

    private func aggregate(
        userText: String,
        shardSelections: [HomeCandidateShardSelection]
    ) async throws -> HomeCandidateAggregationResult {
        let selectedIDs = Self.stableUnique(shardSelections.flatMap(\.selectedCandidateIDs))
        guard !selectedIDs.isEmpty else {
            return HomeCandidateAggregationResult(
                finalCandidateIDs: [],
                needsClarification: true,
                clarificationQuestion: "Which device do you want to control?",
                confidence: 0
            )
        }

        let deterministic = HomeCandidateAggregationResult(
            finalCandidateIDs: selectedIDs,
            needsClarification: selectedIDs.count != 1,
            clarificationQuestion: selectedIDs.count == 1 ? nil : "Which device do you mean?",
            confidence: selectedIDs.count == 1 ? 0.65 : 0.55
        )

        guard foundationModelAvailability(), selectedIDs.count > 1 else {
            return deterministic
        }

        do {
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
            return Self.constrainAggregation(
                response.content,
                allowedIDs: selectedIDs,
                fallback: deterministic
            )
        } catch {
            return deterministic
        }
    }

    private func deterministicAggregation(
        userText: String,
        resolutionState: HomeResolutionState,
        candidates: [HomeCompactCandidateView],
        memoryHints: [MemoryHint]
    ) -> HomeCandidateAggregationResult {
        let normalized = userText.agentNormalizedHomeTokenString
        let rooms = Set(resolutionState.slots.rooms.map(\.agentNormalizedHomeTokenString))
        let types = Set(resolutionState.deviceType.deviceTypes.map(\.agentNormalizedHomeTokenString))
        let hintedDeviceIDs = Set(memoryHints.compactMap(\.deviceID))
        let hintedCapabilities = Set(memoryHints.compactMap(\.capability))

        let scored = candidates.map { candidate in
            var score = 0
            let label = candidate.label.agentNormalizedHomeTokenString
            let type = candidate.deviceType.agentNormalizedHomeTokenString
            let room = candidate.room?.agentNormalizedHomeTokenString

            if normalized.contains(label) { score += 20 }
            if normalized.contains(type) || types.contains(type) { score += 8 }
            if let room, normalized.contains(room) || rooms.contains(room) { score += 8 }

            let overlap = normalized.agentTokenSet.intersection(label.agentTokenSet).count
            score += min(overlap * 2, 8)

            if resolutionState.intent.topFamilies.contains(.power),
               candidate.shortCapabilities.contains("switch") {
                score += 4
            }
            if resolutionState.intent.topFamilies.contains(.brightness),
               candidate.shortCapabilities.contains("switchLevel") {
                score += 4
            }
            if resolutionState.intent.topFamilies.contains(.temperature),
               candidate.shortCapabilities.contains(where: { $0.contains("thermostat") || $0 == "temperatureMeasurement" }) {
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
            if hintedDeviceIDs.contains(candidate.id) {
                score += 10
            }
            if !hintedCapabilities.isDisjoint(with: Set(candidate.shortCapabilities)) {
                score += 4
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

        return HomeCandidateAggregationResult(
            finalCandidateIDs: [best.candidate.id],
            needsClarification: false,
            confidence: min(0.95, Double(best.score) / 28.0)
        )
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private static func constrainShardSelection(
        _ selection: HomeCandidateShardSelection,
        allowedIDs: [String],
        fallback: HomeCandidateShardSelection
    ) -> HomeCandidateShardSelection {
        let allowed = Set(allowedIDs)
        let selected = stableUnique(selection.selectedCandidateIDs.filter { allowed.contains($0) })
        guard !selected.isEmpty || selection.selectedCandidateIDs.isEmpty else {
            return fallback
        }
        let rejected = allowedIDs.filter { !selected.contains($0) }
        return HomeCandidateShardSelection(
            selectedCandidateIDs: selected,
            rejectedCandidateIDs: rejected,
            confidence: selection.confidence,
            reason: selection.reason
        )
    }

    private static func constrainAggregation(
        _ aggregation: HomeCandidateAggregationResult,
        allowedIDs: [String],
        fallback: HomeCandidateAggregationResult
    ) -> HomeCandidateAggregationResult {
        let allowed = Set(allowedIDs)
        let selected = stableUnique(aggregation.finalCandidateIDs.filter { allowed.contains($0) })
        guard !selected.isEmpty || aggregation.finalCandidateIDs.isEmpty else {
            return fallback
        }
        return HomeCandidateAggregationResult(
            finalCandidateIDs: selected,
            needsClarification: aggregation.needsClarification || selected.count != 1,
            clarificationQuestion: selected.count == 1 ? aggregation.clarificationQuestion : aggregation.clarificationQuestion ?? "Which device do you mean?",
            confidence: aggregation.confidence
        )
    }
}

private struct IndexedShardSelection: Sendable {
    let index: Int
    let selection: HomeCandidateShardSelection
}

public struct CandidateRetrievalAgent: HomeAgent {
    public typealias Input = CandidateRetrievalInput
    public typealias Output = [HomeCandidateRecord]

    public let id = AgentID.candidateRetrieval
    public let capabilities: Set<AgentCapability> = [.candidateRetrieval]
    public let timeoutNanoseconds: UInt64 = 5_000_000_000
    private let retrieve: @Sendable (CandidateRetrievalInput) async throws -> [HomeCandidateRecord]

    public init(retrieve: @escaping @Sendable (CandidateRetrievalInput) async throws -> [HomeCandidateRecord]) {
        self.retrieve = retrieve
    }

    public init(
        registry: MockHomeDeviceRegistry = MockHomeDeviceRegistry(),
        contextRetriever: ContextRetriever? = nil
    ) {
        self.retrieve = { input in
            let existing = await registry.retrieveCandidates(text: input.text, hints: input.state, limit: input.limit)
            let allDevices = await registry.allDevices()
            let memoryDeviceIDs = Set(input.memoryHints.compactMap(\.deviceID))
            let memoryCandidates = allDevices.filter { memoryDeviceIDs.contains($0.id) }
            guard let contextRetriever else {
                return AgentRAGSupport.stableUnique(existing + memoryCandidates) { $0.id }
            }

            let semanticQuery = Self.semanticQuery(from: input)
            let deviceChunks = await contextRetriever.retrieve(
                query: semanticQuery,
                topK: 12,
                filter: MetadataFilter(source: .device)
            )
            let ragDeviceIDs = Set(deviceChunks.compactMap { $0.chunk.metadata["deviceId"] })
            guard !ragDeviceIDs.isEmpty else {
                return AgentRAGSupport.stableUnique(existing + memoryCandidates) { $0.id }
            }

            let ragOnlyCandidates = allDevices.filter { ragDeviceIDs.contains($0.id) }
            return AgentRAGSupport.stableUnique(existing + ragOnlyCandidates + memoryCandidates) { $0.id }
        }
    }

    public func run(_ input: CandidateRetrievalInput, context: ResolutionContext) async throws -> [HomeCandidateRecord] {
        try await retrieve(input)
    }

    private static func semanticQuery(from input: CandidateRetrievalInput) -> String {
        var parts: [String] = [input.text]
        parts.append(contentsOf: input.state.slots.rooms)
        parts.append(contentsOf: input.state.slots.deviceNicknames)
        parts.append(contentsOf: input.state.deviceType.deviceTypes)
        parts.append(contentsOf: input.state.intent.topFamilies.map { String(describing: $0) })
        parts.append(contentsOf: input.memoryHints.compactMap(\.deviceID))
        parts.append(contentsOf: input.memoryHints.compactMap(\.capability))
        return parts.joined(separator: " ")
    }
}

public struct CandidateRankingAgent: HomeAgent {
    public typealias Input = CandidateRankingInput
    public typealias Output = HomeCandidateAggregationResult

    public let id = AgentID.candidateRanking
    public let capabilities: Set<AgentCapability> = [.candidateRanking]
    public let timeoutNanoseconds: UInt64 = 10_000_000_000
    private let rank: @Sendable (CandidateRankingInput) async throws -> HomeCandidateAggregationResult

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
        try await rank(input)
    }
}

public struct CandidateShardAgent: HomeAgent {
    public typealias Input = CandidateShardInput
    public typealias Output = HomeCandidateShardSelection

    public let id = AgentID.candidateShard
    public let capabilities: Set<AgentCapability> = [.candidateSharding]
    public let timeoutNanoseconds: UInt64 = 10_000_000_000
    private let shard: @Sendable (CandidateShardInput) async throws -> HomeCandidateShardSelection

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
        try await shard(input)
    }
}

public struct CandidateHydrationAgent: HomeAgent {
    public typealias Input = CandidateHydrationInput
    public typealias Output = [HomeCandidateRecord]

    public let id = AgentID.candidateHydration
    public let capabilities: Set<AgentCapability> = [.candidateHydration]
    public let timeoutNanoseconds: UInt64 = 5_000_000_000
    private let hydrate: @Sendable (CandidateHydrationInput) async throws -> [HomeCandidateRecord]

    public init(hydrate: @escaping @Sendable (CandidateHydrationInput) async throws -> [HomeCandidateRecord]) {
        self.hydrate = hydrate
    }

    public init(registry: MockHomeDeviceRegistry = MockHomeDeviceRegistry()) {
        self.hydrate = { input in
            let devices = await registry.allDevices()
            let idSet = Set(input.candidateIDs)
            return devices.filter { idSet.contains($0.id) }
        }
    }

    public func run(_ input: CandidateHydrationInput, context: ResolutionContext) async throws -> [HomeCandidateRecord] {
        try await hydrate(input)
    }
}
