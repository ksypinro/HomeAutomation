import Foundation

public struct StructuredRetrievalQuery: Sendable, Hashable {
    public let rawText: String
    public let semanticText: String
    public let keywordTerms: [String]
    public let metadataFilter: MetadataFilter?
    public let nluHints: NLURetrievalHints?
    public let strategy: RetrievalStrategy
    public let minScore: Float
    public let topK: Int

    public init(
        rawText: String,
        semanticText: String? = nil,
        keywordTerms: [String] = [],
        metadataFilter: MetadataFilter? = nil,
        nluHints: NLURetrievalHints? = nil,
        strategy: RetrievalStrategy = .semanticOnly,
        minScore: Float = 0,
        topK: Int = 5
    ) {
        self.rawText = rawText
        self.semanticText = semanticText ?? rawText
        self.keywordTerms = keywordTerms
        self.metadataFilter = metadataFilter
        self.nluHints = nluHints
        self.strategy = strategy
        self.minScore = minScore
        self.topK = topK
    }
}

public struct NLURetrievalHints: Sendable, Hashable, Codable {
    public let deviceTypes: [String]
    public let intentFamilies: [String]
    public let rooms: [String]
    public let capabilities: [String]

    public init(
        deviceTypes: [String] = [],
        intentFamilies: [String] = [],
        rooms: [String] = [],
        capabilities: [String] = []
    ) {
        self.deviceTypes = Self.stableUnique(deviceTypes)
        self.intentFamilies = Self.stableUnique(intentFamilies)
        self.rooms = Self.stableUnique(rooms)
        self.capabilities = Self.stableUnique(capabilities)
    }

    public var isEmpty: Bool {
        deviceTypes.isEmpty && intentFamilies.isEmpty && rooms.isEmpty && capabilities.isEmpty
    }

    private static func stableUnique(_ values: [String]) -> [String] {
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

public enum RetrievalStrategy: Sendable, Hashable, Codable {
    case semanticOnly
    case keywordOnly
    case hybrid(alpha: Float)
    case agentic

    public var name: String {
        switch self {
        case .semanticOnly:
            return "semanticOnly"
        case .keywordOnly:
            return "keywordOnly"
        case .hybrid:
            return "hybrid"
        case .agentic:
            return "agentic"
        }
    }

    public var semanticWeight: Float {
        switch self {
        case .semanticOnly:
            return 1
        case .keywordOnly:
            return 0
        case .hybrid(let alpha):
            return min(max(alpha, 0), 1)
        case .agentic:
            return 0.55
        }
    }
}
