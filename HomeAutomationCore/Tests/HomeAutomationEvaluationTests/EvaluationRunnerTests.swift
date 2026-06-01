import Foundation
import HomeAutomationEvaluation
import Testing

@Suite
struct EvaluationRunnerTests {
    @Test
    func deterministicRunnerProducesReportArtifacts() async throws {
        let runner = EvaluationRunner(
            mode: .deterministic,
            suites: ["observability-contract"]
        )
        let result = await runner.run()

        #expect(result.summary.totalCaseCount == 1)
        #expect(result.summary.failedCaseCount == 0)
        #expect(result.results.first?.metrics != nil)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("home-automation-eval-\(UUID().uuidString)", isDirectory: true)
        try runner.write(result, to: directory)

        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("evaluation-results.jsonl").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("evaluation-summary.json").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("evaluation-report.md").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("agent-metrics.json").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("dataset-validation-report.md").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("actual-traces", isDirectory: true).path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("trace-diffs", isDirectory: true).path))

        let agentMetricsData = try Data(contentsOf: directory.appendingPathComponent("agent-metrics.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let agentMetrics = try decoder.decode(EvaluationAgentMetricsReport.self, from: agentMetricsData)
        let report = try String(contentsOf: directory.appendingPathComponent("evaluation-report.md"), encoding: .utf8)

        #expect(!agentMetrics.agents.isEmpty)
        #expect(report.contains("## Agents"))
        #expect(report.contains("## Budget Violations"))
    }

    @Test
    func liveModeSkipsWhenDisabled() async {
        let runner = EvaluationRunner(
            mode: .live,
            suites: ["observability-contract"]
        )
        let result = await runner.run()

        #expect(result.summary.totalCaseCount == 1)
        #expect(result.summary.skippedCaseCount == 1)
        #expect(result.summary.failedCaseCount == 0)
    }
}
