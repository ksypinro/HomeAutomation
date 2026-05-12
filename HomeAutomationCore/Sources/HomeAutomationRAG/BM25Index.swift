import Foundation

public actor BM25Index {
    private var invertedIndex: [String: [(chunkIndex: Int, termFrequency: Int)]] = [:]
    private var documentLengths: [Int] = []
    private var averageDocumentLength: Double = 0
    private var chunks: [DocumentChunk] = []

    private let k1: Double
    private let b: Double

    public init(k1: Double = 1.2, b: Double = 0.75) {
        self.k1 = k1
        self.b = b
    }

    public func index(_ chunks: [DocumentChunk]) {
        self.chunks = chunks
        invertedIndex = [:]
        documentLengths = []

        for (chunkIndex, chunk) in chunks.enumerated() {
            let tokens = Self.indexTokens(for: chunk)
            documentLengths.append(tokens.count)

            var termCounts: [String: Int] = [:]
            for token in tokens {
                termCounts[token, default: 0] += 1
            }

            for (term, count) in termCounts {
                invertedIndex[term, default: []].append((chunkIndex: chunkIndex, termFrequency: count))
            }
        }

        let totalLength = documentLengths.reduce(0, +)
        averageDocumentLength = documentLengths.isEmpty
            ? 0
            : Double(totalLength) / Double(documentLengths.count)
    }

    public func clear() {
        invertedIndex = [:]
        documentLengths = []
        averageDocumentLength = 0
        chunks = []
    }

    public func search(
        terms: [String],
        topK: Int = 5,
        filter: MetadataFilter? = nil
    ) -> [ScoredChunk] {
        let queryTerms = Self.queryTokens(from: terms)
        guard !queryTerms.isEmpty, !chunks.isEmpty else { return [] }

        var scores: [Int: Double] = [:]
        let documentCount = Double(chunks.count)
        for term in queryTerms {
            guard let postings = invertedIndex[term], !postings.isEmpty else { continue }
            let documentFrequency = Double(postings.count)
            let idf = log(((documentCount - documentFrequency + 0.5) / (documentFrequency + 0.5)) + 1)

            for posting in postings {
                let chunk = chunks[posting.chunkIndex]
                guard filter.map({ $0.matches(chunk) }) ?? true else { continue }
                let frequency = Double(posting.termFrequency)
                let length = Double(max(documentLengths[posting.chunkIndex], 1))
                let denominator = frequency + k1 * (1 - b + b * length / max(averageDocumentLength, 1))
                scores[posting.chunkIndex, default: 0] += idf * ((frequency * (k1 + 1)) / denominator)
            }
        }

        return scores
            .compactMap { index, score -> ScoredChunk? in
                guard score > 0 else { return nil }
                return ScoredChunk(chunk: chunks[index], score: Float(score))
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
        chunks.count
    }

    private static func indexTokens(for chunk: DocumentChunk) -> [String] {
        let metadata = chunk.metadata
            .keys
            .sorted()
            .flatMap { key in
                [key, chunk.metadata[key] ?? ""]
            }
            .joined(separator: " ")
        return TFIDFEmbeddingProvider.normalizedTokens(
            [chunk.content, chunk.semanticContent, metadata].joined(separator: " ")
        )
    }

    private static func queryTokens(from terms: [String]) -> [String] {
        terms.flatMap(TFIDFEmbeddingProvider.normalizedTokens)
    }
}
