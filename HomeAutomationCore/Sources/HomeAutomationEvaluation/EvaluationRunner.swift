import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import HomeAutomationRAG

public struct EvaluationRunner: Sendable {
    public let mode: EvaluationMode
    public let requireLiveModel: Bool
    public let suites: Set<String>
    private let coordinator: any EvaluationCoordinating
    private let traceCapture = EvaluationTraceCapture()
    private let traceComparator = TraceContractComparator()
    private let metricsComparator = MetricsContractComparator()
    private let traceDiffWriter = TraceDiffWriter()

    public init(
        mode: EvaluationMode,
        requireLiveModel: Bool = false,
        suites: Set<String> = ["all"],
        coordinator: (any EvaluationCoordinating)? = nil
    ) {
        self.mode = mode
        self.requireLiveModel = requireLiveModel
        self.suites = suites
        self.coordinator = coordinator ?? EvaluationCoordinator()
    }

    public func run(cases: [EvaluationCase] = EvaluationCorpus.defaultCases) async -> EvaluationSuiteResult {
        let selectedCases = cases.filter { suites.contains("all") || suites.contains($0.suite) }
        var results: [EvaluationCaseResult] = []
        for testCase in selectedCases {
            results.append(await runCase(testCase))
        }
        return EvaluationSuiteResult(mode: mode, results: results)
    }

    public func runGeneratedDataset(
        _ dataset: GeneratedEvaluationDataset,
        compareTraces: Bool = false,
        writeActualTraces: Bool = false,
        outputURL: URL? = nil,
        caseLimit: Int? = nil,
        fixtureLimit: Int? = nil
    ) async -> EvaluationSuiteResult {
        let allowedFixtureIDs = Set(dataset.fixtures.prefix(fixtureLimit ?? dataset.fixtures.count).map(\.id))
        let selectedCases = dataset.cases
            .filter { allowedFixtureIDs.contains($0.fixtureID) }
            .filter { suites.contains("all") || suites.contains($0.suite) }
            .prefix(caseLimit ?? Int.max)
        let fixtureByID = Dictionary(uniqueKeysWithValues: dataset.fixtures.map { ($0.id, $0) })
        let traceContracts = Dictionary(uniqueKeysWithValues: dataset.traceContracts.map { ($0.id, $0) })
        let metricsContracts = Dictionary(uniqueKeysWithValues: dataset.metricsContracts.map { ($0.id, $0) })

        if let outputURL {
            try? FileManager.default.createDirectory(
                at: outputURL.appendingPathComponent("actual-traces", isDirectory: true),
                withIntermediateDirectories: true
            )
            try? FileManager.default.createDirectory(
                at: outputURL.appendingPathComponent("trace-diffs", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        var results: [EvaluationCaseResult] = []
        for generatedCase in selectedCases {
            guard let fixture = fixtureByID[generatedCase.fixtureID] else {
                results.append(EvaluationCaseResult(
                    id: generatedCase.id,
                    suite: generatedCase.suite,
                    fixtureID: generatedCase.fixtureID,
                    tags: generatedCase.tags,
                    mode: mode,
                    status: .unsupported,
                    passed: false,
                    durationMs: 0,
                    assertionFailures: ["Missing fixture \(generatedCase.fixtureID)"],
                    expectedDeviceIDs: generatedCase.expected.expectedDeviceIDs,
                    expectedCapability: generatedCase.expected.capability,
                    expectedCommand: generatedCase.expected.command,
                    expectedActionCount: generatedCase.expected.actionCount,
                    expectedConditionCount: generatedCase.expected.conditionCount
                ))
                continue
            }
            results.append(await runGeneratedCase(
                generatedCase,
                fixture: fixture,
                traceContract: traceContracts[generatedCase.traceContractID],
                metricsContract: metricsContracts[generatedCase.metricsContractID],
                compareTraces: compareTraces,
                writeActualTraces: writeActualTraces,
                outputURL: outputURL
            ))
        }
        return EvaluationSuiteResult(mode: mode, results: results)
    }

    public func write(_ result: EvaluationSuiteResult, to directoryURL: URL) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: directoryURL.appendingPathComponent("evaluation-traces", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL.appendingPathComponent("actual-traces", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL.appendingPathComponent("trace-diffs", isDirectory: true),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let resultLines = try result.results.map { item -> String in
            let data = try encoder.encode(item)
            return String(data: data, encoding: .utf8) ?? "{}"
        }.joined(separator: "\n")
        try resultLines.write(
            to: directoryURL.appendingPathComponent("evaluation-results.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let summaryData = try encoder.encode(result.summary)
        try summaryData.write(to: directoryURL.appendingPathComponent("evaluation-summary.json"))

        let agentMetrics = EvaluationAgentMetricsReport.make(from: result.results)
        let agentMetricsData = try encoder.encode(agentMetrics)
        try agentMetricsData.write(to: directoryURL.appendingPathComponent("agent-metrics.json"))

        try datasetValidationReport(for: result).write(
            to: directoryURL.appendingPathComponent("dataset-validation-report.md"),
            atomically: true,
            encoding: .utf8
        )

        try markdownReport(for: result, agentMetrics: agentMetrics).write(
            to: directoryURL.appendingPathComponent("evaluation-report.md"),
            atomically: true,
            encoding: .utf8
        )

        for failing in result.results where !failing.passed && !failing.skipped {
            let data = try encoder.encode(failing)
            try data.write(
                to: directoryURL
                    .appendingPathComponent("evaluation-traces", isDirectory: true)
                    .appendingPathComponent("\(failing.id).json")
            )
        }
    }

    private func runCase(_ testCase: EvaluationCase) async -> EvaluationCaseResult {
        let startedAt = Date()
        if mode == .live && !isLiveEvaluationEnabled {
            if requireLiveModel {
                return skippedResult(testCase, startedAt: startedAt, reason: "Live evaluation requested but HOME_AUTOMATION_EVAL_LIVE is not enabled")
            }
            return skippedResult(testCase, startedAt: startedAt, reason: "Live evaluation disabled")
        }

        if testCase.suite == "rag-retrieval" {
            return await runRAGCase(testCase, startedAt: startedAt)
        }

        let orchestrator = coordinator.makeOrchestrator(for: testCase, mode: mode)

        do {
            let result = try await orchestrator.resolve(testCase.input, executeLowRiskCommands: false)
            let metrics = await orchestrator.lastMetrics()
            let outcome = allowedOutcome(for: result.resolution)
            let failures = assertionFailures(for: testCase, result: result, metrics: metrics)
            let durationMs = Date().timeIntervalSince(startedAt) * 1_000
            return EvaluationCaseResult(
                id: testCase.id,
                suite: testCase.suite,
                tags: testCase.tags,
                mode: mode,
                status: outcome,
                passed: failures.isEmpty,
                durationMs: durationMs,
                traceID: metrics?.graphRun?.graphID,
                assertionFailures: failures,
                expectedDeviceIDs: testCase.expected.expectedDeviceIDs,
                selectedDeviceIDs: result.aggregation.finalCandidateIDs,
                actualTargetDeviceID: result.draft?.targetDeviceID,
                expectedCapability: testCase.expected.capability,
                actualCapability: result.draft?.capability,
                expectedCommand: testCase.expected.command,
                actualCommand: result.draft?.command,
                expectedActionCount: testCase.expected.actionCount,
                actualActionCount: metrics?.automationMetrics.automationActionCount,
                expectedConditionCount: testCase.expected.conditionCount,
                actualConditionCount: metrics?.automationMetrics.automationConditionCount,
                modelCallCount: metrics?.metricsV2?.modelCalls.modelCallCount ?? 0,
                toolCallCount: metrics?.metricsV2?.toolCalls.toolCount ?? 0,
                observability: observabilityMetrics(from: metrics?.metricsV2),
                metrics: metrics?.metricsV2
            )
        } catch {
            return EvaluationCaseResult(
                id: testCase.id,
                suite: testCase.suite,
                tags: testCase.tags,
                mode: mode,
                status: .unsupported,
                passed: false,
                durationMs: Date().timeIntervalSince(startedAt) * 1_000,
                assertionFailures: ["Execution threw: \(error.localizedDescription)"],
                expectedDeviceIDs: testCase.expected.expectedDeviceIDs,
                expectedCapability: testCase.expected.capability,
                expectedCommand: testCase.expected.command,
                expectedActionCount: testCase.expected.actionCount,
                expectedConditionCount: testCase.expected.conditionCount
            )
        }
    }

    private func runGeneratedCase(
        _ generatedCase: GeneratedEvaluationCase,
        fixture: GeneratedEvaluationFixture,
        traceContract: ExpectedTraceContract?,
        metricsContract: ExpectedMetricsContract?,
        compareTraces: Bool,
        writeActualTraces: Bool,
        outputURL: URL?
    ) async -> EvaluationCaseResult {
        let startedAt = Date()
        let testCase = evaluationCase(from: generatedCase, fixture: fixture)
        if mode == .live && !isLiveEvaluationEnabled {
            if requireLiveModel {
                return skippedResult(testCase, startedAt: startedAt, reason: "Live evaluation requested but HOME_AUTOMATION_EVAL_LIVE is not enabled")
            }
            return skippedResult(testCase, startedAt: startedAt, reason: "Live evaluation disabled")
        }

        let orchestrator = coordinator.makeOrchestrator(for: testCase, mode: mode)
        do {
            let capture = try await traceCapture.capture(caseID: generatedCase.id) {
                try await orchestrator.resolve(testCase.input, executeLowRiskCommands: false)
            }
            let result = capture.value
            let metrics = await orchestrator.lastMetrics()
            let outcome = allowedOutcome(for: result.resolution)
            var failures = assertionFailures(for: testCase, result: result, metrics: metrics)
            var traceDiff: TraceDiff?
            if compareTraces {
                if let traceContract {
                    let diff = traceComparator.compare(traceContract, actual: capture.normalizedTrace)
                    traceDiff = diff
                    failures += traceFailureMessages(from: diff)
                    if let outputURL {
                        _ = try? traceDiffWriter.write(
                            diff,
                            to: outputURL.appendingPathComponent("trace-diffs", isDirectory: true)
                        )
                    }
                } else {
                    failures.append("Missing trace contract \(generatedCase.traceContractID)")
                }
            }
            if let metricsContract {
                failures += metricsComparator.compare(
                    metricsContract,
                    actual: capture.normalizedTrace,
                    durationMs: Date().timeIntervalSince(startedAt) * 1_000
                )
            } else {
                failures.append("Missing metrics contract \(generatedCase.metricsContractID)")
            }
            if writeActualTraces, let outputURL {
                _ = try? traceCapture.writeActualTrace(
                    capture.events,
                    caseID: generatedCase.id,
                    to: outputURL.appendingPathComponent("actual-traces", isDirectory: true)
                )
            }
            return EvaluationCaseResult(
                id: generatedCase.id,
                suite: generatedCase.suite,
                fixtureID: generatedCase.fixtureID,
                tags: generatedCase.tags,
                mode: mode,
                status: outcome,
                passed: failures.isEmpty,
                durationMs: Date().timeIntervalSince(startedAt) * 1_000,
                traceID: capture.events.first(where: { $0.traceID != nil })?.traceID,
                assertionFailures: failures,
                expectedDeviceIDs: generatedCase.expected.expectedDeviceIDs,
                selectedDeviceIDs: result.aggregation.finalCandidateIDs,
                actualTargetDeviceID: result.draft?.targetDeviceID ?? capture.normalizedTrace.targetDeviceID,
                expectedCapability: generatedCase.expected.capability,
                actualCapability: result.draft?.capability ?? capture.normalizedTrace.capability,
                expectedCommand: generatedCase.expected.command,
                actualCommand: result.draft?.command ?? capture.normalizedTrace.command,
                expectedActionCount: generatedCase.expected.actionCount,
                actualActionCount: metrics?.automationMetrics.automationActionCount,
                expectedConditionCount: generatedCase.expected.conditionCount,
                actualConditionCount: metrics?.automationMetrics.automationConditionCount,
                modelCallCount: capture.normalizedTrace.modelCallCount,
                toolCallCount: capture.normalizedTrace.toolCallCount,
                observability: observabilityMetrics(
                    from: metrics?.metricsV2,
                    normalizedTrace: capture.normalizedTrace,
                    traceContract: traceContract,
                    traceDiff: traceDiff
                ),
                metrics: metrics?.metricsV2
            )
        } catch {
            return EvaluationCaseResult(
                id: generatedCase.id,
                suite: generatedCase.suite,
                fixtureID: generatedCase.fixtureID,
                tags: generatedCase.tags,
                mode: mode,
                status: .unsupported,
                passed: false,
                durationMs: Date().timeIntervalSince(startedAt) * 1_000,
                assertionFailures: ["Execution threw: \(error.localizedDescription)"],
                expectedDeviceIDs: generatedCase.expected.expectedDeviceIDs,
                expectedCapability: generatedCase.expected.capability,
                expectedCommand: generatedCase.expected.command,
                expectedActionCount: generatedCase.expected.actionCount,
                expectedConditionCount: generatedCase.expected.conditionCount
            )
        }
    }

    private func runRAGCase(_ testCase: EvaluationCase, startedAt: Date) async -> EvaluationCaseResult {
        let chunks = DocumentChunker().automationChunks()
        let indexer = coordinator.makeKnowledgeIndexer()
        _ = await indexer.index(chunks: chunks)
        let retriever = await indexer.makeRetriever()
        let expectedSources = testCase.expected.smartThingsJSONContains
        let results = await retriever.retrieve(testCase.input, topK: 5)
        let resultSources = Set(results.map { $0.chunk.source.rawValue })
        let missingSources = expectedSources.filter { !resultSources.contains($0) }
        let failures = missingSources.map { "Missing RAG source \($0) in top 5" }
        let durationMs = Date().timeIntervalSince(startedAt) * 1_000
        return EvaluationCaseResult(
            id: testCase.id,
            suite: testCase.suite,
            tags: testCase.tags,
            mode: mode,
            status: failures.isEmpty ? .ready : .unsupported,
            passed: failures.isEmpty,
            durationMs: durationMs,
            assertionFailures: failures,
            expectedDeviceIDs: testCase.expected.expectedDeviceIDs,
            modelCallCount: 0
        )
    }

    private func assertionFailures(
        for testCase: EvaluationCase,
        result: HomeAutomationResolverResult,
        metrics: OrchestratorMetrics?
    ) -> [String] {
        var failures: [String] = []
        let expected = testCase.expected
        let outcome = allowedOutcome(for: result.resolution)
        if outcome != expected.allowedOutcome {
            failures.append("Expected outcome \(expected.allowedOutcome.rawValue), got \(outcome.rawValue)")
        }
        if !expected.expectedDeviceIDs.isEmpty {
            let selected = Set(result.aggregation.finalCandidateIDs + [result.draft?.targetDeviceID].compactMap { $0 })
            let missing = expected.expectedDeviceIDs.filter { !selected.contains($0) }
            if !missing.isEmpty {
                failures.append("Missing expected selected device IDs: \(missing.joined(separator: ","))")
            }
        }
        if let capability = expected.capability, result.draft?.capability != capability {
            failures.append("Expected capability \(capability), got \(result.draft?.capability ?? "nil")")
        }
        if let command = expected.command, result.draft?.command != command {
            failures.append("Expected command \(command), got \(result.draft?.command ?? "nil")")
        }
        if let maxDuration = expected.maxDurationMs,
           let totalDurationMs = metrics?.metricsV2?.totalDurationMs,
           totalDurationMs > maxDuration {
            failures.append("Duration \(totalDurationMs)ms exceeded \(maxDuration)ms")
        }
        if let maxModelCalls = expected.maxModelCallCount,
           (metrics?.metricsV2?.modelCalls.modelCallCount ?? 0) > maxModelCalls {
            failures.append("Model call budget exceeded")
        }
        if let actionCount = expected.actionCount,
           metrics?.automationMetrics.automationActionCount != actionCount {
            failures.append("Expected \(actionCount) action(s), got \(metrics?.automationMetrics.automationActionCount ?? 0)")
        }
        if let conditionCount = expected.conditionCount,
           metrics?.automationMetrics.automationConditionCount != conditionCount {
            failures.append("Expected \(conditionCount) condition node(s), got \(metrics?.automationMetrics.automationConditionCount ?? 0)")
        }
        if !expected.smartThingsJSONContains.isEmpty {
            let summary = result.resolution.displaySummary
            let missing = expected.smartThingsJSONContains.filter { !summary.contains($0) }
            if !missing.isEmpty {
                failures.append("Resolution summary missing SmartThings markers: \(missing.joined(separator: ","))")
            }
        }
        if testCase.suite == "observability-contract", metrics?.metricsV2 == nil {
            failures.append("Missing RunMetricsV2")
        }
        return failures
    }

    private func allowedOutcome(for resolution: HomeCommandResolution) -> EvaluationAllowedOutcome {
        switch resolution {
        case .readyToExecute, .executed:
            return .ready
        case .automationDrafted:
            return .drafted
        case .needsClarification:
            return .clarification
        case .requiresConfirmation, .automationRequiresConfirmation:
            return .confirmation
        case .unsupported:
            return .unsupported
        }
    }

    private func skippedResult(_ testCase: EvaluationCase, startedAt: Date, reason: String) -> EvaluationCaseResult {
        EvaluationCaseResult(
            id: testCase.id,
            suite: testCase.suite,
            tags: testCase.tags,
            mode: mode,
            status: requireLiveModel ? .unsupported : .skipped,
            passed: !requireLiveModel,
            skipped: !requireLiveModel,
            durationMs: Date().timeIntervalSince(startedAt) * 1_000,
            assertionFailures: requireLiveModel ? [reason] : [],
            expectedDeviceIDs: testCase.expected.expectedDeviceIDs,
            expectedCapability: testCase.expected.capability,
            expectedCommand: testCase.expected.command,
            expectedActionCount: testCase.expected.actionCount,
            expectedConditionCount: testCase.expected.conditionCount
        )
    }

    private func observabilityMetrics(
        from metrics: RunMetricsV2?,
        normalizedTrace: NormalizedTrace? = nil,
        traceContract: ExpectedTraceContract? = nil,
        traceDiff: TraceDiff? = nil
    ) -> EvaluationCaseObservabilityMetrics? {
        guard metrics != nil || normalizedTrace != nil || traceContract != nil || traceDiff != nil else {
            return nil
        }
        let attempts = metrics?.agentAttempts ?? []
        var invocationCounts: [String: Int] = [:]
        var statusCounts: [String: [String: Int]] = [:]
        var durationSamples: [String: [Double]] = [:]

        if let normalizedTrace {
            for (agentID, check) in normalizedTrace.agentIdentityChecks {
                invocationCounts[agentID] = max(check.observedRunIDs.count, check.inputOutputPairs)
            }
            for span in normalizedTrace.spans where span.eventType == "agent.output" {
                guard let agentID = span.agentID else { continue }
                statusCounts[agentID, default: [:]][normalizedAgentStatus(span.status ?? "completed"), default: 0] += 1
            }
        } else {
            invocationCounts = Dictionary(grouping: attempts, by: \.agentID).mapValues(\.count)
            for attempt in attempts {
                statusCounts[attempt.agentID, default: [:]][normalizedAgentStatus(attempt.status), default: 0] += 1
            }
        }

        for attempt in attempts {
            durationSamples[attempt.agentID, default: []].append(attempt.durationMs)
        }

        let requiredAgents = stableUnique(traceContract?.requiredAgents.map(\.agentID) ?? [])
        let missingRequiredAgents = stableUnique(traceDiff?.missingRequiredAgents ?? [])
        let modelCallsByAgent = normalizedTrace.map { trace in
            Dictionary(grouping: trace.spans.filter { $0.spanKind == "modelCall" }.compactMap(\.agentID), by: { $0 })
                .mapValues(\.count)
        } ?? [:]
        let toolCallsByAgent = normalizedTrace.map { trace in
            Dictionary(grouping: trace.toolIdentityChecks.values.compactMap(\.callerAgentID), by: { $0 })
                .mapValues(\.count)
        } ?? [:]
        let missingAgentTraceIDs = normalizedTrace.map { trace in
            trace.agentIdentityChecks.mapValues {
                $0.missingInputTraceIDCount + $0.missingOutputTraceIDCount + $0.nonMonotonicRunIDCount
            }
        } ?? [:]
        let missingToolTraceCount = normalizedTrace?.toolIdentityChecks.values.filter {
            $0.missingToolSessionID || $0.missingCallerAgentTraceID
        }.count ?? 0
        let unpairedToolCallCount = normalizedTrace?.toolIdentityChecks.values.filter {
            !$0.hasInputEvent || !$0.hasOutputEvent
        }.count ?? traceDiff?.unpairedToolCalls.count ?? 0
        let callerIdentityMismatchCount = normalizedTrace?.toolIdentityChecks.values.filter(\.callerIdentityMismatch).count ??
            traceDiff?.callerIdentityMismatches.count ?? 0
        let contextWindowFailureCount = normalizedTrace?.contextWindowFailureCount ??
            metrics?.modelCalls.contextWindowFailuresByAgent.values.reduce(0, +) ?? 0

        return EvaluationCaseObservabilityMetrics(
            requiredAgents: requiredAgents,
            missingRequiredAgents: missingRequiredAgents,
            agentInvocationCounts: invocationCounts,
            agentStatusCounts: statusCounts,
            agentDurationSamplesMs: durationSamples,
            modelCallCountByAgent: modelCallsByAgent,
            toolCallCountByAgent: toolCallsByAgent,
            missingAgentTraceIdentityCountByAgent: missingAgentTraceIDs,
            missingToolTraceIdentityCount: missingToolTraceCount,
            unpairedToolCallCount: unpairedToolCallCount,
            callerIdentityMismatchCount: callerIdentityMismatchCount,
            contextWindowFailureCount: contextWindowFailureCount
        )
    }

    private func normalizedAgentStatus(_ rawStatus: String) -> String {
        let status = rawStatus.lowercased()
        if status.contains("skip") { return "skipped" }
        if status.contains("fail") || status.contains("error") { return "failed" }
        if status.contains("success") || status.contains("complete") || status == "completed" {
            return "completed"
        }
        return status
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    private var isLiveEvaluationEnabled: Bool {
        let value = ProcessInfo.processInfo.environment["HOME_AUTOMATION_EVAL_LIVE"] ?? ""
        return ["1", "true", "yes", "on"].contains(value.lowercased())
    }

    private func markdownReport(
        for result: EvaluationSuiteResult,
        agentMetrics: EvaluationAgentMetricsReport
    ) -> String {
        let topAgents = Array(agentMetrics.agents.prefix(20))
        let failures = result.results.filter { !$0.passed && !$0.skipped }
        let budgetFailures = failures.flatMap { result in
            result.assertionFailures
                .filter { $0.localizedCaseInsensitiveContains("budget") || $0.localizedCaseInsensitiveContains("exceeded") }
                .map { (result.id, $0) }
        }
        var lines: [String] = [
            "# Home Automation Evaluation Report",
            "",
            "## Summary",
            "",
            "| Metric | Value |",
            "|---|---:|",
            "| Mode | \(result.mode.rawValue) |",
            "| Total cases | \(result.summary.totalCaseCount) |",
            "| Passed | \(result.summary.passedCaseCount) |",
            "| Failed | \(result.summary.failedCaseCount) |",
            "| Skipped | \(result.summary.skippedCaseCount) |",
            "| Pass rate | \(percent(result.summary.passRate)) |",
            "| Selected device accuracy | \(percent(result.summary.selectedDeviceExactMatchAccuracy)) |",
            "| Target device accuracy | \(percent(result.summary.targetDeviceExactMatchAccuracy)) |",
            "| Capability accuracy | \(percent(result.summary.capabilityExactMatchAccuracy)) |",
            "| Command accuracy | \(percent(result.summary.commandExactMatchAccuracy)) |",
            "| Candidate recall@1 | \(percent(result.summary.candidateRecallAt1)) |",
            "| Candidate recall@3 | \(percent(result.summary.candidateRecallAt3)) |",
            "| Candidate recall@5 | \(percent(result.summary.candidateRecallAt5)) |",
            "| Model calls | \(result.summary.modelCallCount) |",
            "| Avg model calls/case | \(fixed(result.summary.averageModelCallsPerCase)) |",
            "| Tool calls | \(result.summary.toolCallCount) |",
            "| Avg tool calls/case | \(fixed(result.summary.averageToolCallsPerCase)) |",
            "| Agent trace identity pass rate | \(percent(result.summary.agentTraceIdentityPassRate)) |",
            "| Tool trace identity pass rate | \(percent(result.summary.toolTraceIdentityPassRate)) |",
            "",
            "## Suites",
            "",
            markdownRateTable(result.summary.passRateBySuite, keyTitle: "Suite"),
            "",
            "## Fixtures",
            "",
            markdownRateTable(result.summary.passRateByFixture, keyTitle: "Fixture"),
            "",
            "## Agents",
            "",
            "| Agent | Invocations | Required | Missing | Completed | Failed | Avg ms | Output | Device | Capability | Command | Model calls | Tool calls | Trace misses |",
            "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
        ]
        if topAgents.isEmpty {
            lines.append("| None | 0 | 0 | 0 | 0 | 0 |  |  |  |  |  | 0 | 0 | 0 |")
        } else {
            for agent in topAgents {
                lines.append("| \(agent.agentID) | \(agent.invocationCount) | \(agent.requiredCount) | \(agent.missingCount) | \(agent.completedCount) | \(agent.failedCount) | \(agent.averageDurationMs.map(fixed) ?? "") | \(percent(agent.outputAccuracy)) | \(percent(agent.selectedDeviceAccuracy)) | \(percent(agent.capabilityAccuracy)) | \(percent(agent.commandAccuracy)) | \(agent.modelCallCount) | \(agent.toolCallCount) | \(agent.missingTraceIdentityCount) |")
            }
        }

        lines += [
            "",
            "## Top Failing Cases"
        ]
        if failures.isEmpty {
            lines.append("None.")
        } else {
            for failure in failures.prefix(20) {
                let diffLink = "trace-diffs/\(failure.id).json"
                lines.append("- \(failure.id) [\(failure.suite)] \(diffLink): \(failure.assertionFailures.joined(separator: "; "))")
            }
        }

        lines += [
            "",
            "## Top Failing Agents",
            result.summary.topFailingAgents.isEmpty ? "None." : result.summary.topFailingAgents.map { "- \($0)" }.joined(separator: "\n"),
            "",
            "## Budget Violations"
        ]
        if budgetFailures.isEmpty {
            lines.append("None.")
        } else {
            for (caseID, failure) in budgetFailures.prefix(20) {
                lines.append("- \(caseID): \(failure)")
            }
        }

        lines += [
            "",
            "## Dataset Validation",
            "See `dataset-validation-report.md`."
        ]
        return lines.joined(separator: "\n")
    }

    private func datasetValidationReport(for result: EvaluationSuiteResult) -> String {
        let missingFixtureCount = result.results.filter { $0.fixtureID == nil }.count
        let missingExpectedDeviceCount = result.results.filter { !$0.skipped && $0.expectedDeviceIDs.isEmpty && $0.expectedCapability != nil }.count
        return [
            "# Dataset Validation Report",
            "",
            "- Evaluated cases: \(result.summary.totalCaseCount)",
            "- Cases with fixture IDs: \(result.summary.totalCaseCount - missingFixtureCount)",
            "- Cases missing fixture IDs: \(missingFixtureCount)",
            "- Command cases missing expected device IDs: \(missingExpectedDeviceCount)",
            "- Trace identity agent pass rate: \(percent(result.summary.agentTraceIdentityPassRate))",
            "- Trace identity tool pass rate: \(percent(result.summary.toolTraceIdentityPassRate))",
            "- Unpaired tool calls: \(result.summary.unpairedToolCallCount)",
            "- Caller identity mismatches: \(result.summary.callerIdentityMismatchCount)",
            "",
            missingExpectedDeviceCount == 0 ? "Validation status: passed." : "Validation status: review needed."
        ].joined(separator: "\n")
    }

    private func markdownRateTable(_ values: [String: Double], keyTitle: String) -> String {
        guard !values.isEmpty else { return "None." }
        var lines = [
            "| \(keyTitle) | Pass rate |",
            "|---|---:|"
        ]
        for (key, value) in values.sorted(by: { $0.key < $1.key }) {
            lines.append("| \(key) | \(percent(value)) |")
        }
        return lines.joined(separator: "\n")
    }

    private func percent(_ value: Double) -> String {
        "\(String(format: "%.2f", value * 100))%"
    }

    private func fixed(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func evaluationCase(
        from generatedCase: GeneratedEvaluationCase,
        fixture: GeneratedEvaluationFixture
    ) -> EvaluationCase {
        EvaluationCase(
            id: generatedCase.id,
            suite: generatedCase.suite,
            tags: generatedCase.tags,
            input: generatedCase.input,
            fixture: EvaluationFixture(devices: fixture.devices),
            expected: EvaluationExpectedOutput(
                operation: generatedCase.expected.operation,
                domain: generatedCase.expected.domain,
                languageCode: generatedCase.expected.languageCode,
                expectedDeviceIDs: generatedCase.expected.expectedDeviceIDs,
                capability: generatedCase.expected.capability,
                command: generatedCase.expected.command,
                actionCount: generatedCase.expected.actionCount,
                conditionCount: generatedCase.expected.conditionCount,
                smartThingsJSONContains: generatedCase.expected.smartThingsJSONContains,
                allowedOutcome: generatedCase.expected.allowedOutcome
            )
        )
    }

    private func traceFailureMessages(from diff: TraceDiff) -> [String] {
        guard !diff.passed else { return [] }
        var messages: [String] = []
        if !diff.missingRequiredAgents.isEmpty {
            messages.append("Missing required agents: \(diff.missingRequiredAgents.joined(separator: ","))")
        }
        if !diff.missingRequiredGraphs.isEmpty {
            messages.append("Missing required graphs: \(diff.missingRequiredGraphs.joined(separator: ","))")
        }
        if !diff.missingRequiredComponents.isEmpty {
            messages.append("Missing required automation components: \(diff.missingRequiredComponents.joined(separator: ","))")
        }
        if !diff.wrongAgentStatuses.isEmpty {
            messages.append("Wrong agent statuses: \(diff.wrongAgentStatuses.joined(separator: ","))")
        }
        if !diff.unexpectedFailedAgents.isEmpty {
            messages.append("Unexpected failed agents: \(diff.unexpectedFailedAgents.joined(separator: ","))")
        }
        if !diff.wrongSelectedDeviceIDs.isEmpty {
            messages.append("Wrong selected device IDs: \(diff.wrongSelectedDeviceIDs.joined(separator: ","))")
        }
        if let wrongCapability = diff.wrongCapability {
            messages.append("Wrong capability: \(wrongCapability)")
        }
        if let wrongCommand = diff.wrongCommand {
            messages.append("Wrong command: \(wrongCommand)")
        }
        if !diff.missingAgentTraceIDs.isEmpty {
            messages.append("Missing agent trace IDs: \(diff.missingAgentTraceIDs.joined(separator: ","))")
        }
        if !diff.missingToolTraceIDs.isEmpty {
            messages.append("Missing tool trace IDs: \(diff.missingToolTraceIDs.joined(separator: ","))")
        }
        if !diff.unpairedToolCalls.isEmpty {
            messages.append("Unpaired tool calls: \(diff.unpairedToolCalls.joined(separator: ","))")
        }
        if !diff.callerIdentityMismatches.isEmpty {
            messages.append("Tool caller identity mismatches: \(diff.callerIdentityMismatches.joined(separator: ","))")
        }
        if !diff.nonMonotonicAgentRunIDs.isEmpty {
            messages.append("Non-monotonic agent run IDs: \(diff.nonMonotonicAgentRunIDs.joined(separator: ","))")
        }
        messages += diff.budgetFailures.map { "Trace budget failure: \($0)" }
        return messages
    }
}
