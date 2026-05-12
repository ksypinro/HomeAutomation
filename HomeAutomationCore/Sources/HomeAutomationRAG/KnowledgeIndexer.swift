import Foundation
import HomeAutomationCore

public struct KnowledgeIndexingResult: Sendable, Hashable {
    public let indexedChunkCount: Int
    public let sourceCounts: [KnowledgeSource: Int]
    /// `true` when the index was loaded from disk rather than rebuilt from scratch.
    public let restoredFromCache: Bool

    public init(
        indexedChunkCount: Int,
        sourceCounts: [KnowledgeSource: Int],
        restoredFromCache: Bool = false
    ) {
        self.indexedChunkCount = indexedChunkCount
        self.sourceCounts = sourceCounts
        self.restoredFromCache = restoredFromCache
    }
}

/// Builds and optionally persists the RAG vector index.
///
/// ## Cold-start optimisation
///
/// `KnowledgeIndexer` accepts an optional `VectorIndexCache`. When a cache is
/// provided, `indexCanonicalKnowledge` uses a two-step strategy:
///
/// 1. **Cache hit** — If a snapshot with a matching version exists on disk the
///    `VectorStore` and `TFIDFEmbeddingProvider` are restored from it in ~10 ms
///    instead of rebuilding all embeddings from scratch (~1-2 s).
/// 2. **Cache miss** — The index is rebuilt normally and the new snapshot is
///    saved to disk for the next launch.
///
/// The version string is computed by `RAGIndexVersion.compute(...)` and encodes
/// the knowledge-base schema version, Bixby command count, dataset example count,
/// and device count. Any change to those numbers invalidates the cache automatically.
public actor KnowledgeIndexer {
    private let chunker: DocumentChunker
    private let embeddingProvider: any EmbeddingProviding
    private let vectorStore: VectorStore
    private let bm25Index: BM25Index
    private let cache: VectorIndexCache?

    public init(
        chunker: DocumentChunker = DocumentChunker(),
        embeddingProvider: any EmbeddingProviding = TFIDFEmbeddingProvider(),
        vectorStore: VectorStore = VectorStore(),
        bm25Index: BM25Index = BM25Index(),
        cache: VectorIndexCache? = nil
    ) {
        self.chunker = chunker
        self.embeddingProvider = embeddingProvider
        self.vectorStore = vectorStore
        self.bm25Index = bm25Index
        self.cache = cache
    }

    /// Indexes an arbitrary list of document chunks.
    ///
    /// This path always rebuilds embeddings and does **not** consult the cache —
    /// it is used by tests and custom indexing pipelines.
    public func index(chunks: [DocumentChunk]) async -> KnowledgeIndexingResult {
        await vectorStore.clear()
        await bm25Index.index(chunks)
        if let corpusAwareProvider = embeddingProvider as? any CorpusAwareEmbeddingProviding {
            await corpusAwareProvider.prepareForCorpus(chunks.map(\.semanticContent))
        }
        let embeddings = await embeddingProvider.embedBatch(chunks.map(\.semanticContent))
        await vectorStore.insertBatch(Array(zip(chunks, embeddings)))

        let sourceCounts = Dictionary(grouping: chunks, by: \.source).mapValues(\.count)
        return KnowledgeIndexingResult(
            indexedChunkCount: chunks.count,
            sourceCounts: sourceCounts,
            restoredFromCache: false
        )
    }

    /// Indexes the canonical knowledge base, using the disk cache when available.
    ///
    /// - Parameters:
    ///   - deviceRegistry: Registry whose devices are included in the index.
    ///   - includeCatalogDevices: When `true`, catalog devices from the knowledge
    ///     base are merged with registry devices before indexing.
    /// - Returns: An indexing result indicating whether the index was restored from
    ///   cache or rebuilt from scratch.
    @discardableResult
    public func indexCanonicalKnowledge(
        deviceRegistry: MockHomeDeviceRegistry = MockHomeDeviceRegistry(),
        includeCatalogDevices: Bool = true
    ) async -> KnowledgeIndexingResult {
        let devices = await deviceRegistry.allDevices()
        let catalogDevices = includeCatalogDevices
            ? HomeAutomationKnowledgeBase.shared.makeCatalogDeviceRecords()
            : []
        let deduplicated = Self.deduplicatedDevices(devices + catalogDevices)

        // Compute the version tag for this knowledge-base state.
        let version = RAGIndexVersion.compute(
            knowledgeBaseSchemaVersion: HomeAutomationKnowledgeBase.shared.schemaVersion,
            bixbyCommandCount: HomeBixbyCommandCatalog.commands.count,
            datasetCommandCount: HomeAutomationKnowledgeBase.generatedDatasetCommandCount(),
            deviceCount: deduplicated.count
        )

        // --- Attempt cache restore ---
        if let cache, let snapshot = await cache.load(expectedVersion: version) {
            let restored = await restoreFromSnapshot(snapshot)
            if restored {
                let sourceCounts = Dictionary(
                    grouping: snapshot.entries.map(\.chunk),
                    by: \.source
                ).mapValues(\.count)
                return KnowledgeIndexingResult(
                    indexedChunkCount: snapshot.entries.count,
                    sourceCounts: sourceCounts,
                    restoredFromCache: true
                )
            }
        }

        // --- Full rebuild ---
        let chunks = chunker.allChunks(devices: deduplicated)
        let result = await index(chunks: chunks)

        // Persist to cache for next launch.
        if let cache {
            let entries = await vectorStore.snapshot()
            let tfidfSnapshot = await Self.tfidfVocabularySnapshot(from: embeddingProvider)
            let indexSnapshot = VectorIndexSnapshot(
                version: version,
                entries: entries,
                tfidfVocabulary: tfidfSnapshot
            )
            await cache.saveInBackground(indexSnapshot)
        }

        return result
    }

    public func makeRetriever() -> ContextRetriever {
        ContextRetriever(embeddingProvider: embeddingProvider, vectorStore: vectorStore, bm25Index: bm25Index)
    }

    // MARK: - Private helpers

    private func restoreFromSnapshot(_ snapshot: VectorIndexSnapshot) async -> Bool {
        guard !snapshot.entries.isEmpty else { return false }
        await vectorStore.clear()
        await vectorStore.restore(from: snapshot.entries)
        await bm25Index.index(snapshot.entries.map(\.chunk))
        if let vocabSnapshot = snapshot.tfidfVocabulary {
            let restoredVocabulary = await Self.restoreTFIDFVocabulary(
                vocabSnapshot,
                into: embeddingProvider
            )
            guard restoredVocabulary else {
                await vectorStore.clear()
                await bm25Index.clear()
                return false
            }
        }
        return true
    }

    private static func tfidfVocabularySnapshot(from provider: any EmbeddingProviding) async -> TFIDFVocabularySnapshot? {
        guard let provider = provider as? any TFIDFVocabularyPersisting else { return nil }
        return await provider.tfidfVocabularySnapshot()
    }

    private static func restoreTFIDFVocabulary(
        _ snapshot: TFIDFVocabularySnapshot,
        into provider: any EmbeddingProviding
    ) async -> Bool {
        guard let provider = provider as? any TFIDFVocabularyPersisting else { return false }
        return await provider.restoreTFIDFVocabulary(from: snapshot)
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
