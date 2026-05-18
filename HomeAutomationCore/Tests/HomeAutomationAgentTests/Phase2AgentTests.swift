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
    func deterministicIntentKeepsExplicitPowerActionForWarmerByTurningOffAC() {
        let state = AgentTextParser.deterministicState(for: "Make bedroom warmer by turning off the AC")

        #expect(Array(state.intent.topFamilies.prefix(2)) == [.power, .temperature])
        #expect(state.deviceType.deviceTypes == ["airConditioner"])
        #expect(state.slots.rooms == ["bedroom"])
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
    func slotDeterministicFallbackIgnoresFewShotExamplesInPrompt() {
        let prompt = """
        Relevant prior smart-home examples for slot extraction:
        Natural language example please mute the living room television for me. Room living room. Risk low
        Natural language example hey assistant, mute the television in the garage. Room garage. Risk low
        Natural language example run the home routine. Room home. Risk low

        User command:
        Make the living room television volume mute
        """

        let state = AgentTextParser.deterministicState(for: prompt)

        #expect(state.slots.rooms == ["living room"])
        #expect(state.slots.modes.isEmpty)
        #expect(state.deviceType.deviceTypes == ["tv"])
    }

    @Test
    func slotWorkerUsesModelToConfirmAmbiguousDeterministicSlots() async throws {
        let promptCapture = PromptCapture()
        let worker = SlotExtractionAgentWorkerSession(
            modelExtract: { prompt in
                await promptCapture.store(prompt)
                return HomeSlotExtractionResult(
                    rooms: ["living room"],
                    deviceNicknames: [],
                    values: [],
                    modes: [],
                    confidence: 0.9
                )
            },
            foundationModelAvailability: { true }
        )

        let result = try await worker.extractSlots(
            "Turn on the living room and garage television",
            modelPrompt: "few-shot examples plus user command"
        )

        #expect(await promptCapture.value().hasPrefix("few-shot examples plus user command"))
        #expect(result.rooms == ["living room"])
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
            HomeCompactCandidateView(id: "bedroom_sconce", label: "Bedroom Sconce", room: "bedroom", deviceType: "light", shortCapabilities: ["switch"]),
            HomeCompactCandidateView(id: "bedroom_lamp", label: "Bedroom Lamp", room: "bedroom", deviceType: "light", shortCapabilities: ["switch", "switchLevel"]),
            HomeCompactCandidateView(id: "bedroom_strip", label: "Bedroom Strip Light", room: "bedroom", deviceType: "light", shortCapabilities: ["switch", "switchLevel"]),
            HomeCompactCandidateView(id: "bedroom_ceiling", label: "Bedroom Ceiling Light", room: "bedroom", deviceType: "light", shortCapabilities: ["switch"]),
            HomeCompactCandidateView(id: "bedroom_closet", label: "Bedroom Closet Light", room: "bedroom", deviceType: "light", shortCapabilities: ["switch"])
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
    func candidateRankingScopesByRoomAndDeviceTypeForWarmerByTurningOffAC() async throws {
        let devices = try await Self.devices(ids: ["bedroom_ac", "hallway_thermostat", "catalog_airconditioner", "bedroom_lamp"])
        let state = AgentTextParser.deterministicState(for: "Make bedroom warmer by turning off the AC")
        let resolver = HomeCandidateResolverSupport(
            shardSize: 1,
            foundationModelAvailability: { false }
        )

        let result = try await resolver.resolveCandidates(
            userText: "Make bedroom warmer by turning off the AC",
            resolutionState: state,
            candidates: devices.map(\.compactView)
        )

        #expect(result.finalCandidateIDs == ["bedroom_ac"])
        #expect(!result.needsClarification)
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
    func instructionComposerCompactsLargeContext() async throws {
        let base = try await Self.device(id: "bedroom_lamp")
        let candidates = (0..<80).map { index in
            HomeCandidateRecord(
                id: "candidate_\(index)",
                displayName: "Bedroom Lamp Candidate \(index)",
                deviceType: base.deviceType,
                room: base.room,
                capabilities: base.capabilities + ["switchLevel", "colorControl", "thermostatCoolingSetpoint"],
                supportedCommands: base.supportedCommands,
                supportedModes: base.supportedModes,
                currentState: base.currentState,
                metadata: ["note": String(repeating: "large-context ", count: 20)],
                riskLevel: base.riskLevel
            )
        }
        let state = Self.state("Set bedroom lamp to 40 percent")
        let input = HomeFinalResolutionInput(
            rawText: "Set bedroom lamp to 40 percent",
            resolutionState: state,
            hydratedCandidates: candidates,
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: candidates.prefix(5).map(\.id),
                needsClarification: false,
                confidence: 1
            )
        )
        let agent = InstructionComposerAgent()

        let package = try await agent.run(input, context: Self.context())
        let report = try #require(package.contextBudgetReport)

        #expect(report.candidateCount == 80)
        #expect(report.selectedCompactionLevel != "full")
        #expect(report.estimatedInputTokenCount <= 3_200)
    }

    @Test
    func contextBudgeterUsesConservativeTokenEstimatorForStructuredText() {
        let budgeter = FoundationModelContextBudgeter()
        let jsonLikeText = String(
            repeating: #"{"id":"bedroom_lamp","capabilities":["switch","switchLevel"],"state":{"level":"40"}}"#,
            count: 20
        )

        let conservativeEstimate = budgeter.estimateTokenCount(jsonLikeText)
        let oldCharacterHeuristic = Int(ceil(Double(jsonLikeText.count) / 4.0))
        let report = budgeter.report(
            instructionText: "Resolve smart-home command.",
            prompt: jsonLikeText,
            tools: [],
            candidateCount: 1,
            ragCapabilitySectionCount: 0,
            ragExampleSectionCount: 0,
            ragBixbySectionCount: 0,
            selectedCompactionLevel: "test"
        )

        #expect(conservativeEstimate > oldCharacterHeuristic)
        #expect(report.tokenEstimatorSource == .conservativeHeuristic)
    }

    @Test
    func candidatePromptBuilderCompactsLargeCandidatePrompts() {
        let base = HomeCompactCandidateView(
            id: "candidate_0",
            label: "Bedroom Lamp Candidate 0",
            room: "bedroom",
            deviceType: "light",
            shortCapabilities: Array(repeating: "veryLongCapabilityNameForBudgetTesting", count: 24)
        )
        let candidates = (0..<80).map { index in
            HomeCompactCandidateView(
                id: "candidate_\(index)",
                label: "Bedroom Lamp Candidate \(index)",
                room: base.room,
                deviceType: base.deviceType,
                shortCapabilities: base.shortCapabilities
            )
        }
        let builder = CandidateResolutionPromptBuilder()
        let instructionText = "Select the best candidate IDs for the user's smart-home command."

        let package = builder.makeDirectPrompt(
            userText: "Turn on the bedroom lamp",
            resolutionState: Self.state("Turn on the bedroom lamp"),
            candidates: candidates,
            memoryHints: [],
            instructionText: instructionText
        )

        #expect(package.contextBudgetReport.candidateCount == 80)
        #expect(package.contextBudgetReport.selectedCompactionLevel != "full")
        #expect(package.contextBudgetReport.estimatedInputTokenCount <= 3_200)
    }

    @Test
    func defaultToolProviderUsesConsolidatedInspectionTool() async throws {
        let device = try await Self.device(id: "bedroom_lamp")
        let input = Self.finalInput(text: "Set bedroom lamp to 40 percent", device: device)
        let tools = AgentToolProvider(registry: Self.registry()).tools(for: input)
        let names = tools.map(\.name)

        #expect(names.contains("inspectCandidateCommand"))
        #expect(!names.contains("getDeviceCapabilities"))
        #expect(!names.contains("validateCommand"))
        #expect(!names.contains("getSupportedModes"))
    }

    @Test
    func inspectCandidateCommandToolReturnsCappedCanonicalHints() async throws {
        let tool = AgentInspectCandidateCommandTool(registry: Self.registry())

        let output = try await tool.call(
            arguments: .init(
                deviceID: "bedroom_lamp",
                capability: "switchLevel",
                command: "setLevel"
            )
        )

        #expect(output.contains(#""supported":"true""#))
        #expect(output.contains("numericRange"))
        #expect(output.count <= 4_000)
    }

    @Test
    func toolProviderUsesObservedOutputSizeForFutureBudgeting() async throws {
        let store = AgentToolOutputSizeStore()
        let registry = Self.registry()
        let tool = AgentFindDevicesTool(registry: registry, outputSizeStore: store)

        let output = try await tool.call(
            arguments: .init(
                query: "",
                room: nil,
                deviceType: nil,
                limit: 25
            )
        )
        let device = try await Self.device(id: "bedroom_lamp")
        let provider = AgentToolProvider(registry: registry, outputSizeStore: store)
        let tools = provider.tools(for: Self.finalInput(text: "Turn on the bedroom lamp", device: device))

        let estimate = provider.estimatedOutputCharacters(for: tools, candidateCount: 1)

        #expect(estimate >= output.count)
    }

    @Test
    func adapterTrainingExporterBuildsDeterministicJSONLAndEvaluatesHoldout() throws {
        let jsonl = try HomeAdapterTrainingExporter.makeJSONL(limit: 5)
        let examples = HomeAdapterTrainingExporter.makeTrainingExamples(limit: 5)
        let holdout = examples.map {
            HomeAdapterEvaluationCase(
                id: $0.id,
                input: $0.input,
                expectedDraft: $0.expectedDraft,
                tags: [$0.source]
            )
        }
        let result = HomeAdapterTrainingExporter.evaluateHoldout(holdout)

        #expect(jsonl.split(separator: "\n").count == 5)
        #expect(result.isPassing)
        #expect(result.holdoutCoverageTags.contains("generatedDataset"))
    }

    @Test
    func adapterTrainingExporterIncludesNLUTaskRecords() throws {
        let examples = try HomeAdapterTrainingExporter.makeTaskTrainingExamples(
            limit: 12,
            includeDrafts: false,
            includeNLU: true
        )
        let jsonl = try HomeAdapterTrainingExporter.makeTaskJSONL(
            limit: 12,
            includeDrafts: false,
            includeNLU: true
        )
        let tasks = Set(examples.map(\.task))

        #expect(jsonl.split(separator: "\n").count == examples.count)
        #expect(tasks.contains(.languageDetection))
        #expect(tasks.contains(.intentFamilyClassification))
        #expect(tasks.contains(.riskClassification))
    }

    @Test
    func nluWorkerSkipsModelForHighConfidenceDeterministicCommand() async throws {
        let worker = LanguageAgentWorkerSession(foundationModelAvailability: { true })

        let result = try await worker.detectLanguage("Turn on the bedroom lamp")

        #expect(result.languageCode == "en")
        #expect(result.confidence >= 0.90)
    }

    @Test
    func draftGenerationAgentReturnsDraftFromInjectedResolver() async throws {
        let expected = Self.draft(deviceID: "bedroom_lamp", capability: "switch", command: "on")
        let agent = DraftGenerationAgent { _ in expected }

        let draft = try await agent.run(Self.package(), context: Self.context())

        #expect(draft == expected)
    }

    @Test
    func generationModeMapsToGenerationOptions() {
        let greedy = FoundationHomeCommandDraftResolver.generationOptions(for: .greedy)
        let defaultSampling = FoundationHomeCommandDraftResolver.generationOptions(for: .defaultSampling)

        #expect(greedy.sampling == .greedy)
        #expect(defaultSampling.sampling == nil)
    }

    @Test
    func draftResolverReportsFoundationModelFailureKind() async throws {
        let metrics = AgentDraftResolverMetrics()
        let resolver = AgentDraftResolver(
            adapterProvider: HomeAdapterModelProvider(
                adapterSource: HomeStaticAdapterModelSource(configuration: nil)
            ),
            metrics: metrics,
            resolver: ThrowingDraftResolver()
        )

        await #expect(throws: Error.self) {
            _ = try await resolver.resolveDraft(from: Self.package())
        }
        let report = try #require(await metrics.lastReport())

        #expect(report.attempts.count == 2)
        #expect(report.attempts.allSatisfy { $0.errorKind == .contextWindowExceeded })
    }

    @Test
    func draftResolverSkipsRemainingAdapterAttemptsAfterAdapterFailure() async throws {
        let metrics = AgentDraftResolverMetrics()
        let resolver = AgentDraftResolver(
            adapterProvider: HomeAdapterModelProvider(
                adapterSource: HomeStaticAdapterModelSource.named("missing-test-adapter")
            ),
            metrics: metrics,
            resolver: AdapterFailingDraftResolver()
        )

        await #expect(throws: Error.self) {
            _ = try await resolver.resolveDraft(from: Self.package())
        }
        let report = try #require(await metrics.lastReport())

        #expect(report.attempts.map(\.name) == ["base/full", "adapter/full", "base/simplified"])
        #expect(report.attempts.first { $0.name == "adapter/full" }?.errorKind == .adapterUnavailable)
        #expect(!report.attempts.contains { $0.name == "adapter/simplified" })
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
            instructionText: "Resolve a test command.",
            prompt: "Test command",
            tools: [],
            useAdapter: false,
            generationMode: .greedy
        )
    }
}

private struct ThrowingDraftResolver: HomeCommandDraftResolving {
    func resolveDraft(from package: HomeModelInstructionPackage) async throws -> HomeCommandDraft {
        throw ContextWindowTestError()
    }
}

private struct AdapterFailingDraftResolver: HomeCommandDraftResolving {
    func resolveDraft(from package: HomeModelInstructionPackage) async throws -> HomeCommandDraft {
        if package.useAdapter {
            throw HomeAdapterUnavailableError(
                diagnostic: HomeAdapterModelDiagnostic(
                    attempted: true,
                    succeeded: false,
                    errorDescription: "adapter asset missing",
                    errorKind: .adapterUnavailable,
                    adapterSource: "name",
                    adapterIdentifier: "missing-test-adapter",
                    compatibilityVersion: HomeAdapterCompatibilityManifest.current.runtimeVersion
                )
            )
        }
        throw ContextWindowTestError()
    }
}

private struct ContextWindowTestError: LocalizedError {
    var errorDescription: String? {
        "exceeded context window size"
    }
}

private actor PromptCapture {
    private var stored = ""

    func store(_ value: String) {
        stored = value
    }

    func value() -> String {
        stored
    }
}
