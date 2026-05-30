import Foundation
import HomeAutomationCore
import HomeAutomationRAG
import Testing

@Suite
struct RAGTests {
    @Test
    func vectorStoreReturnsTopK() async {
        let store = VectorStore()
        await store.insert(
            DocumentChunk(id: "a", content: "light on", source: .device),
            embedding: [1, 0, 0]
        )
        await store.insert(
            DocumentChunk(id: "b", content: "temp set", source: .device),
            embedding: [0, 1, 0]
        )

        let results = await store.query([1, 0, 0], topK: 1)

        #expect(results.map(\.chunk.id) == ["a"])
    }

    @Test
    func vectorStoreAppliesMinimumScore() async {
        let store = VectorStore()
        await store.insert(
            DocumentChunk(id: "a", content: "light on", source: .device),
            embedding: [1, 0]
        )
        await store.insert(
            DocumentChunk(id: "b", content: "weak match", source: .device),
            embedding: [0.1, 0.9]
        )

        let results = await store.query([1, 0], topK: 5, minScore: 0.5)

        #expect(results.map(\.chunk.id) == ["a"])
    }

    @Test
    func similarTextGetsHigherScore() async {
        let embeddingProvider = TFIDFEmbeddingProvider()
        await embeddingProvider.buildVocabulary(from: [
            "turn on light",
            "set temperature",
            "unlock door"
        ])

        let base = await embeddingProvider.embed("turn on the light")
        let similar = await embeddingProvider.embed("switch on lamp")
        let different = await embeddingProvider.embed("set thermostat")

        #expect(cosineSimilarity(base, similar) > cosineSimilarity(base, different))
    }

    @Test
    func tfidfSynonymsIncludeCanonicalKnowledge() {
        let tokens = TFIDFEmbeddingProvider.tokenize("freezing")

        #expect(tokens.contains("temperature"))
        #expect(tokens.contains("thermostat"))
    }

    @Test
    func metadataFilterRestrictsVectorStoreResults() async {
        let store = VectorStore()
        await store.insert(
            DocumentChunk(
                id: "capability:switch",
                content: "switch light on off",
                source: .capability,
                metadata: ["capabilityId": "switch"]
            ),
            embedding: [1, 0]
        )
        await store.insert(
            DocumentChunk(
                id: "device:lamp",
                content: "living room lamp",
                source: .device,
                metadata: ["deviceType": "light"]
            ),
            embedding: [1, 0]
        )

        let results = await store.query(
            [1, 0],
            topK: 5,
            filter: MetadataFilter(source: .capability, requiredTags: ["capabilityId": "switch"])
        )

        #expect(results.map(\.chunk.id) == ["capability:switch"])
    }

    @Test
    func documentChunkerEmitsRequiredCanonicalMetadata() {
        let chunker = DocumentChunker()

        let capability = chunker.capabilityChunks().first { $0.metadata["capabilityId"] == "switch" }
        #expect(capability?.metadata["commands"]?.contains("on") == true)
        #expect(capability?.metadata["risk"]?.isEmpty == false)

        let device = chunker.deviceChunks(
            devices: HomeAutomationKnowledgeBase.shared.makeCatalogDeviceRecords()
        ).first
        #expect(device?.metadata["deviceId"]?.isEmpty == false)
        #expect(device?.metadata["room"] != nil)
        #expect(device?.metadata["deviceType"]?.isEmpty == false)
        #expect(device?.metadata["capabilities"]?.isEmpty == false)

        let bixbyCommand = chunker.bixbyCommandChunks().first
        #expect(bixbyCommand?.metadata["capability"]?.isEmpty == false)
        #expect(bixbyCommand?.metadata["action"]?.isEmpty == false)
        #expect(bixbyCommand?.metadata["method"]?.isEmpty == false)

        let datasetExample = chunker.nlDatasetChunks().first
        #expect(datasetExample?.metadata["exampleId"]?.isEmpty == false)
        #expect(datasetExample?.metadata["language"]?.isEmpty == false)
        #expect(datasetExample?.metadata["deviceType"]?.isEmpty == false)
        #expect(datasetExample?.metadata["capability"]?.isEmpty == false)
        #expect(datasetExample?.metadata["command"]?.isEmpty == false)
        #expect(datasetExample?.semanticContent == HomeAutomationKnowledgeBase.generatedDatasetCommands().first?.text)
        #expect(capability?.metadata["relatedDeviceTypes"]?.contains("light") == true)
    }

    @Test
    func documentChunkerEmitsAutomationKnowledgeSources() {
        let chunks = DocumentChunker().automationChunks()
        let sources = Set(chunks.map(\.source))

        #expect(sources.contains(.automationPattern))
        #expect(sources.contains(.automationRuleExample))
        #expect(sources.contains(.automationConditionOperator))
        #expect(sources.contains(.smartThingsRuleSchema))
        #expect(chunks.allSatisfy { $0.metadata["operation"] == HomeAutomationOperationKind.automationCreation.rawValue })
        #expect(chunks.contains { $0.metadata["conditionOperators"]?.contains("between") == true })
        #expect(chunks.contains { $0.metadata["schemaKeys"]?.contains("specific") == true })
    }

    @Test
    func documentChunkDecodingDefaultsMissingSemanticContent() throws {
        let data = try #require("""
        {"id":"legacy","content":"legacy content","source":"device","metadata":{}}
        """.data(using: .utf8))

        let chunk = try JSONDecoder().decode(DocumentChunk.self, from: data)

        #expect(chunk.semanticContent == "legacy content")
    }

    @Test
    func knowledgeIndexerBuildsRetriever() async {
        let chunks = [
            DocumentChunk(
                id: "capability:switch",
                content: "switch light power on off lamp",
                source: .capability,
                metadata: ["capabilityId": "switch", "commands": "on,off", "risk": "low"]
            ),
            DocumentChunk(
                id: "capability:thermostatCoolingSetpoint",
                content: "thermostat cooling temperature setpoint set cooling",
                source: .capability,
                metadata: [
                    "capabilityId": "thermostatCoolingSetpoint",
                    "commands": "setCoolingSetpoint",
                    "risk": "medium"
                ]
            )
        ]

        let indexer = KnowledgeIndexer()
        let result = await indexer.index(chunks: chunks)
        let retriever = await indexer.makeRetriever()
        let results = await retriever.retrieve("turn lamp on", topK: 1)

        #expect(result.indexedChunkCount == chunks.count)
        #expect(result.sourceCounts[.capability] == chunks.count)
        #expect(results.first?.chunk.id == "capability:switch")
    }

    @Test
    func knowledgeIndexerEmbedsSemanticContent() async {
        let chunks = [
            DocumentChunk(
                id: "nl:dim",
                content: "Natural language example unrelated boilerplate thermostat heating",
                semanticContent: "dim the bedroom lamp",
                source: .nlDataset,
                metadata: ["exampleId": "dim"]
            ),
            DocumentChunk(
                id: "nl:heat",
                content: "Natural language example dim lamp boilerplate",
                semanticContent: "increase thermostat heat",
                source: .nlDataset,
                metadata: ["exampleId": "heat"]
            )
        ]

        let indexer = KnowledgeIndexer()
        _ = await indexer.index(chunks: chunks)
        let retriever = await indexer.makeRetriever()
        let results = await retriever.retrieve("dim lamp", topK: 1)

        #expect(results.first?.chunk.id == "nl:dim")
    }

    @Test
    func bm25FindsExactKeywordMatches() async {
        let index = BM25Index()
        let chunks = [
            DocumentChunk(id: "capability:switchLevel", content: "switchLevel setLevel brightness", source: .capability),
            DocumentChunk(id: "capability:lock", content: "lock unlock door", source: .capability)
        ]
        await index.index(chunks)

        let results = await index.search(terms: ["setLevel"], topK: 1)

        #expect(results.first?.chunk.id == "capability:switchLevel")
    }

    @Test
    func structuredHybridRetrievalUsesBM25AndSemanticEvidence() async {
        let chunks = [
            DocumentChunk(
                id: "capability:switchLevel",
                content: "switchLevel setLevel brightness",
                semanticContent: "brightness level dim",
                source: .capability,
                metadata: ["capabilityId": "switchLevel"]
            ),
            DocumentChunk(
                id: "capability:lock",
                content: "lock unlock door",
                semanticContent: "door lock",
                source: .capability,
                metadata: ["capabilityId": "lock"]
            )
        ]
        let indexer = KnowledgeIndexer()
        _ = await indexer.index(chunks: chunks)
        let retriever = await indexer.makeRetriever()

        let results = await retriever.retrieve(
            StructuredRetrievalQuery(
                rawText: "switchLevel setLevel 75",
                keywordTerms: ["switchLevel", "setLevel"],
                metadataFilter: MetadataFilter(source: .capability),
                strategy: .hybrid(alpha: 0.5),
                topK: 1
            )
        )

        #expect(results.first?.chunk.id == "capability:switchLevel")
    }

    @Test
    func complexAutomationRetrievalUsesAutomationChunksAndMetadataFilter() async {
        let chunks = DocumentChunker().automationChunks() + [
            DocumentChunk(
                id: "nl:direct-switch",
                content: "Natural language example turn on the lamp",
                semanticContent: "turn on the lamp",
                source: .nlDataset,
                metadata: ["exampleId": "direct-switch", "deviceType": "light"]
            )
        ]
        let indexer = KnowledgeIndexer()
        _ = await indexer.index(chunks: chunks)
        let retriever = await indexer.makeRetriever()

        let results = await retriever.retrieve(
            StructuredRetrievalQuery(
                rawText: "Turn on AC every day at 7 AM if bedroom window is closed and motion is detected",
                keywordTerms: ["if", "and", "equals", "deviceAttribute", "everyDay"],
                metadataFilter: MetadataFilter(
                    requiredTags: ["operation": HomeAutomationOperationKind.automationCreation.rawValue]
                ),
                operation: .automationCreation,
                automationConcepts: ["schedule", "compoundCondition", "deviceAttribute"],
                conditionOperators: ["and", "equals"],
                repeatHints: ["everyDay"],
                strategy: .hybrid(alpha: 0.35),
                topK: 4
            )
        )
        let sources = Set(results.map(\.chunk.source))

        #expect(!results.isEmpty)
        #expect(!sources.contains(.nlDataset))
        #expect(sources.contains(.automationRuleExample) || sources.contains(.automationConditionOperator))
    }

    @Test
    func directCommandRAGFilteringIsUnchangedByAutomationChunks() async {
        let chunks = [
            DocumentChunk(
                id: "nl:lamp-power",
                content: "Natural language example turn on the living room lamp",
                semanticContent: "turn on the living room lamp",
                source: .nlDataset,
                metadata: ["exampleId": "lamp-power", "deviceType": "light", "capability": "switch", "command": "on"]
            )
        ] + DocumentChunker().automationChunks()
        let indexer = KnowledgeIndexer()
        _ = await indexer.index(chunks: chunks)
        let retriever = await indexer.makeRetriever()

        let results = await retriever.retrieve(
            "turn on the living room lamp",
            topK: 1,
            filter: MetadataFilter(source: .nlDataset)
        )

        #expect(results.first?.chunk.id == "nl:lamp-power")
    }

    @Test
    func semanticEmbeddingProviderCanDriveRetrievalRanking() async {
        let provider = SemanticEmbeddingProvider { text in
            let normalized = text.lowercased()
            if normalized.contains("semantic-garage") || normalized.contains("car bay") {
                return [1, 0]
            }
            if normalized.contains("lamp") {
                return [0, 1]
            }
            return [0, 0]
        }
        let chunks = [
            DocumentChunk(id: "device:garage", content: "semantic-garage entry opener", source: .device),
            DocumentChunk(id: "device:lamp", content: "lamp light switch", source: .device)
        ]

        let indexer = KnowledgeIndexer(embeddingProvider: provider)
        _ = await indexer.index(chunks: chunks)
        let retriever = await indexer.makeRetriever()
        let results = await retriever.retrieve("open the car bay", topK: 1)

        #expect(results.first?.chunk.id == "device:garage")
    }

    @Test
    func fallbackEmbeddingProviderUsesTFIDFWhenSemanticVectorIsEmpty() async {
        let semantic = SemanticEmbeddingProvider { _ in [] }
        let provider = FallbackEmbeddingProvider(
            primary: semantic,
            fallback: TFIDFEmbeddingProvider()
        )
        let chunks = [
            DocumentChunk(id: "capability:switch", content: "switch light power on off lamp", source: .capability),
            DocumentChunk(id: "capability:temperature", content: "thermostat temperature cooling heat", source: .capability)
        ]

        let indexer = KnowledgeIndexer(embeddingProvider: provider)
        _ = await indexer.index(chunks: chunks)
        let retriever = await indexer.makeRetriever()
        let results = await retriever.retrieve("switch on lamp", topK: 1)

        #expect(results.first?.chunk.id == "capability:switch")
    }

    @Test
    func formattedRetrieverHonorsRequestedSources() async {
        let chunks = [
            DocumentChunk(
                id: "capability:switch",
                content: "switch light power on off lamp",
                source: .capability,
                metadata: ["capabilityId": "switch", "commands": "on,off", "risk": "low"]
            ),
            DocumentChunk(
                id: "device:lamp",
                content: "living room lamp device switch light",
                source: .device,
                metadata: [
                    "deviceId": "lamp",
                    "room": "living room",
                    "deviceType": "light",
                    "capabilities": "switch"
                ]
            )
        ]

        let indexer = KnowledgeIndexer()
        _ = await indexer.index(chunks: chunks)
        let retriever = await indexer.makeRetriever()
        let formatted = await retriever.retrieveFormatted("lamp", topK: 1, sources: [.device])

        #expect(formatted.contains("[device]"))
        #expect(formatted.contains("device:lamp"))
        #expect(!formatted.contains("[capability]"))
    }

    // MARK: - Cache persistence tests

    @Test
    func vectorIndexCacheSavesAndLoadsMatchingVersion() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_rag_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let cache = VectorIndexCache(fileURL: tempURL)
        let entry = VectorStoreEntry(
            chunk: DocumentChunk(id: "test:switch", content: "switch on off", source: .capability),
            embedding: [0.1, 0.9, 0.3]
        )
        let snapshot = VectorIndexSnapshot(version: "v1", entries: [entry], tfidfVocabulary: nil)

        await cache.save(snapshot)
        let loaded = await cache.load(expectedVersion: "v1")

        #expect(loaded != nil)
        #expect(loaded?.version == "v1")
        #expect(loaded?.entries.count == 1)
        #expect(loaded?.entries.first?.chunk.id == "test:switch")
        #expect(loaded?.entries.first?.embedding == [0.1, 0.9, 0.3])
    }

    @Test
    func vectorIndexCacheRejectsStaleVersion() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_rag_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let cache = VectorIndexCache(fileURL: tempURL)
        let snapshot = VectorIndexSnapshot(version: "v1", entries: [], tfidfVocabulary: nil)
        await cache.save(snapshot)

        let loaded = await cache.load(expectedVersion: "v2-different")
        #expect(loaded == nil)
    }

    @Test
    func vectorIndexCacheReturnsNilWhenFileAbsent() async {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent_\(UUID().uuidString).json")
        let cache = VectorIndexCache(fileURL: tempURL)
        let loaded = await cache.load(expectedVersion: "any")
        #expect(loaded == nil)
    }

    @Test
    func vectorStoreSnapshotRoundTrips() async {
        let store = VectorStore()
        let chunk = DocumentChunk(id: "cap:switch", content: "switch on off", source: .capability)
        await store.insert(chunk, embedding: [0.5, 0.5])

        let entries = await store.snapshot()
        let restored = VectorStore()
        await restored.restore(from: entries)

        let results = await restored.query([0.5, 0.5], topK: 1)
        #expect(results.first?.chunk.id == "cap:switch")
        #expect(await restored.count() == 1)
    }

    @Test
    func tfidfVocabularySnapshotRoundTrips() async {
        let provider = TFIDFEmbeddingProvider()
        await provider.prepareForCorpus(["switch on light", "lock the door", "set thermostat"])

        let snap = await provider.vocabularySnapshot()
        #expect(snap.documentCount == 3)
        #expect(!snap.vocabulary.isEmpty)

        let restored = TFIDFEmbeddingProvider()
        await restored.restoreVocabulary(from: snap)
        let restoredSnap = await restored.vocabularySnapshot()
        #expect(restoredSnap == snap)
    }

    @Test
    func fallbackEmbeddingProviderPersistsNestedTFIDFVocabulary() async throws {
        let provider = FallbackEmbeddingProvider(
            primary: SemanticEmbeddingProvider { _ in [] },
            fallback: TFIDFEmbeddingProvider()
        )
        await provider.prepareForCorpus(["switch on light", "lock the door", "set thermostat"])

        let snapshot = try #require(await provider.tfidfVocabularySnapshot())
        let restored = FallbackEmbeddingProvider(
            primary: SemanticEmbeddingProvider { _ in [] },
            fallback: TFIDFEmbeddingProvider()
        )
        let restoredVocabulary = await restored.restoreTFIDFVocabulary(from: snapshot)
        let embedding = await restored.embed("switch on lamp")

        #expect(restoredVocabulary)
        #expect(!embedding.isEmpty)
    }

    @Test
    func knowledgeIndexerRestoresFallbackTFIDFVocabularyFromCache() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_rag_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let cache = VectorIndexCache(fileURL: tempURL)
        let firstProvider = FallbackEmbeddingProvider(
            primary: SemanticEmbeddingProvider { _ in [] },
            fallback: TFIDFEmbeddingProvider()
        )
        let firstIndexer = KnowledgeIndexer(embeddingProvider: firstProvider, cache: cache)
        let firstResult = await firstIndexer.indexCanonicalKnowledge(
            deviceRegistry: MockHomeDeviceRegistry(),
            includeCatalogDevices: false
        )
        await cache.waitForPendingSave()

        let secondProvider = FallbackEmbeddingProvider(
            primary: SemanticEmbeddingProvider { _ in [] },
            fallback: TFIDFEmbeddingProvider()
        )
        let secondIndexer = KnowledgeIndexer(embeddingProvider: secondProvider, cache: cache)
        let secondResult = await secondIndexer.indexCanonicalKnowledge(
            deviceRegistry: MockHomeDeviceRegistry(),
            includeCatalogDevices: false
        )
        let retriever = await secondIndexer.makeRetriever()
        let results = await retriever.retrieve("bedroom lamp", topK: 1)

        #expect(!firstResult.restoredFromCache)
        #expect(secondResult.restoredFromCache)
        #expect((results.first?.score ?? 0) > 0)
    }

    @Test
    func ragIndexVersionChangesWithKnowledgeBaseContent() {
        let v1 = RAGIndexVersion.compute(
            knowledgeBaseSchemaVersion: "1.0",
            bixbyCommandCount: 200,
            datasetCommandCount: 500,
            automationKnowledgeCount: 10,
            deviceCount: 20
        )
        let v2 = RAGIndexVersion.compute(
            knowledgeBaseSchemaVersion: "1.0",
            bixbyCommandCount: 200,
            datasetCommandCount: 500,
            automationKnowledgeCount: 10,
            deviceCount: 21  // one more device
        )
        let v3 = RAGIndexVersion.compute(
            knowledgeBaseSchemaVersion: "2.0",  // schema bump
            bixbyCommandCount: 200,
            datasetCommandCount: 500,
            automationKnowledgeCount: 10,
            deviceCount: 20
        )
        let v4 = RAGIndexVersion.compute(
            knowledgeBaseSchemaVersion: "1.0",
            bixbyCommandCount: 200,
            datasetCommandCount: 500,
            automationKnowledgeCount: 11,
            deviceCount: 20
        )
        #expect(v1 != v2)
        #expect(v1 != v3)
        #expect(v1 != v4)
        #expect(v2 != v3)
        #expect(v1.contains(RAGIndexVersion.semanticIndexVersion))
    }
}
