import Foundation

public actor VectorStore {
    private var entries: [(chunk: DocumentChunk, embedding: [Float])] = []

    public init() {}

    public func insert(_ chunk: DocumentChunk, embedding: [Float]) {
        entries.append((chunk, embedding))
    }

    public func insertBatch(_ items: [(DocumentChunk, [Float])]) {
        entries.append(contentsOf: items.map { (chunk: $0.0, embedding: $0.1) })
    }

    public func query(_ queryEmbedding: [Float], topK: Int = 5, filter: MetadataFilter? = nil) -> [ScoredChunk] {
        entries
            .filter { item in
                filter.map { $0.matches(item.chunk) } ?? true
            }
            .map { item in
                ScoredChunk(chunk: item.chunk, score: cosineSimilarity(queryEmbedding, item.embedding))
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

    public func count() -> Int {
        entries.count
    }

    public func allChunks() -> [DocumentChunk] {
        entries.map(\.chunk)
    }

    public func clear() {
        entries.removeAll()
    }

    // MARK: - Persistence

    /// Returns a snapshot of all entries suitable for disk serialisation.
    public func snapshot() -> [VectorStoreEntry] {
        entries.map { VectorStoreEntry(chunk: $0.chunk, embedding: $0.embedding) }
    }

    /// Replaces all entries with those from a previously persisted snapshot.
    public func restore(from entries: [VectorStoreEntry]) {
        self.entries = entries.map { (chunk: $0.chunk, embedding: $0.embedding) }
    }
}
