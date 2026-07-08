import Foundation
import HomeAutomationCore
import HomeAutomationEvaluation
import Testing

@Suite("Phase G — Orchestration Comparison & Exit Criteria")
struct OrchestrationComparisonTests {

    // MARK: - G1: Arm summary computation

    @Test
    func armSummaryComputesAccuracy() {
        let results = [
            makeArmResult(arm: .graph, passed: true, durationMs: 100, modelCallCount: 2),
            makeArmResult(arm: .graph, passed: true, durationMs: 200, modelCallCount: 3),
            makeArmResult(arm: .graph, passed: false, durationMs: 300, modelCallCount: 5),
        ]
        let summary = OrchestrationArmSummary.make(arm: .graph, results: results)

        #expect(summary.totalCases == 3)
        #expect(summary.passedCases == 2)
        #expect(abs(summary.accuracy - 2.0/3.0) < 0.01)
    }

    @Test
    func armSummaryComputesFMCallStats() {
        let results = [
            makeArmResult(arm: .graph, passed: true, durationMs: 100, modelCallCount: 1),
            makeArmResult(arm: .graph, passed: true, durationMs: 200, modelCallCount: 3),
            makeArmResult(arm: .graph, passed: true, durationMs: 300, modelCallCount: 5),
        ]
        let summary = OrchestrationArmSummary.make(arm: .graph, results: results)

        #expect(summary.maxFMCalls == 5)
        #expect(abs(summary.meanFMCalls - 3.0) < 0.01)
    }

    @Test
    func armSummaryComputesDurationPercentiles() {
        let results = (1...100).map { i in
            makeArmResult(arm: .graph, passed: true, durationMs: Double(i), modelCallCount: 0)
        }
        let summary = OrchestrationArmSummary.make(arm: .graph, results: results)

        #expect(abs(summary.p50DurationMs - 50.5) < 1.0)
        #expect(summary.p95DurationMs >= 95.0)
    }

    @Test
    func armSummaryComputesClarificationRate() {
        let results = [
            makeArmResult(arm: .graph, passed: true, durationMs: 100, modelCallCount: 0, clarification: true),
            makeArmResult(arm: .graph, passed: true, durationMs: 100, modelCallCount: 0, clarification: false),
            makeArmResult(arm: .graph, passed: true, durationMs: 100, modelCallCount: 0, clarification: false),
            makeArmResult(arm: .graph, passed: true, durationMs: 100, modelCallCount: 0, clarification: false),
        ]
        let summary = OrchestrationArmSummary.make(arm: .graph, results: results)

        #expect(abs(summary.clarificationRate - 0.25) < 0.01)
    }

    @Test
    func armSummaryComputesLoopIterationHistogram() {
        let results = [
            makeArmResult(arm: .verifierLoop, passed: true, durationMs: 100, modelCallCount: 0, loopIterations: 1),
            makeArmResult(arm: .verifierLoop, passed: true, durationMs: 100, modelCallCount: 0, loopIterations: 1),
            makeArmResult(arm: .verifierLoop, passed: true, durationMs: 100, modelCallCount: 0, loopIterations: 2),
            makeArmResult(arm: .verifierLoop, passed: false, durationMs: 100, modelCallCount: 0, loopIterations: 3),
        ]
        let summary = OrchestrationArmSummary.make(arm: .verifierLoop, results: results)

        #expect(summary.loopIterationHistogram[1] == 2)
        #expect(summary.loopIterationHistogram[2] == 1)
        #expect(summary.loopIterationHistogram[3] == 1)
    }

    @Test
    func armSummaryHandlesEmptyResults() {
        let summary = OrchestrationArmSummary.make(arm: .graph, results: [])
        #expect(summary.totalCases == 0)
        #expect(summary.accuracy == 0)
        #expect(summary.meanFMCalls == 0)
    }

    // MARK: - G2: Exit criteria

    @Test
    func exitCriteriaAllPassWhenMetricsAreGood() {
        let graph = OrchestrationArmSummary.make(arm: .graph, results: [
            makeArmResult(arm: .graph, passed: true, durationMs: 100, modelCallCount: 2),
        ])
        let tier1 = OrchestrationArmSummary.make(arm: .graphWithTier1, results: [
            makeArmResult(arm: .graphWithTier1, passed: true, durationMs: 80, modelCallCount: 1),
        ])
        let loop = OrchestrationArmSummary.make(arm: .verifierLoop, results: [
            makeArmResult(arm: .verifierLoop, passed: true, durationMs: 90, modelCallCount: 2, loopIterations: 1),
        ])

        let criteria = OrchestrationExitCriteria.evaluate(summaries: [graph, tier1, loop])
        let allPassed = criteria.allSatisfy(\.passed)
        #expect(allPassed)
    }

    @Test
    func exitCriteriaFailWhenAccuracyDrops() {
        let graph = OrchestrationArmSummary.make(arm: .graph, results: [
            makeArmResult(arm: .graph, passed: true, durationMs: 100, modelCallCount: 2),
        ])
        let tier1 = OrchestrationArmSummary.make(arm: .graphWithTier1, results: [
            makeArmResult(arm: .graphWithTier1, passed: false, durationMs: 80, modelCallCount: 1),
        ])
        let loop = OrchestrationArmSummary.make(arm: .verifierLoop, results: [
            makeArmResult(arm: .verifierLoop, passed: true, durationMs: 90, modelCallCount: 2, loopIterations: 1),
        ])

        let criteria = OrchestrationExitCriteria.evaluate(summaries: [graph, tier1, loop])
        let tier1AccuracyCriterion = criteria.first { $0.name.contains("Tier 1") && $0.name.contains("accuracy") }
        #expect(tier1AccuracyCriterion?.passed == false)
    }

    @Test
    func exitCriteriaFailWhenFMCallsExceedThreshold() {
        let graph = OrchestrationArmSummary.make(arm: .graph, results: [
            makeArmResult(arm: .graph, passed: true, durationMs: 100, modelCallCount: 2),
        ])
        let tier1 = OrchestrationArmSummary.make(arm: .graphWithTier1, results: [
            makeArmResult(arm: .graphWithTier1, passed: true, durationMs: 80, modelCallCount: 8),
        ])
        let loop = OrchestrationArmSummary.make(arm: .verifierLoop, results: [
            makeArmResult(arm: .verifierLoop, passed: true, durationMs: 90, modelCallCount: 6, loopIterations: 1),
        ])

        let criteria = OrchestrationExitCriteria.evaluate(summaries: [graph, tier1, loop])
        let loopFMCriterion = criteria.first { $0.name.contains("direct command") }
        #expect(loopFMCriterion?.passed == false)
    }

    @Test
    func exitCriteriaCheckP95LoopIterations() {
        let graph = OrchestrationArmSummary.make(arm: .graph, results: [
            makeArmResult(arm: .graph, passed: true, durationMs: 100, modelCallCount: 0),
        ])
        let tier1 = OrchestrationArmSummary.make(arm: .graphWithTier1, results: [
            makeArmResult(arm: .graphWithTier1, passed: true, durationMs: 100, modelCallCount: 0),
        ])
        let loopResults = (0..<20).map { _ in
            makeArmResult(arm: .verifierLoop, passed: true, durationMs: 100, modelCallCount: 0, loopIterations: 3)
        }
        let loop = OrchestrationArmSummary.make(arm: .verifierLoop, results: loopResults)

        let criteria = OrchestrationExitCriteria.evaluate(summaries: [graph, tier1, loop])
        let p95Criterion = criteria.first { $0.name.contains("p95") }
        #expect(p95Criterion?.passed == false)
    }

    @Test
    func exitCriteriaCheckClarificationDelta() {
        let graph = OrchestrationArmSummary.make(arm: .graph, results:
            (0..<10).map { _ in makeArmResult(arm: .graph, passed: true, durationMs: 100, modelCallCount: 0) }
        )
        let tier1 = OrchestrationArmSummary.make(arm: .graphWithTier1, results:
            (0..<7).map { _ in makeArmResult(arm: .graphWithTier1, passed: true, durationMs: 100, modelCallCount: 0) } +
            (0..<3).map { _ in makeArmResult(arm: .graphWithTier1, passed: true, durationMs: 100, modelCallCount: 0, clarification: true) }
        )
        let loop = OrchestrationArmSummary.make(arm: .verifierLoop, results:
            (0..<10).map { _ in makeArmResult(arm: .verifierLoop, passed: true, durationMs: 100, modelCallCount: 0, loopIterations: 1) }
        )

        let criteria = OrchestrationExitCriteria.evaluate(summaries: [graph, tier1, loop])
        let clarCriterion = criteria.first { $0.name.contains("Clarification") }
        #expect(clarCriterion?.passed == false)
    }

    // MARK: - G1: Report generation

    @Test
    func comparisonReportContainsAllArms() {
        let summaries = OrchestrationArm.allCases.map { arm in
            OrchestrationArmSummary.make(arm: arm, results: [
                makeArmResult(arm: arm, passed: true, durationMs: 100, modelCallCount: 1),
            ])
        }
        let report = OrchestrationComparisonReport(
            caseCount: 1,
            armSummaries: summaries,
            perCaseResults: [:],
            exitCriteriaResults: OrchestrationExitCriteria.evaluate(summaries: summaries)
        )

        #expect(report.armSummaries.count == 3)
        #expect(report.exitCriteriaResults.count >= 5)
    }

    @Test
    func reportSerializesToJSON() throws {
        let summaries = OrchestrationArm.allCases.map { arm in
            OrchestrationArmSummary.make(arm: arm, results: [
                makeArmResult(arm: arm, passed: true, durationMs: 100, modelCallCount: 1),
            ])
        }
        let report = OrchestrationComparisonReport(
            caseCount: 1,
            armSummaries: summaries,
            perCaseResults: [:],
            exitCriteriaResults: []
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(OrchestrationComparisonReport.self, from: data)
        #expect(decoded.caseCount == 1)
        #expect(decoded.armSummaries.count == 3)
    }

    // MARK: - Helpers

    private func makeArmResult(
        arm: OrchestrationArm,
        passed: Bool,
        durationMs: Double,
        modelCallCount: Int,
        clarification: Bool = false,
        confirmation: Bool = false,
        loopIterations: Int? = nil,
        escalated: Bool = false
    ) -> OrchestrationArmResult {
        OrchestrationArmResult(
            arm: arm,
            caseID: UUID().uuidString,
            suite: "test",
            tags: [],
            passed: passed,
            durationMs: durationMs,
            modelCallCount: modelCallCount,
            fmQueueWaitMs: 0,
            outcome: clarification ? EvaluationAllowedOutcome.clarification : (confirmation ? EvaluationAllowedOutcome.confirmation : EvaluationAllowedOutcome.ready),
            loopIterations: loopIterations,
            escalated: escalated,
            clarification: clarification,
            confirmation: confirmation,
            selectedDeviceIDs: [],
            capability: nil as String?,
            command: nil as String?
        )
    }
}
