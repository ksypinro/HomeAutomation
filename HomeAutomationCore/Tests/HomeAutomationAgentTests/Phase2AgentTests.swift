import Foundation
import FoundationModels
import HomeAutomationAgents
import HomeAutomationCore
import Testing

@Suite
struct Phase2AgentTests {
    @Test
    func languageAgentDetectsEnglish() async throws {
        let agent = LanguageAgent { _ in
            HomeLanguageDetectionResult(languageCode: "en", isMixedLanguage: false, confidence: 0.95, unsupportedLanguageLikely: false)
        }

        let result = try await agent.run("turn on light", context: Self.context())

        #expect(result.languageCode == "en")
    }

    @Test
    func domainAgentClassifiesHomeAutomation() async throws {
        let agent = DomainAgent { _ in
            HomeDomainClassificationResult(domain: .homeAutomation, confidence: 0.9)
        }

        let result = try await agent.run("turn on light", context: Self.context())

        #expect(result.domain == .homeAutomation)
    }

    @Test
    func intentFamilyAgentReturnsPowerFamily() async throws {
        let agent = IntentFamilyAgent { _ in
            HomeIntentFamilyResult(topFamilies: [.power], confidence: 0.9)
        }

        let result = try await agent.run("turn on light", context: Self.context())

        #expect(result.topFamilies == [.power])
    }

    @Test
    func deviceTypeAgentReturnsLightType() async throws {
        let agent = DeviceTypeAgent { _ in
            HomeDeviceTypeResult(deviceTypes: ["light"], confidence: 0.9)
        }

        let result = try await agent.run("turn on light", context: Self.context())

        #expect(result.deviceTypes == ["light"])
    }

    @Test
    func slotExtractionAgentReturnsRoom() async throws {
        let agent = SlotExtractionAgent { _ in
            HomeSlotExtractionResult(
                rooms: ["bedroom"],
                deviceNicknames: ["lamp"],
                values: [],
                modes: [],
                confidence: 0.9
            )
        }

        let result = try await agent.run("turn on bedroom lamp", context: Self.context())

        #expect(result.rooms == ["bedroom"])
    }

    @Test
    func riskClassificationAgentReturnsHighRisk() async throws {
        let agent = RiskClassificationAgent { _ in
            HomeRiskClassificationResult(riskLevel: .high, requiresConfirmation: true, reason: "lock", confidence: 0.9)
        }

        let result = try await agent.run("unlock the door", context: Self.context())

        #expect(result.requiresConfirmation)
    }

    @Test
    func capabilityKnowledgeAgentHydratesCanonicalCapability() async throws {
        let agent = CapabilityKnowledgeAgent()

        let snippets = try await agent.run(["switch"], context: Self.context())

        #expect(snippets.first?.metadata["source"] == "canonicalCapability")
        #expect(snippets.first?.content.contains("commands: on,off") == true)
    }

    @Test
    func bixbyKnowledgeAgentReturnsMatchingCatalogCommand() async throws {
        let agent = BixbyKnowledgeAgent()

        let snippets = try await agent.run(
            BixbyKnowledgeInput(text: "Show me the Front Porch Camera", deviceNames: ["Front Porch Camera"]),
            context: Self.context()
        )

        #expect(snippets.contains { $0.metadata["source"] == "canonicalBixby" })
    }

    @Test
    func commandExampleAgentReturnsDatasetSnippet() async throws {
        let agent = CommandExampleAgent()

        let snippets = try await agent.run(CommandExampleInput(text: "turn on bedroom light", limit: 1), context: Self.context())

        #expect(snippets.count == 1)
        #expect(snippets.first?.metadata["source"] == "canonicalCommandDataset")
    }

    @Test
    func candidateRetrievalAgentReturnsRegistryCandidates() async throws {
        let agent = CandidateRetrievalAgent()
        let state = Self.state("Turn on the bedroom lamp")

        let candidates = try await agent.run(
            CandidateRetrievalInput(text: "Turn on the bedroom lamp", state: state),
            context: Self.context()
        )

        #expect(candidates.contains { $0.id == "bedroom_lamp" })
    }

    @Test
    func candidateRankingAgentSelectsBestCandidate() async throws {
        let devices = try await Self.devices(ids: ["living_room_ceiling_light", "bedroom_lamp"])
        let state = Self.state("Turn on the bedroom lamp")
        let agent = CandidateRankingAgent()

        let result = try await agent.run(
            CandidateRankingInput(text: "Turn on the bedroom lamp", state: state, candidates: devices.map(\.compactView)),
            context: Self.context()
        )

        #expect(result.finalCandidateIDs == ["bedroom_lamp"])
    }

    @Test
    func candidateRankingUsesParallelShardMetricsForLargeSets() async throws {
        let candidates = [
            HomeCompactCandidateView(id: "entry_sensor", label: "Entry Sensor", room: "hallway", deviceType: "sensor", shortCapabilities: ["contactSensor"]),
            HomeCompactCandidateView(id: "water_sensor", label: "Water Sensor", room: "utility", deviceType: "sensor", shortCapabilities: ["waterSensor"]),
            HomeCompactCandidateView(id: "bedroom_lamp", label: "Bedroom Lamp", room: "bedroom", deviceType: "light", shortCapabilities: ["switch", "switchLevel"]),
            HomeCompactCandidateView(id: "air_monitor", label: "Air Monitor", room: "living room", deviceType: "sensor", shortCapabilities: ["airQualityMeasurement"]),
            HomeCompactCandidateView(id: "washer", label: "Washer", room: "laundry", deviceType: "washer", shortCapabilities: ["washerOperatingState"])
        ]
        let metrics = HomeCandidateResolverMetrics()
        let resolver = HomeCandidateResolverSupport(
            shardSize: 2,
            metrics: metrics,
            foundationModelAvailability: { false }
        )
        let state = Self.state("Turn on the bedroom lamp")

        let result = try await resolver.resolveCandidates(
            userText: "Turn on the bedroom lamp",
            resolutionState: state,
            candidates: candidates
        )

        #expect(result.finalCandidateIDs == ["bedroom_lamp"])
        #expect(await metrics.lastStrategy == "parallel-sharded")
        #expect(await metrics.lastCandidateCount == 5)
        #expect(await metrics.lastShardCount == 3)
        #expect(await metrics.lastParallelTaskCount == 3)
        #expect(await metrics.lastShardWinnerCount == 1)
    }

    @Test
    func candidateShardAgentSelectsWithinShard() async throws {
        let devices = try await Self.devices(ids: ["living_room_ceiling_light", "bedroom_lamp"])
        let state = Self.state("Turn on the bedroom lamp")
        let agent = CandidateShardAgent()

        let result = try await agent.run(
            CandidateShardInput(text: "Turn on the bedroom lamp", state: state, shard: devices.map(\.compactView)),
            context: Self.context()
        )

        #expect(result.selectedCandidateIDs == ["bedroom_lamp"])
    }

    @Test
    func candidateHydrationAgentReturnsSelectedRecords() async throws {
        let agent = CandidateHydrationAgent()

        let devices = try await agent.run(CandidateHydrationInput(candidateIDs: ["bedroom_lamp"]), context: Self.context())

        #expect(devices.map(\.id) == ["bedroom_lamp"])
    }

    @Test
    func instructionComposerAgentBuildsPackage() async throws {
        let device = try await Self.device(id: "bedroom_lamp")
        let input = Self.finalInput(text: "Set bedroom lamp to 40 percent", device: device)
        let agent = InstructionComposerAgent()

        let package = try await agent.run(input, context: Self.context())

        #expect(package.prompt.contains("User command: Set bedroom lamp to 40 percent"))
        #expect(!package.tools.isEmpty)
    }

    @Test
    func draftGenerationAgentReturnsDraftFromInjectedResolver() async throws {
        let expected = Self.draft(deviceID: "bedroom_lamp", capability: "switch", command: "on")
        let agent = DraftGenerationAgent { _ in expected }

        let draft = try await agent.run(Self.package(), context: Self.context())

        #expect(draft == expected)
    }

    @Test
    func draftRepairAgentReturnsReportFromInjectedRepair() async throws {
        let expected = Self.draft(deviceID: "bedroom_lamp", capability: "switch", command: "on")
        let report = AgentDraftResolutionReport(
            attempts: [
                AgentDraftAttemptReport(
                    name: "stub",
                    useAdapter: false,
                    simplifiedPrompt: false,
                    outcome: "success",
                    confidence: 0.99,
                    selected: true,
                    errorDescription: nil
                )
            ],
            selectedAttemptName: "stub"
        )
        let agent = DraftRepairAgent { _ in
            AgentDraftResolutionOutput(draft: expected, report: report)
        }

        let output = try await agent.run(Self.package(), context: Self.context())

        #expect(output.draft == expected)
        #expect(output.report.bestDraftAttempt == "stub")
    }

    @Test
    func safetyValidationAgentReturnsReadyPlanForValidDraft() async throws {
        let device = try await Self.device(id: "bedroom_lamp")
        let input = Self.finalInput(text: "Turn on the bedroom lamp", device: device)
        let draft = Self.draft(deviceID: device.id, capability: "switch", command: "on")
        let agent = SafetyValidationAgent()

        let resolution = try await agent.run(SafetyValidationInput(draft: draft, finalInput: input), context: Self.context())

        if case .readyToExecute(let plan) = resolution {
            #expect(plan.steps.first?.command == "on")
        } else {
            Issue.record("Expected ready-to-execute resolution.")
        }
    }

    @Test
    func parameterValidationAgentAcceptsValidNumericParameter() async throws {
        let device = try await Self.device(id: "bedroom_lamp")
        let agent = ParameterValidationAgent()

        let valid = try await agent.run(
            ParameterValidationInput(
                parameters: [HomeResolvedParameter(name: "value", numericValue: 40, unit: "percent", confidence: 1)],
                capability: "switchLevel",
                command: "setLevel",
                device: device
            ),
            context: Self.context()
        )

        #expect(valid)
    }

    @Test
    func confirmationPolicyAgentRequiresConfirmationForUnlock() async throws {
        let agent = ConfirmationPolicyAgent()

        let requiresConfirmation = try await agent.run(
            ConfirmationPolicyInput(
                intent: .unlock,
                capability: "lock",
                deviceType: "lock",
                candidateRisk: .high,
                command: "unlock"
            ),
            context: Self.context()
        )

        #expect(requiresConfirmation)
    }

    @Test
    func executionPlanningAgentCreatesCommandPlan() async throws {
        let device = try await Self.device(id: "bedroom_lamp")
        let draft = Self.draft(deviceID: device.id, capability: "switch", command: "on")
        let agent = ExecutionPlanningAgent()

        let plan = try await agent.run(ExecutionPlanningInput(draft: draft, device: device), context: Self.context())

        #expect(plan.steps.first?.type == "command")
        #expect(plan.steps.first?.deviceID == "bedroom_lamp")
    }

    @Test
    func mockExecutionAgentMutatesLowRiskDevice() async throws {
        let plan = HomeAutomationExecutionPlan(
            steps: [
                HomeAutomationExecutionStep(
                    type: "command",
                    deviceID: "bedroom_lamp",
                    deviceName: "Bedroom Lamp",
                    capability: "switch",
                    command: "on"
                )
            ],
            requiresConfirmation: false
        )
        let agent = MockExecutionAgent(registry: MockHomeDeviceRegistry())

        let device = try await agent.run(plan, context: Self.context())

        #expect(device.currentState["switch"] == "on")
    }

    @Test
    func ruleFallbackAgentResolvesPowerCommand() async throws {
        let agent = RuleFallbackAgent()

        let result = try await agent.run(
            RuleFallbackInput(text: "Turn on the bedroom lamp", executeLowRiskCommands: false),
            context: Self.context()
        )

        #expect(result.aggregation.finalCandidateIDs == ["bedroom_lamp"])
    }

    @Test
    func bixbyFallbackAgentMapsCatalogIntent() async throws {
        let devices = try await Self.devices(ids: ["front_porch_camera"])
        let agent = BixbyFallbackAgent()

        let matches = try await agent.run(
            BixbyFallbackInput(text: "Show me the Front Porch Camera", devices: devices),
            context: Self.context()
        )

        #expect(matches.first?.device.id == "front_porch_camera")
        #expect(matches.first?.draft.command == "getStatus")
    }

    @Test
    func unsupportedCommandAgentReturnsUnsupportedResolution() async throws {
        let agent = UnsupportedCommandAgent()

        let resolution = try await agent.run("write a poem", context: Self.context())

        if case .unsupported(let reason) = resolution {
            #expect(reason == "This command is not supported.")
        } else {
            Issue.record("Expected unsupported resolution.")
        }
    }

    @Test
    func clarificationAgentReturnsClarificationResolution() async throws {
        let agent = ClarificationAgent()

        let resolution = try await agent.run("Which lamp?", context: Self.context())

        if case .needsClarification(let question) = resolution {
            #expect(question == "Which lamp?")
        } else {
            Issue.record("Expected clarification resolution.")
        }
    }

    @Test
    func resultSummaryAgentFormatsDisplaySummary() async throws {
        let agent = ResultSummaryAgent()

        let summary = try await agent.run(.needsClarification("Which lamp?"), context: Self.context())

        #expect(summary == "Which lamp?")
    }

    private static func context(text: String = "turn on the light") -> ResolutionContext {
        ResolutionContext(request: CommandRequest(text: text, executeLowRiskCommands: false))
    }

    private static func state(_ text: String) -> HomeResolutionState {
        AgentTextParser.deterministicState(for: text, confidence: 1)
    }

    private static func registry() -> MockHomeDeviceRegistry {
        MockHomeDeviceRegistry()
    }

    private static func devices(ids: [String]) async throws -> [HomeCandidateRecord] {
        let devices = await registry().allDevices()
        let idSet = Set(ids)
        return devices.filter { idSet.contains($0.id) }
    }

    private static func device(id: String) async throws -> HomeCandidateRecord {
        let devices = try await devices(ids: [id])
        return try #require(devices.first)
    }

    private static func finalInput(text: String, device: HomeCandidateRecord) -> HomeFinalResolutionInput {
        let state = Self.state(text)
        return HomeFinalResolutionInput(
            rawText: text,
            resolutionState: state,
            hydratedCandidates: [device],
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: [device.id],
                needsClarification: false,
                confidence: 1
            )
        )
    }

    private static func draft(deviceID: String, capability: String, command: String) -> HomeCommandDraft {
        HomeCommandDraft(
            intent: command == "on" ? .turnOn : .setValue,
            targetDeviceID: deviceID,
            capability: capability,
            command: command,
            needsClarification: false,
            requiresConfirmation: false,
            confidence: 1
        )
    }

    private static func package() -> HomeModelInstructionPackage {
        HomeModelInstructionPackage(
            instructions: Instructions("Resolve a test command."),
            prompt: "Test command",
            tools: [],
            useAdapter: false,
            generationMode: .greedy
        )
    }
}
