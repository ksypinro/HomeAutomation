import Foundation
import HomeAutomationCore

public struct KnowledgeIndexingResult: Sendable, Hashable {
    public let indexedChunkCount: Int
    public let sourceCounts: [KnowledgeSource: Int]

    public init(indexedChunkCount: Int, sourceCounts: [KnowledgeSource: Int]) {
        self.indexedChunkCount = indexedChunkCount
        self.sourceCounts = sourceCounts
    }
}

public actor KnowledgeIndexer {
    private let chunker: DocumentChunker
    private let embeddingProvider: any EmbeddingProviding
    private let vectorStore: VectorStore

    public init(
        chunker: DocumentChunker = DocumentChunker(),
        embeddingProvider: any EmbeddingProviding = TFIDFEmbeddingProvider(),
        vectorStore: VectorStore = VectorStore()
    ) {
        self.chunker = chunker
        self.embeddingProvider = embeddingProvider
        self.vectorStore = vectorStore
    }

    public func index(chunks: [DocumentChunk]) async -> KnowledgeIndexingResult {
        await vectorStore.clear()
        if let corpusAwareProvider = embeddingProvider as? any CorpusAwareEmbeddingProviding {
            await corpusAwareProvider.prepareForCorpus(chunks.map(\.content))
        }
        let embeddings = await embeddingProvider.embedBatch(chunks.map(\.content))
        await vectorStore.insertBatch(Array(zip(chunks, embeddings)))

        let sourceCounts = Dictionary(grouping: chunks, by: \.source).mapValues(\.count)
        return KnowledgeIndexingResult(indexedChunkCount: chunks.count, sourceCounts: sourceCounts)
    }

    @discardableResult
    public func indexCanonicalKnowledge(
        deviceRegistry: MockHomeDeviceRegistry = MockHomeDeviceRegistry(),
        includeCatalogDevices: Bool = true
    ) async -> KnowledgeIndexingResult {
        let devices = await deviceRegistry.allDevices()
        let catalogDevices = includeCatalogDevices ? HomeAutomationKnowledgeBase.shared.makeCatalogDeviceRecords() : []
        let deduplicated = Self.deduplicatedDevices(devices + catalogDevices)
        return await index(chunks: chunker.allChunks(devices: deduplicated))
    }

    public func makeRetriever() -> ContextRetriever {
        ContextRetriever(embeddingProvider: embeddingProvider, vectorStore: vectorStore)
    }

    private static func deduplicatedDevices(_ devices: [HomeCandidateRecord]) -> [HomeCandidateRecord] {
        var seen = Set<String>()
        var result: [HomeCandidateRecord] = []
        for device in devices where !seen.contains(device.id) {
            seen.insert(device.id)
            result.append(device)
        }
        return result
    }
}
