import Foundation

public struct HybridRetrievalStrategy: Sendable {
    private let vectorStore: VectorStore
    private let bm25Index: BM25Index
    private let embeddingProvider: any EmbeddingProviding
    private let rrfK: Double

    public init(
        vectorStore: VectorStore,
        bm25Index: BM25Index,
        embeddingProvider: any EmbeddingProviding,
        rrfK: Double = 60
    ) {
        self.vectorStore = vectorStore
        self.bm25Index = bm25Index
        self.embeddingProvider = embeddingProvider
        self.rrfK = rrfK
    }

    public func retrieve(_ query: StructuredRetrievalQuery) async -> [ScoredChunk] {
        switch query.strategy {
        case .semanticOnly:
            return await semanticSearch(query)
        case .keywordOnly:
            return await keywordSearch(query)
        case .hybrid, .agentic:
            async let semantic = semanticSearch(query)
            async let keyword = keywordSearch(query)
            return await reciprocalRankFusion(
                semantic: semantic,
                keyword: keyword,
                alpha: query.strategy.semanticWeight,
                topK: query.topK
            )
        }
    }

    private func semanticSearch(_ query: StructuredRetrievalQuery) async -> [ScoredChunk] {
        let embedding = await embeddingProvider.embed(query.semanticText)
        return await vectorStore.query(
            embedding,
            topK: query.topK,
            filter: query.metadataFilter,
            minScore: query.minScore
        )
    }

    private func keywordSearch(_ query: StructuredRetrievalQuery) async -> [ScoredChunk] {
        let terms = keywordTerms(for: query)
        return await bm25Index.search(
            terms: terms,
            topK: query.topK,
            filter: query.metadataFilter
        )
    }

    private func keywordTerms(for query: StructuredRetrievalQuery) -> [String] {
        var terms = query.keywordTerms
        if let operation = query.operation {
            terms.append(operation.rawValue)
        }
        terms.append(contentsOf: query.automationConcepts)
        terms.append(contentsOf: query.conditionOperators)
        terms.append(contentsOf: query.repeatHints)
        terms.append(query.rawText)
        return stableUnique(terms)
    }

    private func reciprocalRankFusion(
        semantic: [ScoredChunk],
        keyword: [ScoredChunk],
        alpha: Float,
        topK: Int
    ) -> [ScoredChunk] {
        var chunksByID: [String: DocumentChunk] = [:]
        var scores: [String: Double] = [:]
        let semanticWeight = Double(min(max(alpha, 0), 1))
        let keywordWeight = 1 - semanticWeight

        for (rank, result) in semantic.enumerated() {
            chunksByID[result.chunk.id] = result.chunk
            scores[result.chunk.id, default: 0] += semanticWeight / (rrfK + Double(rank + 1))
        }

        for (rank, result) in keyword.enumerated() {
            chunksByID[result.chunk.id] = result.chunk
            scores[result.chunk.id, default: 0] += keywordWeight / (rrfK + Double(rank + 1))
        }

        return scores
            .compactMap { id, score -> ScoredChunk? in
                guard let chunk = chunksByID[id], score > 0 else { return nil }
                return ScoredChunk(chunk: chunk, score: Float(score))
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.chunk.id < rhs.chunk.id
                }
                return lhs.score > rhs.score
            }
            .prefix(max(0, topK))
            .map { $0 }
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }
}
