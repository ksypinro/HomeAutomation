import Testing
import Foundation
import FoundationModels
import HomeAutomationCore
@testable import HomeAutomationResolver

@Suite
struct LegacyResolverTests {
    @Test
    func resolvesLowRiskCommandWithoutFoundationModels() async throws {
        let registry = MockHomeDeviceRegistry()
        let resolver = LegacyHomeCommandResolver(
            registry: registry,
            foundationModelAvailability: { false }
        )

        let result = try await resolver.resolve(
            "Turn on the living room ceiling light",
            executeLowRiskCommands: true
        )

        switch result.resolution {
        case .executed(let plan, let updatedDevice):
            #expect(plan.steps.first?.deviceID == "living_room_ceiling_light")
            #expect(plan.steps.first?.capability == "switch")
            #expect(plan.steps.first?.command == "on")
            #expect(updatedDevice.currentState["switch"] == "on")
        default:
            Issue.record("Expected legacy to execute a low-risk light command without Foundation Models.")
        }
    }

    @Test
    func keepsHighRiskCommandBehindConfirmationWithoutFoundationModels() async throws {
        let resolver = LegacyHomeCommandResolver(
            foundationModelAvailability: { false }
        )

        let result = try await resolver.resolve(
            "Unlock the front door",
            executeLowRiskCommands: true
        )

        switch result.resolution {
        case .requiresConfirmation(let draft):
            #expect(draft.targetDeviceID == "front_door_lock")
            #expect(draft.capability == "lock")
            #expect(draft.command == "unlock")
        default:
            Issue.record("Expected legacy to require confirmation for unlocking the front door.")
        }
    }

    @Test
    func resolvesRelativeCoolingToValidSetpointWithoutFoundationModels() async throws {
        let resolver = LegacyHomeCommandResolver(
            foundationModelAvailability: { false }
        )

        let result = try await resolver.resolve(
            "Make the bedroom AC cooler by 2 degrees",
            executeLowRiskCommands: false
        )

        switch result.resolution {
        case .readyToExecute(let plan):
            let step = try #require(plan.steps.last)
            #expect(plan.steps.first?.type == "readAttribute")
            #expect(plan.steps.first?.attribute == "coolingSetpoint")
            #expect(step.deviceID == "bedroom_ac")
            #expect(step.capability == "thermostatCoolingSetpoint")
            #expect(step.command == "setCoolingSetpoint")
            #expect(step.valueFormula == "current - 2")
        default:
            Issue.record("Expected legacy to map relative cooling to a formula-based cooling setpoint.")
        }
    }

    @Test
    func resolvesRelativeBrightnessToFormulaPlanWithoutFoundationModels() async throws {
        let resolver = LegacyHomeCommandResolver(
            foundationModelAvailability: { false }
        )

        let result = try await resolver.resolve(
            "Increase the bedroom lamp by 10 percent",
            executeLowRiskCommands: false
        )

        switch result.resolution {
        case .readyToExecute(let plan):
            let readStep = try #require(plan.steps.first)
            let commandStep = try #require(plan.steps.last)
            #expect(readStep.type == "readAttribute")
            #expect(readStep.attribute == "level")
            #expect(commandStep.deviceID == "bedroom_lamp")
            #expect(commandStep.capability == "switchLevel")
            #expect(commandStep.command == "setLevel")
            #expect(commandStep.valueFormula == "current + 10")
        default:
            Issue.record("Expected relative brightness to map to a formula-based setter plan.")
        }
    }

    @Test
    func executesFormulaPlanAgainstCurrentState() async throws {
        let registry = MockHomeDeviceRegistry()
        let plan = HomeAutomationExecutionPlan(
            steps: [
                HomeAutomationExecutionStep(
                    type: "readAttribute",
                    deviceID: "bedroom_ac",
                    deviceName: "Bedroom AC",
                    capability: "thermostatCoolingSetpoint",
                    command: "getStatus",
                    attribute: "coolingSetpoint"
                ),
                HomeAutomationExecutionStep(
                    type: "command",
                    deviceID: "bedroom_ac",
                    deviceName: "Bedroom AC",
                    capability: "thermostatCoolingSetpoint",
                    command: "setCoolingSetpoint",
                    attribute: "coolingSetpoint",
                    valueFormula: "current - 2"
                )
            ],
            requiresConfirmation: false
        )

        let updatedDevice = try await registry.executeLowRiskPlan(plan)

        #expect(updatedDevice.currentState["coolingSetpoint"] == "22")
    }

    @Test
    func malformedFormulaDoesNotMutateDeviceState() async throws {
        let registry = MockHomeDeviceRegistry()
        let plan = HomeAutomationExecutionPlan(
            steps: [
                HomeAutomationExecutionStep(
                    type: "command",
                    deviceID: "bedroom_ac",
                    deviceName: "Bedroom AC",
                    capability: "thermostatCoolingSetpoint",
                    command: "setCoolingSetpoint",
                    attribute: "coolingSetpoint",
                    valueFormula: "current / 2"
                )
            ],
            requiresConfirmation: false
        )

        await #expect(throws: FoundationLabCoreError.self) {
            _ = try await registry.executeLowRiskPlan(plan)
        }

        let devices = await registry.allDevices()
        let device = try #require(devices.first { $0.id == "bedroom_ac" })
        #expect(device.currentState["coolingSetpoint"] == "24")
    }

    @Test
    func smallCandidateSetUsesDirectSelection() async throws {
        let registry = MockHomeDeviceRegistry()
        let devices = await registry.allDevices()
        let candidates = devices
            .filter { ["living_room_ceiling_light", "bedroom_lamp"].contains($0.id) }
            .map(\.compactView)
        let metrics = LegacyCandidateResolverMetrics()
        let resolver = LegacyCandidateResolver(metrics: metrics)
        let state = LegacyTextParser.deterministicState(for: "Turn on the bedroom lamp", confidence: 1)

        let aggregation = try await resolver.resolveCandidates(
            userText: "Turn on the bedroom lamp",
            resolutionState: state,
            candidates: candidates
        )

        #expect(await metrics.lastStrategy == "direct")
        #expect(aggregation.finalCandidateIDs == ["bedroom_lamp"])
    }

    @Test
    func toolsReturnDeviceStateWithoutThrowing() async throws {
        let tool = LegacyGetDeviceStateTool(registry: MockHomeDeviceRegistry())
        let output = try await tool.call(arguments: .init(deviceID: "bedroom_lamp"))

        #expect(output.contains("level"))
        #expect(output.contains("35"))
    }

    @Test
    func toolsReturnActionableValidationAndCapabilityHints() async throws {
        let registry = MockHomeDeviceRegistry()
        let validateTool = LegacyValidateCommandTool(registry: registry)
        let valid = try await validateTool.call(
            arguments: .init(
                deviceID: "bedroom_lamp",
                capability: "switchLevel",
                command: "setLevel"
            )
        )
        let invalid = try await validateTool.call(
            arguments: .init(
                deviceID: "bedroom_lamp",
                capability: "switchLevel",
                command: "setCoolingSetpoint"
            )
        )
        let capabilityTool = LegacyGetCapabilitiesTool(registry: registry)
        let capabilities = try await capabilityTool.call(arguments: .init(deviceID: "bedroom_lamp"))

        #expect(valid.contains(#""valid":true"#))
        #expect(valid.contains(#""risk":"low""#))
        #expect(invalid.contains("supportedCommands"))
        #expect(capabilities.contains("attributes"))
        #expect(capabilities.contains("numericRange"))
    }

    @Test
    func bixbyFallbackMapsCatalogVoiceIntent() async throws {
        let registry = MockHomeDeviceRegistry()
        let devices = await registry.allDevices()
        let matches = LegacyBixbyFallbackMapper().matches(
            text: "Show me the Front Porch Camera",
            devices: devices
        )
        let match = try #require(matches.first)

        #expect(match.device.id == "front_porch_camera")
        #expect(match.sourceCapability == "camera")
        #expect(match.sourceAction == "show")
        #expect(match.draft.intent == .getStatus)
        #expect(match.draft.capability == "videoStream")
        #expect(match.draft.command == "getStatus")
    }

    @Test
    func ruleBasedFallbackUsesBixbyCatalogWhenKeywordRulesDoNotMatch() async throws {
        let resolver = LegacyHomeCommandResolver(
            foundationModelAvailability: { false }
        )

        let result = try await resolver.resolve(
            "Show me the Front Porch Camera",
            executeLowRiskCommands: false
        )

        switch result.resolution {
        case .requiresConfirmation(let draft):
            #expect(draft.targetDeviceID == "front_porch_camera")
            #expect(draft.capability == "videoStream")
            #expect(draft.command == "getStatus")
        default:
            Issue.record("Expected legacy to use the Bixby catalog fallback for camera show intent.")
        }
    }

    @Test(arguments: [
        "enciende la lampara del dormitorio",
        "allume la lampe de la chambre",
        "リビングのライトつけて",
        "বেডরুম লাইট চালু"
    ])
    func multilingualFallbackMapsCommonLightCommands(command: String) async throws {
        let resolver = LegacyHomeCommandResolver(
            foundationModelAvailability: { false }
        )

        let result = try await resolver.resolve(command, executeLowRiskCommands: false)

        switch result.resolution {
        case .readyToExecute(let plan):
            #expect(plan.steps.first?.capability == "switch")
            #expect(plan.steps.first?.command == "on")
        default:
            Issue.record("Expected multilingual fallback to map a common light command.")
        }
    }

    @Test
    func exposesMetricsJSONAfterResolution() async throws {
        let resolver = LegacyHomeCommandResolver(
            foundationModelAvailability: { false }
        )

        _ = try await resolver.resolve("Turn on the bedroom lamp", executeLowRiskCommands: false)
        let metricsJSON = try #require(await resolver.lastMetricsJSON())

        #expect(metricsJSON.contains("usedRuleBasedFallback"))
        #expect(metricsJSON.contains("fallbackReason"))
        #expect(metricsJSON.contains("readyToExecute"))
        #expect(metricsJSON.contains("emittedEventCount"))
        #expect(metricsJSON.contains("totalDuration"))
    }

    @Test
    func streamsLegacyPipelineEventsAndResult() async throws {
        let resolver = LegacyHomeCommandResolver(
            foundationModelAvailability: { false }
        )

        var eventIDs: [String] = []
        var result: HomeAutomationResolverResult?
        for try await update in resolver.resolveStream(
            "Turn on the bedroom lamp",
            executeLowRiskCommands: false
        ) {
            switch update {
            case .event(let event):
                eventIDs.append(event.id)
                #expect(event.stage?.rawValue == event.id)
            case .result(let output):
                result = output
            }
        }

        #expect(eventIDs.contains("input"))
        #expect(eventIDs.contains("ruleBasedPrecheck"))
        #expect(eventIDs.contains("outcome"))
        #expect(result?.aggregation.finalCandidateIDs == ["bedroom_lamp"])
    }

    @Test
    func languageRulesPreserveInternalEnglishSchemaValues() {
        let input = Self.finalInput(
            rawText: "enciende bedroom light",
            state: Self.resolutionState(
                rawText: "enciende bedroom light",
                language: HomeLanguageDetectionResult(
                    languageCode: "mixed_bn_en",
                    isMixedLanguage: true,
                    confidence: 0.9,
                    unsupportedLanguageLikely: true
                )
            )
        )

        let rules = LegacyInstructionSetFactory.languageRules(for: input)

        #expect(rules.contains("English/internal schema"))
        #expect(rules.contains("mix languages"))
        #expect(rules.contains("ask for clarification"))
    }

    @Test
    func draftResolverRetriesLowConfidenceDraftsAndReportsAttempts() async throws {
        let lowDraft = HomeCommandDraft(
            intent: .turnOn,
            targetDeviceID: "bedroom_lamp",
            capability: "switch",
            command: "on",
            needsClarification: false,
            requiresConfirmation: false,
            confidence: 0.42
        )
        let highDraft = HomeCommandDraft(
            intent: .setValue,
            targetDeviceID: "bedroom_lamp",
            capability: "switchLevel",
            command: "setLevel",
            parameters: [
                HomeResolvedParameter(name: "value", value: "40", numericValue: 40, unit: "percent", confidence: 1)
            ],
            needsClarification: false,
            requiresConfirmation: false,
            confidence: 0.91
        )
        let metrics = LegacyDraftResolverMetrics()
        let resolver = LegacyDraftResolver(
            confidenceThreshold: 0.70,
            metrics: metrics,
            resolver: SequencedDraftResolver(drafts: [lowDraft, highDraft])
        )

        let package = Self.instructionPackage()
        let draft = try await resolver.resolveDraft(from: package)
        let report = try #require(await metrics.lastReport())

        #expect(draft == highDraft)
        #expect(report.attemptCount == 2)
        #expect(report.bestDraftAttempt == "adapter/full")
        #expect(report.attemptSummaries.first?.contains("low-confidence") == true)
        #expect(report.attemptSummaries.last?.contains("selected") == true)
    }

    @Test
    func partialWorkerFailureKeepsOtherWorkerOutputs() async throws {
        let layer = LegacyPartialSafeWorkerSessionLayer(
            workerOverrides: LegacyPartialWorkerOverrides(
                detectLanguage: { _ in
                    throw FoundationLabCoreError.invalidRequest("language worker failed")
                },
                classifyDomain: { _ in
                    HomeDomainClassificationResult(domain: .homeAutomation, confidence: 0.99)
                },
                classifyIntentFamily: { _ in
                    HomeIntentFamilyResult(topFamilies: [.brightness], confidence: 0.97)
                },
                classifyDeviceType: { _ in
                    HomeDeviceTypeResult(deviceTypes: ["light"], confidence: 0.96)
                },
                extractSlots: { _ in
                    HomeSlotExtractionResult(
                        rooms: ["bedroom"],
                        deviceNicknames: ["lamp"],
                        values: [
                            HomeExtractedSlot(name: "value", rawValue: "40", numericValue: 40, unit: "percent", confidence: 0.95)
                        ],
                        modes: [],
                        confidence: 0.95
                    )
                },
                classifyRisk: { _ in
                    HomeRiskClassificationResult(
                        riskLevel: .low,
                        requiresConfirmation: false,
                        reason: "test",
                        confidence: 0.94
                    )
                }
            ),
            foundationModelAvailability: { true }
        )

        let state = try await layer.analyze("Set the bedroom lamp to 40 percent")

        #expect(state.language.confidence == 0.42)
        #expect(state.domain.confidence == 0.99)
        #expect(state.intent.topFamilies == [.brightness])
        #expect(state.slots.values.first?.numericValue == 40)
    }

    @Test
    func fmPathMetricsRecordToolsAndDraftAttemptsWithoutLiveFoundationModels() async throws {
        let draft = HomeCommandDraft(
            intent: .setValue,
            targetDeviceID: "bedroom_lamp",
            capability: "switchLevel",
            command: "setLevel",
            parameters: [
                HomeResolvedParameter(name: "value", value: "40", numericValue: 40, unit: "percent", confidence: 1)
            ],
            needsClarification: false,
            requiresConfirmation: false,
            confidence: 0.92
        )
        let resolver = LegacyHomeCommandResolver(
            workerLayer: StaticWorkerLayer(
                state: Self.resolutionState(
                    rawText: "bedroom lamp illumination setting 40",
                    language: HomeLanguageDetectionResult(
                        languageCode: "en",
                        isMixedLanguage: false,
                        confidence: 1,
                        unsupportedLanguageLikely: false
                    )
                )
            ),
            draftResolver: LegacyDraftResolver(
                metrics: LegacyDraftResolverMetrics(),
                resolver: SequencedDraftResolver(drafts: [draft])
            ),
            foundationModelAvailability: { true }
        )

        _ = try await resolver.resolve(
            "bedroom lamp illumination setting 40",
            executeLowRiskCommands: false
        )
        let metricsJSON = try #require(await resolver.lastMetricsJSON())

        #expect(metricsJSON.contains("usedFoundationModels"))
        #expect(metricsJSON.contains("selectedToolNames"))
        #expect(metricsJSON.contains("getDeviceCapabilities"))
    }

    @Test
    func exportsAdapterTrainingJSONL() {
        let jsonl = LegacyAdapterTrainingExporter.makeJSONL(limit: 2)

        #expect(jsonl.contains("\"prompt\""))
        #expect(jsonl.split(separator: "\n").count == 2)
    }

    private static func instructionPackage() -> HomeModelInstructionPackage {
        HomeModelInstructionPackage(
            instructions: Instructions("Resolve a test command."),
            prompt: "Test command",
            tools: [],
            useAdapter: false,
            generationMode: .greedy
        )
    }

    private static func resolutionState(
        rawText: String,
        language: HomeLanguageDetectionResult = HomeLanguageDetectionResult(
            languageCode: "en",
            isMixedLanguage: false,
            confidence: 1,
            unsupportedLanguageLikely: false
        )
    ) -> HomeResolutionState {
        HomeResolutionState(
            rawText: rawText,
            language: language,
            domain: HomeDomainClassificationResult(domain: .homeAutomation, confidence: 1),
            intent: HomeIntentFamilyResult(topFamilies: [.brightness], confidence: 1),
            deviceType: HomeDeviceTypeResult(deviceTypes: ["light"], confidence: 1),
            slots: HomeSlotExtractionResult(
                rooms: ["bedroom"],
                deviceNicknames: ["lamp"],
                values: [
                    HomeExtractedSlot(name: "value", rawValue: "40", numericValue: 40, unit: "percent", confidence: 1)
                ],
                modes: [],
                confidence: 1
            ),
            risk: HomeRiskClassificationResult(
                riskLevel: .low,
                requiresConfirmation: false,
                reason: "test",
                confidence: 1
            )
        )
    }

    private static func finalInput(
        rawText: String,
        state: HomeResolutionState
    ) -> HomeFinalResolutionInput {
        HomeFinalResolutionInput(
            rawText: rawText,
            resolutionState: state,
            hydratedCandidates: [],
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: [],
                needsClarification: false,
                confidence: 1
            )
        )
    }
}

private struct StaticWorkerLayer: HomeWorkerSessionAnalyzing {
    let state: HomeResolutionState

    func analyze(_ text: String) async throws -> HomeResolutionState {
        state
    }
}

private struct SequencedDraftResolver: HomeCommandDraftResolving {
    private let queue: DraftQueue

    init(drafts: [HomeCommandDraft]) {
        self.queue = DraftQueue(drafts: drafts)
    }

    func resolveDraft(from package: HomeModelInstructionPackage) async throws -> HomeCommandDraft {
        try await queue.next()
    }
}

private actor DraftQueue {
    private var drafts: [HomeCommandDraft]

    init(drafts: [HomeCommandDraft]) {
        self.drafts = drafts
    }

    func next() throws -> HomeCommandDraft {
        guard !drafts.isEmpty else {
            throw FoundationLabCoreError.invalidRequest("No more draft responses")
        }
        return drafts.removeFirst()
    }
}
