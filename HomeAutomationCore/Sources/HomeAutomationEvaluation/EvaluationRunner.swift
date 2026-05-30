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

    public func write(_ result: EvaluationSuiteResult, to directoryURL: URL) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: directoryURL.appendingPathComponent("evaluation-traces", isDirectory: true),
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

        try markdownReport(for: result).write(
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
                mode: mode,
                status: outcome,
                passed: failures.isEmpty,
                durationMs: durationMs,
                traceID: metrics?.graphRun?.graphID,
                assertionFailures: failures,
                selectedDeviceIDs: result.aggregation.finalCandidateIDs,
                modelCallCount: metrics?.metricsV2?.modelCalls.modelCallCount ?? 0,
                metrics: metrics?.metricsV2
            )
        } catch {
            return EvaluationCaseResult(
                id: testCase.id,
                suite: testCase.suite,
                mode: mode,
                status: .unsupported,
                passed: false,
                durationMs: Date().timeIntervalSince(startedAt) * 1_000,
                assertionFailures: ["Execution threw: \(error.localizedDescription)"]
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
            mode: mode,
            status: failures.isEmpty ? .ready : .unsupported,
            passed: failures.isEmpty,
            durationMs: durationMs,
            assertionFailures: failures,
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
            mode: mode,
            status: requireLiveModel ? .unsupported : .skipped,
            passed: !requireLiveModel,
            skipped: !requireLiveModel,
            durationMs: Date().timeIntervalSince(startedAt) * 1_000,
            assertionFailures: requireLiveModel ? [reason] : []
        )
    }

    private var isLiveEvaluationEnabled: Bool {
        let value = ProcessInfo.processInfo.environment["HOME_AUTOMATION_EVAL_LIVE"] ?? ""
        return ["1", "true", "yes", "on"].contains(value.lowercased())
    }

    private func markdownReport(for result: EvaluationSuiteResult) -> String {
        var lines: [String] = [
            "# Home Automation Evaluation Report",
            "",
            "- Mode: \(result.mode.rawValue)",
            "- Total: \(result.summary.totalCaseCount)",
            "- Passed: \(result.summary.passedCaseCount)",
            "- Failed: \(result.summary.failedCaseCount)",
            "- Skipped: \(result.summary.skippedCaseCount)",
            "- Pass rate: \(String(format: "%.2f", result.summary.passRate * 100))%",
            "- Model calls: \(result.summary.modelCallCount)",
            "",
            "## Failing Cases"
        ]
        let failures = result.results.filter { !$0.passed && !$0.skipped }
        if failures.isEmpty {
            lines.append("None.")
        } else {
            for failure in failures {
                lines.append("- \(failure.id) [\(failure.suite)]: \(failure.assertionFailures.joined(separator: "; "))")
            }
        }
        return lines.joined(separator: "\n")
    }
}
