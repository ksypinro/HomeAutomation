import Foundation

public protocol EmbeddingProviding: Sendable {
    func embed(_ text: String) async -> [Float]
    func embedBatch(_ texts: [String]) async -> [[Float]]
}

public protocol CorpusAwareEmbeddingProviding: EmbeddingProviding {
    func prepareForCorpus(_ texts: [String]) async
}

public actor TFIDFEmbeddingProvider: CorpusAwareEmbeddingProviding {
    private var vocabulary: [String: Int] = [:]
    private var documentFrequency: [String: Int] = [:]
    private var documentCount: Int = 0

    public init() {}

    public func buildVocabulary(from texts: [String]) async {
        await prepareForCorpus(texts)
    }

    public func prepareForCorpus(_ texts: [String]) async {
        vocabulary = [:]
        documentFrequency = [:]
        documentCount = texts.count

        var allTokens = Set<String>()
        for text in texts {
            let tokens = Set(Self.tokenize(text))
            for token in tokens {
                documentFrequency[token, default: 0] += 1
                allTokens.insert(token)
            }
        }

        for (index, token) in allTokens.sorted().enumerated() {
            vocabulary[token] = index
        }
    }

    public func embed(_ text: String) async -> [Float] {
        tfidfVector(for: text)
    }

    public func embedBatch(_ texts: [String]) async -> [[Float]] {
        texts.map { tfidfVector(for: $0) }
    }

    public static func tokenize(_ text: String) -> [String] {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        let tokens = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }

        return tokens.flatMap { token -> [String] in
            Self.synonyms[token, default: []] + [token]
        }
    }

    private func tfidfVector(for text: String) -> [Float] {
        let tokens = Self.tokenize(text)
        guard !vocabulary.isEmpty else { return [] }

        var vector = [Float](repeating: 0, count: vocabulary.count)
        var termFrequency: [String: Int] = [:]
        for token in tokens {
            termFrequency[token, default: 0] += 1
        }

        let total = Float(max(tokens.count, 1))
        for (token, count) in termFrequency {
            guard let index = vocabulary[token] else { continue }
            let idf = log(Float(max(documentCount, 1)) / Float(documentFrequency[token, default: 1]) + 1.0)
            vector[index] = Float(count) / total * idf
        }
        return vector
    }

    private static let synonyms: [String: [String]] = [
        "lamp": ["light", "switch"],
        "bulb": ["light", "switch"],
        "lights": ["light", "switch"],
        "switch": ["light"],
        "thermostat": ["temperature", "setpoint"],
        "ac": ["air", "conditioner", "temperature"],
        "cooler": ["cooling", "temperature"],
        "warmer": ["heating", "temperature"],
        "brightness": ["level", "light"],
        "dim": ["brightness", "level"],
        "lock": ["door", "security"],
        "unlock": ["door", "security"],
        "camera": ["video", "stream"],
        "scene": ["routine"],
        "movie": ["routine", "scene"]
    ]
}

public struct SemanticEmbeddingProvider: CorpusAwareEmbeddingProviding {
    private let embedOne: @Sendable (String) async -> [Float]
    private let prepareCorpus: @Sendable ([String]) async -> Void

    public init(
        embed: @escaping @Sendable (String) async -> [Float],
        prepareCorpus: @escaping @Sendable ([String]) async -> Void = { _ in }
    ) {
        self.embedOne = embed
        self.prepareCorpus = prepareCorpus
    }

    public func prepareForCorpus(_ texts: [String]) async {
        await prepareCorpus(texts)
    }

    public func embed(_ text: String) async -> [Float] {
        await embedOne(text)
    }

    public func embedBatch(_ texts: [String]) async -> [[Float]] {
        await withTaskGroup(of: IndexedEmbedding.self) { group in
            for (index, text) in texts.enumerated() {
                group.addTask {
                    IndexedEmbedding(index: index, embedding: await embedOne(text))
                }
            }

            var indexed: [IndexedEmbedding] = []
            for await item in group {
                indexed.append(item)
            }
            return indexed
                .sorted { $0.index < $1.index }
                .map(\.embedding)
        }
    }
}

public struct FallbackEmbeddingProvider: CorpusAwareEmbeddingProviding {
    private let primary: any EmbeddingProviding
    private let fallback: any EmbeddingProviding

    public init(primary: any EmbeddingProviding, fallback: any EmbeddingProviding = TFIDFEmbeddingProvider()) {
        self.primary = primary
        self.fallback = fallback
    }

    public func prepareForCorpus(_ texts: [String]) async {
        if let primary = primary as? any CorpusAwareEmbeddingProviding {
            await primary.prepareForCorpus(texts)
        }
        if let fallback = fallback as? any CorpusAwareEmbeddingProviding {
            await fallback.prepareForCorpus(texts)
        }
    }

    public func embed(_ text: String) async -> [Float] {
        let primaryEmbedding = await primary.embed(text)
        guard primaryEmbedding.isEmpty else { return primaryEmbedding }
        return await fallback.embed(text)
    }

    public func embedBatch(_ texts: [String]) async -> [[Float]] {
        let primaryEmbeddings = await primary.embedBatch(texts)
        guard primaryEmbeddings.count == texts.count else {
            return await texts.asyncMap { await embed($0) }
        }

        var resolved = primaryEmbeddings
        let missingIndexes = primaryEmbeddings.indices.filter { primaryEmbeddings[$0].isEmpty }
        guard !missingIndexes.isEmpty else { return resolved }

        let fallbackEmbeddings = await fallback.embedBatch(missingIndexes.map { texts[$0] })
        for (offset, index) in missingIndexes.enumerated() where offset < fallbackEmbeddings.count {
            resolved[index] = fallbackEmbeddings[offset]
        }
        return resolved
    }
}

private struct IndexedEmbedding: Sendable {
    let index: Int
    let embedding: [Float]
}

private extension Array where Element == String {
    func asyncMap<T: Sendable>(_ transform: @escaping @Sendable (String) async -> T) async -> [T] {
        await withTaskGroup(of: (Int, T).self) { group in
            for (index, value) in enumerated() {
                group.addTask {
                    (index, await transform(value))
                }
            }

            var values: [(Int, T)] = []
            for await value in group {
                values.append(value)
            }
            return values.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}

public func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
    guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }

    var dot: Float = 0
    var lhsNorm: Float = 0
    var rhsNorm: Float = 0

    for index in lhs.indices {
        dot += lhs[index] * rhs[index]
        lhsNorm += lhs[index] * lhs[index]
        rhsNorm += rhs[index] * rhs[index]
    }

    let denominator = sqrt(lhsNorm) * sqrt(rhsNorm)
    return denominator > 0 ? dot / denominator : 0
}
