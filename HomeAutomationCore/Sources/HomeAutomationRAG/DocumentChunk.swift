import Foundation

public struct DocumentChunk: Identifiable, Sendable, Hashable, Codable {
    public let id: String
    public let content: String
    public let semanticContent: String
    public let source: KnowledgeSource
    public let metadata: [String: String]

    public init(
        id: String,
        content: String,
        semanticContent: String? = nil,
        source: KnowledgeSource,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.content = content
        self.semanticContent = semanticContent ?? content
        self.source = source
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case content
        case semanticContent
        case source
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        semanticContent = try container.decodeIfPresent(String.self, forKey: .semanticContent) ?? content
        source = try container.decode(KnowledgeSource.self, forKey: .source)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(semanticContent, forKey: .semanticContent)
        try container.encode(source, forKey: .source)
        try container.encode(metadata, forKey: .metadata)
    }
}

public enum KnowledgeSource: String, Sendable, Hashable, Codable, CaseIterable {
    case capability
    case nlDataset
    case bixbyCommand
    case device
    case automationPattern
    case automationRuleExample
    case automationConditionOperator
    case smartThingsRuleSchema
}

public struct ScoredChunk: Sendable, Hashable {
    public let chunk: DocumentChunk
    public let score: Float

    public init(chunk: DocumentChunk, score: Float) {
        self.chunk = chunk
        self.score = score
    }
}

public struct MetadataFilter: Sendable, Hashable {
    public let source: KnowledgeSource?
    public let requiredTags: [String: String]
    public let requiredTagValues: [String: [String]]

    public init(
        source: KnowledgeSource? = nil,
        requiredTags: [String: String] = [:],
        requiredTagValues: [String: [String]] = [:]
    ) {
        self.source = source
        self.requiredTags = requiredTags
        self.requiredTagValues = requiredTagValues.mapValues { Self.stableUnique($0) }
    }

    public func matches(_ chunk: DocumentChunk) -> Bool {
        if let source, chunk.source != source {
            return false
        }
        for (key, value) in requiredTags where !Self.metadataValue(chunk.metadata[key], matches: value) {
            return false
        }
        for (key, values) in requiredTagValues where !Self.metadataValue(chunk.metadata[key], matchesAny: values) {
            return false
        }
        return true
    }

    private static func metadataValue(_ metadataValue: String?, matches expected: String) -> Bool {
        guard let metadataValue else { return false }
        return metadataTokens(metadataValue).contains(normalized(expected))
    }

    private static func metadataValue(_ metadataValue: String?, matchesAny expected: [String]) -> Bool {
        guard let metadataValue else { return false }
        let tokens = metadataTokens(metadataValue)
        return expected.contains { tokens.contains(normalized($0)) }
    }

    private static func metadataTokens(_ value: String) -> Set<String> {
        Set(
            value
                .split { $0 == "," || $0 == ";" || $0 == "|" || $0 == "/" }
                .map { normalized(String($0)) }
                .filter { !$0.isEmpty }
        )
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let normalized = normalized(value)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(value)
        }
        return result
    }
}
