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
}
