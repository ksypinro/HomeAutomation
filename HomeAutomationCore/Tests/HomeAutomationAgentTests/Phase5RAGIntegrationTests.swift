import FoundationModels
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationRAG
import Testing

@Suite
struct Phase5RAGIntegrationTests {
    @Test
    func capabilityKnowledgeUsesRAGAndHydratesCanonicalRegistry() async throws {
        let retriever = await Self.retriever(chunks: [
            DocumentChunk(
                id: "capability:switch",
                content: "lamp light power turn on off",
                source: .capability,
                metadata: ["capabilityId": "switch", "commands": "on,off", "risk": "low"]
            )
        ])
        let agent = CapabilityKnowledgeAgent(contextRetriever: retriever)

        let snippets = try await agent.run(["lamp power"], context: Self.context(text: "lamp power"))

        #expect(snippets.first?.sourceID == "switch")
        #expect(snippets.first?.metadata["source"] == "canonicalCapability")
        #expect(snippets.first?.content.contains("commands: on,off") == true)
    }

    @Test
    func capabilityKnowledgeUsesNLUHintsForStructuredRetrieval() async throws {
        let retriever = await Self.retriever(chunks: [
            DocumentChunk(
                id: "capability:switchLevel",
                content: "switchLevel setLevel brightness",
                semanticContent: "brightness level dim",
                source: .capability,
                metadata: [
                    "capabilityId": "switchLevel",
                    "commands": "setLevel",
                    "risk": "low",
                    "relatedDeviceTypes": "light"
                ]
            ),
            DocumentChunk(
                id: "capability:thermostatCoolingSetpoint",
                content: "thermostat cooling setpoint",
                semanticContent: "temperature cooling",
                source: .capability,
                metadata: [
                    "capabilityId": "thermostatCoolingSetpoint",
                    "commands": "setCoolingSetpoint",
                    "risk": "medium",
                    "relatedDeviceTypes": "thermostat"
                ]
            )
        ])
        let agent = CapabilityKnowledgeAgent(contextRetriever: retriever)

        let output = try await agent.run(
            [],
            context: Self.context(text: "Dim it", intent: [.brightness], deviceTypes: ["light"])
        )

        #expect(output.first?.sourceID == "switchLevel")
        #expect(output.reports.first?.strategy == "hybrid")
        #expect(output.reports.first?.filterHints["deviceTypes"] == ["light"])
    }

    @Test
    func bixbyKnowledgeUsesRAGAndHydratesCanonicalCatalog() async throws {
        let retriever = await Self.retriever(chunks: [
            DocumentChunk(
                id: "bixby:camera-show",
                content: "view camera video stream front porch",
                source: .bixbyCommand,
                metadata: ["capability": "camera", "action": "show", "method": "POST"]
            )
        ])
        let agent = BixbyKnowledgeAgent(contextRetriever: retriever)

        let snippets = try await agent.run(
            BixbyKnowledgeInput(text: "view porch video", deviceNames: ["Front Porch Camera"]),
            context: Self.context(text: "view porch video")
        )

        #expect(snippets.first?.metadata["source"] == "canonicalBixby")
        #expect(snippets.first?.metadata["capability"] == "camera")
        #expect(snippets.first?.metadata["action"] == "show")
    }

    @Test
    func commandExampleUsesRAGSelectedDatasetExample() async throws {
        let example = try #require(HomeAutomationKnowledgeBase.generatedDatasetCommands().first)
        let retriever = await Self.retriever(chunks: [
            DocumentChunk(
                id: "nl:\(example.id)",
                content: "sleeping room nightstand lamp power",
                source: .nlDataset,
                metadata: [
                    "exampleId": example.id,
                    "language": example.language,
                    "deviceType": example.deviceType,
                    "capability": example.capability,
                    "command": example.command
                ]
            )
        ])
        let agent = CommandExampleAgent(contextRetriever: retriever)

        let snippets = try await agent.run(
            CommandExampleInput(text: "sleeping room nightstand lamp", limit: 1),
            context: Self.context(text: "sleeping room nightstand lamp")
        )

        #expect(snippets.first?.sourceID == example.id)
        #expect(snippets.first?.metadata["source"] == "canonicalCommandDataset")
    }

    @Test
    func commandExampleReportsNLUDeviceTypeFilter() async throws {
        let example = try #require(HomeAutomationKnowledgeBase.generatedDatasetCommands().first)
        let retriever = await Self.retriever(chunks: [
            DocumentChunk(
                id: "nl:\(example.id)",
                content: "Natural language example: \(example.text)",
                semanticContent: example.text,
                source: .nlDataset,
                metadata: [
                    "exampleId": example.id,
                    "language": example.language,
                    "deviceType": "light",
                    "capability": example.capability,
                    "command": example.command
                ]
            )
        ])
        let agent = CommandExampleAgent(contextRetriever: retriever)

        let output = try await agent.run(
            CommandExampleInput(text: "dim the lamp", limit: 1),
            context: Self.context(text: "dim the lamp", intent: [.brightness], deviceTypes: ["light"])
        )

        #expect(output.reports.first?.strategy == "semanticOnly")
        #expect(output.reports.first?.filterHints["deviceTypes"] == ["light"])
    }

    @Test
    func retrievalJudgeSkipsRetryWhenModelUnavailable() async throws {
        var context = Self.context(text: "make it cozy", intent: [.routine], deviceTypes: ["light"])
        context.retrievalReports = [
            KnowledgeRetrievalReport(
                agentID: AgentID.capabilityKnowledge.rawValue,
                source: KnowledgeSource.capability.rawValue,
                strategy: "hybrid",
                query: "make it cozy",
                returnedCount: 0,
                acceptedCount: 0,
                averageScore: 0,
                maxScore: 0,
                minScore: 0.01
            )
        ]
        let agent = RetrievalJudgeAgent(contextRetriever: nil, foundationModelAvailability: { false })

        let output = try await agent.run(RetrievalJudgeInput(text: "make it cozy"), context: context)

        #expect(output.snippets.isEmpty)
        #expect(output.reports.first?.strategy == "skippedUnavailable")
    }

    @Test
    func retrievalJudgeRetriesLowQualityCapabilityRetrieval() async throws {
        let retriever = await Self.retriever(chunks: [
            DocumentChunk(
                id: "capability:switch",
                content: "switch on off light",
                semanticContent: "light power switch",
                source: .capability,
                metadata: [
                    "capabilityId": "switch",
                    "commands": "on,off",
                    "risk": "low",
                    "relatedDeviceTypes": "light"
                ]
            )
        ])
        var context = Self.context(text: "turn on the lamp", intent: [.power], deviceTypes: ["light"])
        context.retrievalReports = [
            KnowledgeRetrievalReport(
                agentID: AgentID.capabilityKnowledge.rawValue,
                source: KnowledgeSource.capability.rawValue,
                strategy: "hybrid",
                query: "turn on the lamp",
                returnedCount: 0,
                acceptedCount: 0,
                averageScore: 0,
                maxScore: 0,
                minScore: 0.01
            )
        ]
        let agent = RetrievalJudgeAgent(contextRetriever: retriever, foundationModelAvailability: { true })

        let output = try await agent.run(RetrievalJudgeInput(text: "turn on the lamp"), context: context)

        #expect(output.first?.sourceID == "switch")
        #expect(output.reports.first?.retryCount == 1)
        #expect(output.reports.first?.reformulatedQuery != nil)
    }

    @Test
    func retrievalJudgeCanReportAutomationChunkSources() async throws {
        let retriever = await Self.retriever(chunks: DocumentChunker().smartThingsRuleSchemaChunks())
        var context = Self.context(text: "SmartThings every specific command schema")
        context.retrievalReports = [
            KnowledgeRetrievalReport(
                agentID: AgentID.automationDraft.rawValue,
                source: KnowledgeSource.smartThingsRuleSchema.rawValue,
                strategy: "hybrid",
                query: "SmartThings every specific command schema",
                returnedCount: 0,
                acceptedCount: 0,
                averageScore: 0,
                maxScore: 0,
                minScore: 0.01
            )
        ]
        let agent = RetrievalJudgeAgent(contextRetriever: retriever, foundationModelAvailability: { true })

        let output = try await agent.run(
            RetrievalJudgeInput(text: "SmartThings every specific command schema"),
            context: context
        )

        #expect(output.snippets.first?.metadata["source"] == "automationRAG")
        #expect(output.snippets.first?.metadata["chunkSource"] == KnowledgeSource.smartThingsRuleSchema.rawValue)
        #expect(output.reports.first?.source == KnowledgeSource.smartThingsRuleSchema.rawValue)
    }

    @Test
    func nluAgentPrependsRAGFewShotExamples() async throws {
        let example = try #require(HomeAutomationKnowledgeBase.generatedDatasetCommands().first)
        let retriever = await Self.retriever(chunks: [
            DocumentChunk(
                id: "nl:\(example.id)",
                content: "Natural language example: \(example.text)",
                source: .nlDataset,
                metadata: [
                    "exampleId": example.id,
                    "language": example.language,
                    "deviceType": example.deviceType,
                    "capability": example.capability,
                    "command": example.command
                ]
            )
        ])
        let capture = CapturedInput()
        let agent = LanguageAgent(contextRetriever: retriever) { text in
            await capture.store(text)
            return HomeLanguageDetectionResult(
                languageCode: "en",
                isMixedLanguage: false,
                confidence: 0.9,
                unsupportedLanguageLikely: false
            )
        }

        _ = try await agent.run("turn on the lamp", context: Self.context(text: "turn on the lamp"))
        let seen = await capture.value()

        #expect(seen.contains("Relevant prior smart-home examples for language detection"))
        #expect(seen.contains("User command:"))
        #expect(seen.contains("turn on the lamp"))
    }

    @Test
    func slotExtractionFallbackDoesNotPromoteRoomsFromRAGExamples() async throws {
        let retriever = await Self.retriever(chunks: [
            DocumentChunk(
                id: "nl:living-room-tv",
                content: "Natural language example please mute the living room television for me. Room living room. Risk low",
                semanticContent: "please mute the living room television for me",
                source: .nlDataset,
                metadata: ["exampleId": "living-room-tv", "deviceType": "tv"]
            ),
            DocumentChunk(
                id: "nl:garage-tv",
                content: "Natural language example hey assistant, mute the television in the garage. Room garage. Risk low",
                semanticContent: "mute the television in the garage",
                source: .nlDataset,
                metadata: ["exampleId": "garage-tv", "deviceType": "tv"]
            ),
            DocumentChunk(
                id: "nl:home-routine",
                content: "Natural language example run the home routine. Room home. Risk low",
                semanticContent: "run the home routine",
                source: .nlDataset,
                metadata: ["exampleId": "home-routine", "deviceType": "routine"]
            )
        ])
        let agent = SlotExtractionAgent(
            worker: SlotExtractionAgentWorkerSession(foundationModelAvailability: { false }),
            contextRetriever: retriever
        )

        let result = try await agent.run(
            "Make the living room television volume mute",
            context: Self.context(text: "Make the living room television volume mute")
        )

        #expect(result.rooms == ["living room"])
        #expect(!result.rooms.contains("garage"))
        #expect(!result.rooms.contains("home"))
        #expect(result.modes.isEmpty)
    }


    @Test
    func candidateRetrievalMergesSemanticDeviceMatches() async throws {
        let retriever = await Self.retriever(chunks: [
            DocumentChunk(
                id: "device:bedroom_lamp",
                content: "nightstand sleeping room lamp",
                source: .device,
                metadata: [
                    "deviceId": "bedroom_lamp",
                    "room": "bedroom",
                    "deviceType": "light",
                    "capabilities": "switch,switchLevel"
                ]
            )
        ])
        let agent = CandidateRetrievalAgent(
            registry: MockHomeDeviceRegistry(),
            contextRetriever: retriever
        )
        let text = "Turn on the nightstand"

        let candidates = try await agent.run(
            CandidateRetrievalInput(text: text, state: Self.state(text), limit: 1),
            context: Self.context(text: text)
        )

        #expect(candidates.contains { $0.id == "bedroom_lamp" })
    }

    @Test
    func ruleFallbackUsesRAGDeviceHintsWithoutBypassingValidation() async throws {
        let retriever = await Self.retriever(chunks: [
            DocumentChunk(
                id: "device:bedroom_lamp",
                content: "nightstand sleeping room lamp",
                source: .device,
                metadata: [
                    "deviceId": "bedroom_lamp",
                    "room": "bedroom",
                    "deviceType": "light",
                    "capabilities": "switch,switchLevel"
                ]
            )
        ])
        let resolver = AgentRuleBasedResolver(
            registry: MockHomeDeviceRegistry(),
            contextRetriever: retriever
        )
        let agent = RuleFallbackAgent(resolver: resolver)

        let result = try await agent.run(
            RuleFallbackInput(text: "Turn on the nightstand", executeLowRiskCommands: false),
            context: Self.context(text: "Turn on the nightstand")
        )

        #expect(result.aggregation.finalCandidateIDs == ["bedroom_lamp"])
        #expect(result.draft?.targetDeviceID == "bedroom_lamp")
        #expect(result.draft?.capability == "switch")
    }

    @Test
    func instructionComposerUsesRAGSelectedSlices() async throws {
        let device = try await Self.device(id: "bedroom_lamp")
        let example = try #require(HomeAutomationKnowledgeBase.generatedDatasetCommands().first)
        let retriever = await Self.retriever(chunks: [
            DocumentChunk(
                id: "capability:switch",
                content: "lamp light power on off",
                source: .capability,
                metadata: ["capabilityId": "switch", "commands": "on,off", "risk": "low"]
            ),
            DocumentChunk(
                id: "nl:\(example.id)",
                content: "Natural language example: \(example.text)",
                source: .nlDataset,
                metadata: [
                    "exampleId": example.id,
                    "language": example.language,
                    "deviceType": example.deviceType,
                    "capability": example.capability,
                    "command": example.command
                ]
            )
        ])
        let factory = AgentInstructionSetFactory(
            toolProvider: AgentToolProvider(registry: MockHomeDeviceRegistry()),
            contextRetriever: retriever
        )
        let agent = InstructionComposerAgent(factory: factory)

        let package = try await agent.run(
            Self.finalInput(text: "Turn on the bedroom lamp", device: device),
            context: Self.context(text: "Turn on the bedroom lamp")
        )

        #expect(package.prompt.contains("Selected RAG context:"))
        #expect(package.prompt.contains("Relevant canonical capabilities:"))
        #expect(package.prompt.contains("Similar canonical command examples:"))
    }

    private static func retriever(chunks: [DocumentChunk]) async -> ContextRetriever {
        let indexer = KnowledgeIndexer()
        _ = await indexer.index(chunks: chunks)
        return await indexer.makeRetriever()
    }

    private static func context(text: String) -> ResolutionContext {
        ResolutionContext(request: CommandRequest(text: text, executeLowRiskCommands: false))
    }

    private static func context(
        text: String,
        intent: [HomeAutomationIntentFamily],
        deviceTypes: [String],
        rooms: [String] = []
    ) -> ResolutionContext {
        var context = ResolutionContext(request: CommandRequest(text: text, executeLowRiskCommands: false))
        context.intent = HomeIntentFamilyResult(topFamilies: intent, confidence: 0.95)
        context.deviceType = HomeDeviceTypeResult(deviceTypes: deviceTypes, confidence: 0.95)
        context.slots = HomeSlotExtractionResult(
            rooms: rooms,
            deviceNicknames: [],
            values: [],
            modes: [],
            confidence: 0.9
        )
        return context
    }

    private static func state(_ text: String) -> HomeResolutionState {
        AgentTextParser.deterministicState(for: text, confidence: 1)
    }

    private static func device(id: String) async throws -> HomeCandidateRecord {
        let devices = await MockHomeDeviceRegistry().allDevices()
        return try #require(devices.first { $0.id == id })
    }

    private static func finalInput(text: String, device: HomeCandidateRecord) -> HomeFinalResolutionInput {
        HomeFinalResolutionInput(
            rawText: text,
            resolutionState: Self.state(text),
            hydratedCandidates: [device],
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: [device.id],
                needsClarification: false,
                confidence: 1
            )
        )
    }
}

private actor CapturedInput {
    private var stored = ""

    func store(_ value: String) {
        stored = value
    }

    func value() -> String {
        stored
    }
}
