import Foundation

public struct ContextRetriever: Sendable {
    private let embeddingProvider: any EmbeddingProviding
    private let vectorStore: VectorStore
    private let bm25Index: BM25Index?

    public init(
        embeddingProvider: any EmbeddingProviding,
        vectorStore: VectorStore,
        bm25Index: BM25Index? = nil
    ) {
        self.embeddingProvider = embeddingProvider
        self.vectorStore = vectorStore
        self.bm25Index = bm25Index
    }

    public func retrieve(
        _ query: String,
        topK: Int = 5,
        filter: MetadataFilter? = nil,
        minScore: Float = 0
    ) async -> [ScoredChunk] {
        let embedding = await embeddingProvider.embed(query)
        return await vectorStore.query(embedding, topK: topK, filter: filter, minScore: minScore)
    }

    public func retrieve(
        query: String,
        topK: Int = 5,
        filter: MetadataFilter? = nil,
        minScore: Float = 0
    ) async -> [ScoredChunk] {
        await retrieve(query, topK: topK, filter: filter, minScore: minScore)
    }

    public func retrieve(_ query: StructuredRetrievalQuery) async -> [ScoredChunk] {
        guard let bm25Index else {
            return await retrieve(
                query.semanticText,
                topK: query.topK,
                filter: query.metadataFilter,
                minScore: query.minScore
            )
        }
        let strategy = HybridRetrievalStrategy(
            vectorStore: vectorStore,
            bm25Index: bm25Index,
            embeddingProvider: embeddingProvider
        )
        return await strategy.retrieve(query)
    }

    public func retrieveFormatted(
        _ query: String,
        topK: Int = 5,
        sources: [KnowledgeSource] = KnowledgeSource.allCases
    ) async -> String {
        var results: [ScoredChunk] = []
        for source in sources {
            let chunks = await retrieve(query, topK: topK, filter: MetadataFilter(source: source))
            results.append(contentsOf: chunks)
        }

        return results
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.chunk.id < rhs.chunk.id
                }
                return lhs.score > rhs.score
            }
            .prefix(topK)
            .map { result in
                let metadata = result.chunk.metadata
                    .keys
                    .sorted()
                    .map { "\($0)=\(result.chunk.metadata[$0] ?? "")" }
                    .joined(separator: ", ")
                return """
                [\(result.chunk.source.rawValue)] \(result.chunk.id) score=\(String(format: "%.3f", result.score))
                \(result.chunk.content)
                metadata: \(metadata)
                """
            }
            .joined(separator: "\n\n")
    }

    public func retrieveFormatted(
        query: String,
        topK: Int = 5,
        sources: [KnowledgeSource] = KnowledgeSource.allCases
    ) async -> String {
        await retrieveFormatted(query, topK: topK, sources: sources)
    }
}
