import Foundation

public struct DocumentChunk: Identifiable, Sendable, Hashable, Codable {
    public let id: String
    public let content: String
    public let source: KnowledgeSource
    public let metadata: [String: String]

    public init(
        id: String,
        content: String,
        source: KnowledgeSource,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.content = content
        self.source = source
        self.metadata = metadata
    }
}

public enum KnowledgeSource: String, Sendable, Hashable, Codable, CaseIterable {
    case capability
    case nlDataset
    case bixbyCommand
    case device
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

    public init(source: KnowledgeSource? = nil, requiredTags: [String: String] = [:]) {
        self.source = source
        self.requiredTags = requiredTags
    }

    public func matches(_ chunk: DocumentChunk) -> Bool {
        if let source, chunk.source != source {
            return false
        }
        for (key, value) in requiredTags where chunk.metadata[key] != value {
            return false
        }
        return true
    }
}
