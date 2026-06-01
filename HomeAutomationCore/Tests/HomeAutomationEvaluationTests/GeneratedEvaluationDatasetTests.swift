import Foundation
import HomeAutomationCore
import HomeAutomationEvaluation
import Testing

@Suite
struct GeneratedEvaluationDatasetTests {
    @Test
    func generatedDatasetSchemaRoundTrips() throws {
        let manifest = EvaluationDatasetManifest(
            name: "unit",
            version: "1.0.0",
            generatedAt: "2026-06-01T00:00:00Z",
            generatorVersion: "test",
            fixtureCount: 0,
            caseCount: 0,
            commandsPerFixture: 0,
            generationMode: "template",
            randomSeed: 1,
            validationStatus: "passed"
        )
        let contract = ExpectedTraceContract(
            id: "case.trace",
            caseID: "case",
            requiredAgents: [ExpectedAgentContract(agentID: "semanticNLU")],
            requiredTools: [ExpectedToolContract(toolID: "findDeviceCandidates")]
        )
        let dataset = GeneratedEvaluationDataset(
            manifest: manifest,
            traceContracts: [contract],
            metricsContracts: [ExpectedMetricsContract(id: "case.metrics", caseID: "case")]
        )

        let data = try JSONEncoder().encode(dataset)
        let decoded = try JSONDecoder().decode(GeneratedEvaluationDataset.self, from: data)

        #expect(decoded.manifest.name == "unit")
        #expect(decoded.traceContracts.first?.requireAgentTraceIdentity == true)
        #expect(decoded.traceContracts.first?.requiredTools.first?.requireCallerAgentTraceIDs == true)
    }

    @Test
    func datasetJSONLRoundTripsCases() async throws {
        let fixture = try #require(EvaluationFixtureGenerator().generateSeedFixtures().first)
        let cases = try await EvaluationCommandGenerator().generateCases(
            for: [fixture],
            commandsPerFixture: 5
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("generated-eval-jsonl-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("cases.jsonl")

        try DatasetJSONL.write(cases, to: url)
        let decoded = try DatasetJSONL.read(GeneratedEvaluationCase.self, from: url)

        #expect(decoded == cases)
    }

    @Test
    func builtInSeedManifestLoads() throws {
        let manifest = try EvaluationDatasetResourceLoader().loadBuiltInManifest(named: "seed-v1")

        #expect(manifest.name == "seed-v1")
        #expect(manifest.generationMode == "template")
    }

    @Test
    func builtInSeedDatasetLoadsCommittedResources() throws {
        let dataset = try EvaluationDatasetResourceLoader().loadBuiltInDataset(named: "seed-v1")

        #expect(dataset.manifest.name == "seed-v1")
        #expect(dataset.fixtures.count == 10)
        #expect(dataset.cases.count == 1_000)
        #expect(dataset.traceContracts.count == 1_000)
        #expect(dataset.metricsContracts.count == 1_000)
        #expect(dataset.manifest.validationStatus == "passed")
    }

    @Test
    func fixtureGeneratorProducesValidSeedFixtures() {
        let fixtures = EvaluationFixtureGenerator().generateSeedFixtures()
        let issues = DatasetValidator().validate(fixtures: fixtures)
        let errors = issues.filter { $0.severity == "error" }
        let numbered = fixtures.first { $0.id == "numbered-bulbs" }
        let names = Set(numbered?.devices.map(\.displayName) ?? [])

        #expect(fixtures.count == 10)
        #expect(errors.isEmpty, "Fixture validation errors: \(errors)")
        #expect(names.isSuperset(of: ["Bulb 1", "Bulb2", "Bulb 3", "Lamp 01", "Kitchen Light 2"]))
    }

    @Test
    func fixtureGeneratorProducesValidFullScaleFixtures() {
        let fixtures = EvaluationFixtureGenerator().generateFullFixtures()
        let issues = DatasetValidator().validate(fixtures: fixtures)
        let errors = issues.filter { $0.severity == "error" }
        let fixtureIDs = Set(fixtures.map(\.id))
        let variant = fixtures.first { $0.id == "simple-home-variant-02" }
        let numberedVariant = fixtures.first { $0.id == "numbered-bulbs-variant-02" }

        #expect(fixtures.count == 100)
        #expect(fixtureIDs.count == 100)
        #expect(errors.isEmpty, "Full fixture validation errors: \(errors)")
        #expect(variant?.devices.first?.id.hasPrefix("simple_home_variant_02_") == true)
        #expect(numberedVariant?.devices.map(\.displayName).contains("Bulb 1") == true)
        #expect(numberedVariant?.devices.map(\.displayName).contains("Bulb2") == true)
        #expect(numberedVariant?.devices.map(\.displayName).contains("Bulb 3") == true)
    }

    @Test
    func commandGeneratorProducesValidatedExpectedOutputs() async throws {
        let fixtures = EvaluationFixtureGenerator().generateSeedFixtures()
        let cases = try await EvaluationCommandGenerator().generateCases(
            for: fixtures,
            commandsPerFixture: 100
        )
        let issues = DatasetValidator().validate(cases: cases, fixtures: fixtures)
        let errors = issues.filter { $0.severity == "error" }

        #expect(cases.count == 1_000)
        #expect(errors.isEmpty, "Case validation errors: \(errors)")
        #expect(cases.contains { $0.fixtureID == "numbered-bulbs" && $0.input.localizedCaseInsensitiveContains("Bulb") })
        #expect(cases.allSatisfy { !$0.traceContractID.isEmpty && !$0.metricsContractID.isEmpty })
    }

    @Test
    func commandGeneratorProducesFullScaleDatasetShape() async throws {
        let dataset = try await EvaluationCommandGenerator().generateFullDataset()
        let fixtureIssues = DatasetValidator().validate(fixtures: dataset.fixtures)
        let caseIssues = DatasetValidator().validate(cases: dataset.cases, fixtures: dataset.fixtures)
        let errors = (fixtureIssues + caseIssues).filter { $0.severity == "error" }

        #expect(dataset.manifest.name == "full-v1")
        #expect(dataset.manifest.fixtureCount == 100)
        #expect(dataset.manifest.caseCount == 10_000)
        #expect(dataset.manifest.commandsPerFixture == 100)
        #expect(dataset.fixtures.count == 100)
        #expect(dataset.cases.count == 10_000)
        #expect(dataset.traceContracts.count == 10_000)
        #expect(dataset.metricsContracts.count == 10_000)
        #expect(dataset.manifest.validationStatus == "passed")
        #expect(errors.isEmpty, "Full dataset validation errors: \(errors.prefix(10))")
    }

    @Test
    func externalGeneratedDatasetRoundTripsFromDirectory() async throws {
        let dataset = try await EvaluationCommandGenerator().generateDataset(
            name: "external-round-trip",
            fixtureLimit: 2,
            commandsPerFixture: 3
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("generated-eval-external-\(UUID().uuidString)", isDirectory: true)

        try EvaluationDatasetWriter().write(dataset, to: directory)
        let decoded = try EvaluationDatasetResourceLoader().loadExternalDataset(from: directory)

        #expect(decoded.manifest.name == "external-round-trip")
        #expect(decoded.fixtures.count == 2)
        #expect(decoded.cases.count == 6)
        #expect(decoded.traceContracts.count == 6)
        #expect(decoded.metricsContracts.count == 6)
    }

    @Test
    func templateProviderDoesNotOwnLabels() async throws {
        let fixture = try #require(EvaluationFixtureGenerator().generateSeedFixtures().first)
        let spec = try #require(EvaluationCommandGenerator().canonicalSpecs(for: fixture).first)
        let phrases = try await TemplateCommandParaphraseProvider().paraphrases(for: spec, count: 6)

        #expect(phrases.count == 6)
        #expect(spec.expected.targetDeviceID != nil || spec.expected.allowedOutcome == .unsupported)
        #expect(Set(phrases).count == phrases.count)
    }

    @Test
    func foundationModelProviderRejectsSemanticDriftFromResponder() async throws {
        let fixture = try #require(EvaluationFixtureGenerator().generateSeedFixtures().first)
        let spec = try #require(EvaluationCommandGenerator().canonicalSpecs(for: fixture).first {
            $0.expected.command == "on" && $0.deviceDisplayName == "Living Room Light"
        })
        let responder = SequencedParaphraseResponder(outputs: [
            .success([
                "Turn off Living Room Light",
                "Turn on Bedroom Lamp",
                "Switch on Living Room Light",
                "Can you turn the living room light on?"
            ])
        ])
        let provider = FoundationModelCommandParaphraseProvider(
            responder: responder,
            foundationModelAvailability: { true },
            maxAttempts: 1
        )

        let phrases = try await provider.paraphrases(for: spec, count: 2)

        #expect(phrases == ["Switch on Living Room Light", "Can you turn the living room light on?"])
    }

    @Test
    func foundationModelProviderRetriesInvalidStructuredOutput() async throws {
        let fixture = try #require(EvaluationFixtureGenerator().generateSeedFixtures().first)
        let spec = try #require(EvaluationCommandGenerator().canonicalSpecs(for: fixture).first {
            $0.expected.command == "on" && $0.deviceDisplayName == "Living Room Light"
        })
        let responder = SequencedParaphraseResponder(outputs: [
            .failure(CommandParaphraseProviderError.invalidModelJSON("not an array")),
            .success(["Turn on Living Room Light"])
        ])
        let provider = FoundationModelCommandParaphraseProvider(
            responder: responder,
            foundationModelAvailability: { true },
            maxAttempts: 2
        )

        let phrases = try await provider.paraphrases(for: spec, count: 1)
        let calls = await responder.callCount

        #expect(phrases == ["Turn on Living Room Light"])
        #expect(calls == 2)
    }

    @Test
    func foundationModelProviderFailsWhenLiveModelUnavailable() async throws {
        let fixture = try #require(EvaluationFixtureGenerator().generateSeedFixtures().first)
        let spec = try #require(EvaluationCommandGenerator().canonicalSpecs(for: fixture).first)
        let provider = FoundationModelCommandParaphraseProvider(
            responder: SequencedParaphraseResponder(outputs: [.success([])]),
            foundationModelAvailability: { false }
        )

        do {
            _ = try await provider.paraphrases(for: spec, count: 1)
            Issue.record("Expected liveModelUnavailable error")
        } catch CommandParaphraseProviderError.liveModelUnavailable {
            return
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func codexProviderRejectsSemanticDriftFromRunner() async throws {
        let fixture = try #require(EvaluationFixtureGenerator().generateSeedFixtures().first)
        let spec = try #require(EvaluationCommandGenerator().canonicalSpecs(for: fixture).first {
            $0.expected.command == "on" && $0.deviceDisplayName == "Living Room Light"
        })
        let runner = SequencedCodexParaphraseRunner(outputs: [
            .success([
                "Turn off Living Room Light",
                "Turn on Bedroom Lamp",
                "Switch on Living Room Light",
                "Can you turn the living room light on?"
            ])
        ])
        let provider = CodexCLICommandParaphraseProvider(
            runner: runner,
            maxAttempts: 1
        )

        let phrases = try await provider.paraphrases(for: spec, count: 2)

        #expect(phrases == ["Switch on Living Room Light", "Can you turn the living room light on?"])
    }

    @Test
    func codexProviderRetriesInvalidStructuredOutput() async throws {
        let fixture = try #require(EvaluationFixtureGenerator().generateSeedFixtures().first)
        let spec = try #require(EvaluationCommandGenerator().canonicalSpecs(for: fixture).first {
            $0.expected.command == "on" && $0.deviceDisplayName == "Living Room Light"
        })
        let runner = SequencedCodexParaphraseRunner(outputs: [
            .failure(CommandParaphraseProviderError.codexCLIInvalidOutput("not json")),
            .success(["Turn on Living Room Light"])
        ])
        let provider = CodexCLICommandParaphraseProvider(
            runner: runner,
            maxAttempts: 2
        )

        let phrases = try await provider.paraphrases(for: spec, count: 1)
        let calls = await runner.callCount

        #expect(phrases == ["Turn on Living Room Light"])
        #expect(calls == 2)
    }

    @Test
    func generatedDatasetManifestRecordsCodexGenerationMode() async throws {
        let generator = EvaluationCommandGenerator(
            paraphraseProvider: TemplateCommandParaphraseProvider(),
            generationMode: .codex
        )
        let dataset = try await generator.generateDataset(
            name: "codex-mode-label-test",
            fixtureLimit: 1,
            commandsPerFixture: 2
        )

        #expect(dataset.manifest.generationMode == EvaluationCommandGenerationMode.codex.rawValue)
    }

    @Test
    func generatedDatasetManifestRecordsFoundationModelGenerationMode() async throws {
        let generator = EvaluationCommandGenerator(
            paraphraseProvider: TemplateCommandParaphraseProvider(),
            generationMode: .foundationModel
        )
        let dataset = try await generator.generateDataset(
            name: "live-mode-label-test",
            fixtureLimit: 1,
            commandsPerFixture: 2
        )

        #expect(dataset.manifest.generationMode == EvaluationCommandGenerationMode.foundationModel.rawValue)
    }

    @Test
    func contractFactoriesProduceTraceAndMetricContracts() async throws {
        let fixture = try #require(EvaluationFixtureGenerator().generateSeedFixtures().first)
        let cases = try await EvaluationCommandGenerator().generateCases(
            for: [fixture],
            commandsPerFixture: 20
        )
        let traceContracts = ExpectedTraceContractFactory().makeContracts(for: cases)
        let metricsContracts = ExpectedMetricsContractFactory().makeContracts(for: cases)
        let direct = try #require(traceContracts.first { contract in
            contract.graphPathAlternatives.contains(["direct-command-graph"])
        })
        let automation = try #require(traceContracts.first { contract in
            contract.requiredGraphs.contains("automation-creation-graph")
        })

        #expect(traceContracts.count == cases.count)
        #expect(metricsContracts.count == cases.count)
        #expect(direct.requiredAgents.contains { $0.agentID == "operationDetection" })
        #expect(direct.agentPathAlternatives.contains { path in
            path.contains { $0.agentID == "semanticNLU" } &&
                path.contains { $0.agentID == "candidateRanking" }
        })
        #expect(direct.agentPathAlternatives.contains { path in
            path.contains { $0.agentID == "ruleFallback" }
        })
        #expect(automation.requiredAgents.contains { $0.agentID == "automationComponentFanOut" })
        #expect(automation.requiredComponents.contains { $0.componentKind == "trigger" && $0.componentID == "t1" })
        #expect(automation.requiredComponents.contains { $0.componentKind == "action" && $0.componentID == "a1" })
    }

    @Test
    func traceNormalizerAliasesIdentityAndStripsVolatileIDs() {
        let events = syntheticTraceEvents(
            agentSessionID: "raw-agent-session-1",
            toolSessionID: "raw-tool-session-1",
            toolCallID: "raw-tool-call-1"
        )
        let trace = TraceNormalizer().normalize(events, caseID: "case-1")
        let agentSpan = trace.spans.first { $0.eventType == "agent.input" }
        let toolCheck = trace.toolIdentityChecks.values.first

        #expect(agentSpan?.agentSessionAlias == "agent-session:semanticNLU:1")
        #expect(agentSpan?.agentSessionAlias?.contains("raw-agent-session") == false)
        #expect(toolCheck?.toolID == "findDeviceCandidates")
        #expect(toolCheck?.hasInputEvent == true)
        #expect(toolCheck?.hasOutputEvent == true)
        #expect(toolCheck?.missingCallerAgentTraceID == false)
        #expect(trace.selectedDeviceIDs.contains("bedroom_ac"))
        #expect(trace.capability == "switch")
        #expect(trace.command == "on")
    }

    @Test
    func traceComparatorPassesValidContractAndFailsMissingAgent() {
        let trace = TraceNormalizer().normalize(syntheticTraceEvents(), caseID: "case-1")
        let passing = ExpectedTraceContract(
            id: "case-1.trace",
            caseID: "case-1",
            requiredGraphs: ["direct-command-graph"],
            requiredAgents: [ExpectedAgentContract(agentID: "semanticNLU", expectedStatus: "completed")],
            requiredTools: [ExpectedToolContract(toolID: "findDeviceCandidates")],
            expectedSelectedDeviceIDs: ["bedroom_ac"],
            expectedCapability: "switch",
            expectedCommand: "on",
            maxModelCallCount: 1,
            maxToolCallCount: 1
        )
        let missingAgent = ExpectedTraceContract(
            id: "case-1.trace",
            caseID: "case-1",
            requiredAgents: [ExpectedAgentContract(agentID: "draftGeneration")]
        )

        let comparator = TraceContractComparator()
        #expect(comparator.compare(passing, actual: trace).passed)
        #expect(comparator.compare(missingAgent, actual: trace).missingRequiredAgents == ["draftGeneration"])
    }

    @Test
    func traceComparatorAcceptsAlternativeGraphAndAgentPaths() {
        let trace = TraceNormalizer().normalize(syntheticTraceEvents(), caseID: "case-1")
        let contract = ExpectedTraceContract(
            id: "case-1.trace",
            caseID: "case-1",
            graphPathAlternatives: [["direct-command-graph"], ["direct-command-fallback-graph"]],
            requiredAgents: [ExpectedAgentContract(agentID: "semanticNLU")],
            agentPathAlternatives: [
                [ExpectedAgentContract(agentID: "draftGeneration")],
                [ExpectedAgentContract(agentID: "semanticNLU")]
            ],
            expectedSelectedDeviceIDs: ["bedroom_ac"],
            expectedCapability: "switch",
            expectedCommand: "on"
        )

        #expect(TraceContractComparator().compare(contract, actual: trace).passed)
    }

    @Test
    func comparatorsDetectToolIdentityAndBudgetFailures() {
        var events = syntheticTraceEvents()
        events.append(ObservabilityEvent(
            eventType: "tool.input",
            spanKind: .toolCall,
            graphID: "direct-command-graph",
            agentID: "draftGeneration",
            toolID: "validateCommand",
            toolCallID: "tool-call-without-output",
            status: .running
        ))
        let trace = TraceNormalizer().normalize(events, caseID: "case-1")
        let traceContract = ExpectedTraceContract(
            id: "case-1.trace",
            caseID: "case-1",
            requiredTools: [ExpectedToolContract(toolID: "validateCommand")]
        )
        let metricsContract = ExpectedMetricsContract(
            id: "case-1.metrics",
            caseID: "case-1",
            maxModelCallCount: 0,
            maxToolCallCount: 1
        )

        let traceDiff = TraceContractComparator().compare(traceContract, actual: trace)
        let metricsFailures = MetricsContractComparator().compare(metricsContract, actual: trace)

        #expect(traceDiff.unpairedToolCalls.contains { $0.contains("validateCommand") })
        #expect(traceDiff.missingToolTraceIDs.contains { $0.contains("validateCommand") })
        #expect(metricsFailures.contains { $0.contains("Model calls") })
        #expect(metricsFailures.contains { $0.contains("Tool calls") })
    }

    @Test
    func traceCaptureWritesActualTraceAndDiff() async throws {
        let context = HomeAutomationTelemetryContext(
            graphID: "direct-command-graph",
            agentID: "semanticNLU",
            agentSessionID: "agent-session",
            agentRunID: 1
        )
        let capture = try await EvaluationTraceCapture().capture(caseID: "capture-case") {
            await HomeAutomationTelemetryScope.$current.withValue(context) {
                await HomeAutomationTelemetry.shared.logAgentInput("Turn on bedroom AC", inputType: "String")
                await HomeAutomationTelemetry.shared.logAgentOutput("ok", outputType: "String")
            }
            return "done"
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("generated-eval-traces-\(UUID().uuidString)", isDirectory: true)
        let traceURL = try EvaluationTraceCapture().writeActualTrace(
            capture.events,
            caseID: "capture-case",
            to: directory.appendingPathComponent("actual-traces", isDirectory: true)
        )
        let diffURL = try TraceDiffWriter().write(
            TraceDiff(caseID: "capture-case", passed: true),
            to: directory.appendingPathComponent("trace-diffs", isDirectory: true)
        )

        #expect(capture.value == "done")
        #expect(capture.normalizedTrace.agentIdentityChecks["semanticNLU"]?.inputOutputPairs == 1)
        #expect(FileManager.default.fileExists(atPath: traceURL.path))
        #expect(FileManager.default.fileExists(atPath: diffURL.path))
    }

    private func syntheticTraceEvents(
        agentSessionID: String = "agent-session-1",
        toolSessionID: String = "tool-session-1",
        toolCallID: String = "tool-call-1"
    ) -> [ObservabilityEvent] {
        let agentInput = ObservabilityEvent(
            eventType: "agent.input",
            traceID: "trace-a",
            spanID: "span-a",
            spanKind: .agentAttempt,
            runID: "run-a",
            graphID: "direct-command-graph",
            agentID: "semanticNLU",
            agentInvocationID: "run-a-semanticNLU-1",
            agentSessionID: agentSessionID,
            agentRunID: 1,
            status: .running,
            payload: TelemetryPayload(values: [
                "agentID": .string("semanticNLU"),
                "agentSessionID": .string(agentSessionID),
                "agentRunID": .int(1)
            ])
        )
        let agentOutput = ObservabilityEvent(
            eventType: "agent.output",
            traceID: "trace-a",
            spanID: "span-a",
            spanKind: .agentAttempt,
            runID: "run-a",
            graphID: "direct-command-graph",
            agentID: "semanticNLU",
            agentInvocationID: "run-a-semanticNLU-1",
            agentSessionID: agentSessionID,
            agentRunID: 1,
            status: .completed,
            payload: TelemetryPayload(values: [
                "selectedCandidateIDs": .string("bedroom_ac"),
                "targetDeviceID": .string("bedroom_ac"),
                "capability": .string("switch"),
                "command": .string("on")
            ])
        )
        let modelCall = ObservabilityEvent(
            eventType: "model.call.completed",
            spanKind: .modelCall,
            graphID: "direct-command-graph",
            agentID: "semanticNLU",
            status: .completed,
            payload: TelemetryPayload(values: ["modelCallID": .string("model-call-1")])
        )
        let toolInput = ObservabilityEvent(
            eventType: "tool.input",
            spanKind: .toolCall,
            graphID: "direct-command-graph",
            agentID: "semanticNLU",
            agentSessionID: agentSessionID,
            agentRunID: 1,
            toolID: "findDeviceCandidates",
            toolSessionID: toolSessionID,
            toolCallID: toolCallID,
            status: .running
        )
        let toolOutput = ObservabilityEvent(
            eventType: "tool.output",
            spanKind: .toolCall,
            graphID: "direct-command-graph",
            agentID: "semanticNLU",
            agentSessionID: agentSessionID,
            agentRunID: 1,
            toolID: "findDeviceCandidates",
            toolSessionID: toolSessionID,
            toolCallID: toolCallID,
            status: .completed
        )
        return [agentInput, agentOutput, modelCall, toolInput, toolOutput]
    }
}

private actor SequencedParaphraseResponder: FoundationModelCommandParaphraseResponding {
    private var outputs: [Result<[String], any Error>]
    private(set) var callCount = 0

    init(outputs: [Result<[String], any Error>]) {
        self.outputs = outputs
    }

    func generateParaphrases(prompt: String, requestedCount: Int) async throws -> [String] {
        callCount += 1
        guard !outputs.isEmpty else { return [] }
        switch outputs.removeFirst() {
        case .success(let values):
            return values
        case .failure(let error):
            throw error
        }
    }
}

private actor SequencedCodexParaphraseRunner: CodexCLICommandParaphraseRunning {
    private var outputs: [Result<[String], any Error>]
    private(set) var callCount = 0

    init(outputs: [Result<[String], any Error>]) {
        self.outputs = outputs
    }

    func run(prompt: String, requestedCount: Int) async throws -> [String] {
        callCount += 1
        guard !outputs.isEmpty else { return [] }
        switch outputs.removeFirst() {
        case .success(let values):
            return values
        case .failure(let error):
            throw error
        }
    }
}
