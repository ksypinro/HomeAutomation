import Foundation

public struct ContextRetriever: Sendable {
    private let embeddingProvider: any EmbeddingProviding
    private let vectorStore: VectorStore

    public init(embeddingProvider: any EmbeddingProviding, vectorStore: VectorStore) {
        self.embeddingProvider = embeddingProvider
        self.vectorStore = vectorStore
    }

    public func retrieve(
        _ query: String,
        topK: Int = 5,
        filter: MetadataFilter? = nil
    ) async -> [ScoredChunk] {
        let embedding = await embeddingProvider.embed(query)
        return await vectorStore.query(embedding, topK: topK, filter: filter)
    }

    public func retrieve(
        query: String,
        topK: Int = 5,
        filter: MetadataFilter? = nil
    ) async -> [ScoredChunk] {
        await retrieve(query, topK: topK, filter: filter)
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
