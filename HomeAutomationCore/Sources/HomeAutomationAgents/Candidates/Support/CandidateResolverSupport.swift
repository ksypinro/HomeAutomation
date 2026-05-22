import Foundation
import FoundationModels
import HomeAutomationCore
import os

/// Metrics actor for tracking candidate resolution diagnostics.
public actor HomeCandidateResolverMetrics {
    public private(set) var lastStrategy = "none"
    public private(set) var lastCandidateCount = 0
    public private(set) var lastShardCount = 0
    public private(set) var lastParallelTaskCount = 0
    public private(set) var lastShardWinnerCount = 0
    public private(set) var lastContextBudgetReport: HomeModelContextBudgetReport?

    public init() {}

    public func record(
        strategy: String,
        candidateCount: Int,
        shardCount: Int = 0,
        parallelTaskCount: Int = 0,
        shardWinnerCount: Int = 0,
        contextBudgetReport: HomeModelContextBudgetReport? = nil
    ) {
        lastStrategy = strategy
        lastCandidateCount = candidateCount
        lastShardCount = shardCount
        lastParallelTaskCount = parallelTaskCount
        lastShardWinnerCount = shardWinnerCount
        if let contextBudgetReport {
            lastContextBudgetReport = contextBudgetReport
        }
    }

    public func recordContextBudget(_ report: HomeModelContextBudgetReport) {
        lastContextBudgetReport = report
    }
}

/// Candidate scoring, ranking, sharding, and aggregation support.
///
/// `HomeCandidateResolverSupport` encapsulates the core ranking logic used by
/// `CandidateRankingAgent` and `CandidateShardAgent`. It supports two strategies:
/// - **Direct**: For ≤ `shardSize` candidates, scores deterministically with optional
///   Foundation Models refinement
/// - **Parallel-sharded**: For large candidate sets, partitions into shards, resolves
///   each in parallel, then aggregates shard winners
public struct HomeCandidateResolverSupport: Sendable {
    private let shardSize: Int
    private let metrics: HomeCandidateResolverMetrics?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let promptBuilder: CandidateResolutionPromptBuilder
    private let logger = Logger(subsystem: "HomeAutomation", category: "Candidates.ResolverSupport")

    public init(
        shardSize: Int = 20,
        metrics: HomeCandidateResolverMetrics? = nil,
        promptBuilder: CandidateResolutionPromptBuilder = CandidateResolutionPromptBuilder(),
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        }
    ) {
        self.shardSize = shardSize
        self.metrics = metrics
        self.promptBuilder = promptBuilder
        self.foundationModelAvailability = foundationModelAvailability
    }

    public func resolveCandidates(
        userText: String,
        resolutionState: HomeResolutionState,
        candidates: [HomeCompactCandidateView],
        memoryHints: [MemoryHint] = []
    ) async throws -> HomeCandidateAggregationResult {
        let scopedCandidates = Self.scopedCandidates(candidates, using: resolutionState)
        guard !scopedCandidates.isEmpty else {
            await metrics?.record(strategy: "empty", candidateCount: 0)
            return HomeCandidateAggregationResult(
                finalCandidateIDs: [],
                needsClarification: true,
                clarificationQuestion: "Which device do you want to control?",
                confidence: 0
            )
        }

        if scopedCandidates.count <= shardSize {
            let result = try await resolveDirectly(
                userText: userText,
                resolutionState: resolutionState,
                candidates: scopedCandidates,
                memoryHints: memoryHints
            )
            await metrics?.record(
                strategy: "direct",
                candidateCount: scopedCandidates.count,
                shardWinnerCount: result.finalCandidateIDs.count
            )
            return result
        }

        let shards = stride(from: 0, to: scopedCandidates.count, by: shardSize).map {
            Array(scopedCandidates[$0..<min($0 + shardSize, scopedCandidates.count)])
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
            candidateCount: scopedCandidates.count,
            shardCount: shards.count,
            parallelTaskCount: shards.count,
            shardWinnerCount: result.finalCandidateIDs.count
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
        guard foundationModelAvailability() else {
            return deterministic
        }

        do {
            let deterministicHint: String
            if !deterministic.finalCandidateIDs.isEmpty {
                deterministicHint = "\nDeterministic scoring suggests candidates: \(deterministic.finalCandidateIDs) with confidence \(deterministic.confidence). Verify or correct."
            } else {
                deterministicHint = ""
            }
            let instructionText = """
            Select the best candidate IDs for the user's smart-home command.
            Use only the provided candidate IDs.
            If no candidate matches, return an empty finalCandidateIDs list and ask a clarification question.
            If multiple candidates are equally plausible, set needsClarification true.
            """
            let session = LanguageModelSession(instructions: Instructions(instructionText))
            let promptPackage = promptBuilder.makeDirectPrompt(
                userText: userText,
                resolutionState: resolutionState,
                candidates: candidates,
                memoryHints: memoryHints,
                instructionText: instructionText
            )
            await metrics?.recordContextBudget(promptPackage.contextBudgetReport)

            logger.debug("[resolveDirectly] FoundationModelInput System Instructions: \(instructionText, privacy: .public)")
            logger.debug("[resolveDirectly] FoundationModelInput Prompt: \(promptPackage.prompt, privacy: .public)")

            let response = try await respondForAggregation(
                session: session,
                prompt: promptPackage.prompt + deterministicHint,
                allowedIDs: candidates.map(\.id)
            )
            
            logger.debug("[resolveDirectly] FoundationModelOutput: \(String(describing: response), privacy: .public)")

            return Self.constrainAggregation(
                response,
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
        guard foundationModelAvailability() else {
            return deterministic
        }

        do {
            let deterministicHint: String
            if !selected.isEmpty {
                deterministicHint = "\nDeterministic scoring suggests: \(selected) with confidence \(aggregation.confidence). Verify or correct."
            } else {
                deterministicHint = ""
            }
            let instructionText = """
            Rank only the candidates in this shard for the user's smart-home command.
            Return candidate IDs only.
            Do not invent IDs.
            If no candidate matches, return an empty selectedCandidateIDs list.
            """
            let session = LanguageModelSession(instructions: Instructions(instructionText))
            let promptPackage = promptBuilder.makeShardPrompt(
                userText: userText,
                resolutionState: resolutionState,
                shard: shard,
                memoryHints: memoryHints,
                instructionText: instructionText
            )
            await metrics?.recordContextBudget(promptPackage.contextBudgetReport)

            logger.debug("[resolveShard] FoundationModelInput System Instructions: \(instructionText, privacy: .public)")
            logger.debug("[resolveShard] FoundationModelInput Prompt: \(promptPackage.prompt, privacy: .public)")

            let response = try await respondForShardSelection(
                session: session,
                prompt: promptPackage.prompt + deterministicHint,
                allowedIDs: shard.map(\.id)
            )
            logger.debug("[resolveShard] FoundationModelOutput: \(String(describing: response), privacy: .public)")
            return Self.constrainShardSelection(
                response,
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

        if let clearWinner = Self.clearShardWinner(from: shardSelections) {
            return clearWinner
        }

        guard foundationModelAvailability(), selectedIDs.count > 1 else {
            return deterministic
        }

        do {
            let instructionText = """
            Merge candidate IDs selected by shard resolver sessions.
            Choose the most likely final candidates for the user's smart-home command.
            If multiple candidates remain equally plausible, mark needsClarification true.
            Return IDs only and never invent an ID.
            """
            let session = LanguageModelSession(instructions: Instructions(instructionText))

            let prompt = """
            User command: \(userText)
            Shard selections:
            \(shardSelections)
            """

            logger.debug("[aggregate] FoundationModelInput System Instructions: \(instructionText, privacy: .public)")
            logger.debug("[aggregate] FoundationModelInput Prompt: \(prompt, privacy: .public)")

            let response = try await session.respond(
                to: Prompt(prompt),
                generating: HomeCandidateAggregationResult.self
            )
            
            logger.debug("[aggregate] FoundationModelOutput: \(String(describing: response.content), privacy: .public)")
            return Self.constrainAggregation(
                response.content,
                allowedIDs: selectedIDs,
                fallback: deterministic
            )
        } catch {
            return deterministic
        }
    }

    private func respondForAggregation(
        session: LanguageModelSession,
        prompt: String,
        allowedIDs: [String]
    ) async throws -> HomeCandidateAggregationResult {
        if let schema = try? Self.aggregationSchema(allowedIDs: allowedIDs) {
            let response = try await session.respond(to: Prompt(prompt), schema: schema)
            return try Self.aggregationResult(from: response.content)
        }

        let response = try await session.respond(
            to: Prompt(prompt),
            generating: HomeCandidateAggregationResult.self
        )
        return response.content
    }

    private func respondForShardSelection(
        session: LanguageModelSession,
        prompt: String,
        allowedIDs: [String]
    ) async throws -> HomeCandidateShardSelection {
        if let schema = try? Self.shardSelectionSchema(allowedIDs: allowedIDs) {
            let response = try await session.respond(to: Prompt(prompt), schema: schema)
            return try Self.shardSelection(from: response.content)
        }

        let response = try await session.respond(
            to: Prompt(prompt),
            generating: HomeCandidateShardSelection.self
        )
        return response.content
    }

    private static func aggregationSchema(allowedIDs: [String]) throws -> GenerationSchema {
        guard !allowedIDs.isEmpty else {
            throw FoundationLabCoreError.invalidRequest("Candidate ID schema requires IDs")
        }
        let idSchema = DynamicGenerationSchema(name: "CandidateID", anyOf: allowedIDs)
        let root = DynamicGenerationSchema(
            name: "HomeCandidateAggregationResult",
            properties: [
                .init(
                    name: "finalCandidateIDs",
                    description: "Final candidate IDs selected from provided candidates only.",
                    schema: DynamicGenerationSchema(arrayOf: idSchema, maximumElements: 5)
                ),
                .init(name: "needsClarification", schema: DynamicGenerationSchema(type: Bool.self)),
                .init(
                    name: "clarificationQuestion",
                    description: "One concise user-facing question when clarification is needed.",
                    schema: DynamicGenerationSchema(type: String.self),
                    isOptional: true
                ),
                .init(name: "confidence", schema: DynamicGenerationSchema(type: Double.self))
            ]
        )
        return try GenerationSchema(root: root, dependencies: [])
    }

    private static func shardSelectionSchema(allowedIDs: [String]) throws -> GenerationSchema {
        guard !allowedIDs.isEmpty else {
            throw FoundationLabCoreError.invalidRequest("Candidate ID schema requires IDs")
        }
        let idSchema = DynamicGenerationSchema(name: "ShardCandidateID", anyOf: allowedIDs)
        let root = DynamicGenerationSchema(
            name: "HomeCandidateShardSelection",
            properties: [
                .init(
                    name: "selectedCandidateIDs",
                    description: "Candidate IDs selected from this shard only.",
                    schema: DynamicGenerationSchema(arrayOf: idSchema, maximumElements: 3)
                ),
                .init(
                    name: "rejectedCandidateIDs",
                    description: "Candidate IDs rejected from this shard only.",
                    schema: DynamicGenerationSchema(arrayOf: idSchema, maximumElements: 20)
                ),
                .init(name: "confidence", schema: DynamicGenerationSchema(type: Double.self)),
                .init(
                    name: "reason",
                    description: "One concise sentence explaining the shard choice.",
                    schema: DynamicGenerationSchema(type: String.self)
                )
            ]
        )
        return try GenerationSchema(root: root, dependencies: [])
    }

    private static func aggregationResult(from content: GeneratedContent) throws -> HomeCandidateAggregationResult {
        HomeCandidateAggregationResult(
            finalCandidateIDs: try content.value([String].self, forProperty: "finalCandidateIDs"),
            needsClarification: try content.value(Bool.self, forProperty: "needsClarification"),
            clarificationQuestion: try? content.value(String.self, forProperty: "clarificationQuestion"),
            confidence: try content.value(Double.self, forProperty: "confidence")
        )
    }

    private static func shardSelection(from content: GeneratedContent) throws -> HomeCandidateShardSelection {
        HomeCandidateShardSelection(
            selectedCandidateIDs: try content.value([String].self, forProperty: "selectedCandidateIDs"),
            rejectedCandidateIDs: try content.value([String].self, forProperty: "rejectedCandidateIDs"),
            confidence: try content.value(Double.self, forProperty: "confidence"),
            reason: try content.value(String.self, forProperty: "reason")
        )
    }

    internal static func stableUnique(_ values: [String]) -> [String] {
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

    private static func clearShardWinner(from shardSelections: [HomeCandidateShardSelection]) -> HomeCandidateAggregationResult? {
        let nonEmpty = shardSelections.filter { !$0.selectedCandidateIDs.isEmpty }
        guard nonEmpty.count > 1 else { return nil }
        let ranked = nonEmpty.sorted { lhs, rhs in
            if lhs.confidence == rhs.confidence {
                return lhs.selectedCandidateIDs.lexicographicallyPrecedes(rhs.selectedCandidateIDs)
            }
            return lhs.confidence > rhs.confidence
        }
        guard let best = ranked.first,
              let second = ranked.dropFirst().first,
              best.selectedCandidateIDs.count == 1,
              best.confidence >= 0.78,
              best.confidence - second.confidence >= 0.20 else {
            return nil
        }
        return HomeCandidateAggregationResult(
            finalCandidateIDs: [best.selectedCandidateIDs[0]],
            needsClarification: false,
            confidence: best.confidence
        )
    }
}

private struct IndexedShardSelection: Sendable {
    let index: Int
    let selection: HomeCandidateShardSelection
}
