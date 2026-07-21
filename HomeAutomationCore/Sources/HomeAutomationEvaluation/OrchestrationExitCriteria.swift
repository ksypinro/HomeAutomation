import Foundation

public struct ExitCriterionResult: Sendable, Codable {
    public let name: String
    public let threshold: String
    public let actual: String
    public let passed: Bool

    public init(name: String, threshold: String, actual: String, passed: Bool) {
        self.name = name
        self.threshold = threshold
        self.actual = actual
        self.passed = passed
    }
}

public enum OrchestrationExitCriteria {
    public static let maxMeanFMCallsDirectCommand = 4
    public static let maxMeanFMCallsAutomationTier1 = 6
    public static let maxMeanFMCallsAutomationLoop = 4
    public static let maxP95LoopIterations = 2
    public static let maxClarificationRateDeltaPts = 0.03

    public static func evaluate(
        summaries: [OrchestrationArmSummary],
        categorySummaries: [String: [OrchestrationArmSummary]] = [:]
    ) -> [ExitCriterionResult] {
        let byArm = Dictionary(uniqueKeysWithValues: summaries.map { ($0.arm, $0) })
        let graph = byArm[.graph]
        let tier1 = byArm[.graphWithTier1]
        let loop = byArm[.verifierLoop]

        // Prefer per-category numbers when the category has cases; fall back
        // to the aggregate so callers without category splits keep working.
        func categoryArm(
            _ category: OrchestrationSuiteCategory,
            _ arm: OrchestrationArm
        ) -> OrchestrationArmSummary? {
            categorySummaries[category.rawValue]?.first { $0.arm == arm && $0.totalCases > 0 }
        }

        var results: [ExitCriterionResult] = []

        let graphAccuracy = graph?.accuracy ?? 0
        let tier1Accuracy = tier1?.accuracy ?? 0
        let loopAccuracy = loop?.accuracy ?? 0

        results.append(ExitCriterionResult(
            name: "End-to-end accuracy (Tier 1)",
            threshold: "≥ graph baseline (\(String(format: "%.1f%%", graphAccuracy * 100)))",
            actual: String(format: "%.1f%%", tier1Accuracy * 100),
            passed: tier1Accuracy >= graphAccuracy
        ))

        results.append(ExitCriterionResult(
            name: "End-to-end accuracy (loop)",
            threshold: "≥ graph baseline (\(String(format: "%.1f%%", graphAccuracy * 100)))",
            actual: String(format: "%.1f%%", loopAccuracy * 100),
            passed: loopAccuracy >= graphAccuracy
        ))

        let loopMeanFM = categoryArm(.directCommand, .verifierLoop)?.meanFMCalls
            ?? loop?.meanFMCalls ?? 0
        results.append(ExitCriterionResult(
            name: "Mean FM calls, direct command (loop)",
            threshold: "≤ \(maxMeanFMCallsDirectCommand)",
            actual: String(format: "%.2f", loopMeanFM),
            passed: loopMeanFM <= Double(maxMeanFMCallsDirectCommand)
        ))

        let tier1MeanFM = categoryArm(.automation, .graphWithTier1)?.meanFMCalls
            ?? tier1?.meanFMCalls ?? 0
        results.append(ExitCriterionResult(
            name: "Mean FM calls, automation (Tier 1)",
            threshold: "≤ \(maxMeanFMCallsAutomationTier1)",
            actual: String(format: "%.2f", tier1MeanFM),
            passed: tier1MeanFM <= Double(maxMeanFMCallsAutomationTier1)
        ))

        let loopAutoFM = categoryArm(.automation, .verifierLoop)?.meanFMCalls
            ?? loop?.meanFMCalls ?? 0
        results.append(ExitCriterionResult(
            name: "Mean FM calls, automation (loop)",
            threshold: "≤ \(maxMeanFMCallsAutomationLoop)",
            actual: String(format: "%.2f", loopAutoFM),
            passed: loopAutoFM <= Double(maxMeanFMCallsAutomationLoop)
        ))

        let p95Iterations = p95LoopIterations(loop)
        results.append(ExitCriterionResult(
            name: "p95 loop iterations",
            threshold: "≤ \(maxP95LoopIterations)",
            actual: "\(p95Iterations)",
            passed: p95Iterations <= maxP95LoopIterations
        ))

        let graphClarRate = graph?.clarificationRate ?? 0
        let tier1ClarRate = tier1?.clarificationRate ?? 0
        let loopClarRate = loop?.clarificationRate ?? 0
        let maxClarDelta = max(
            tier1ClarRate - graphClarRate,
            loopClarRate - graphClarRate
        )
        results.append(ExitCriterionResult(
            name: "Clarification rate delta",
            threshold: "≤ baseline + \(Int(maxClarificationRateDeltaPts * 100)) pts",
            actual: String(format: "+%.1f pts", maxClarDelta * 100),
            passed: maxClarDelta <= maxClarificationRateDeltaPts
        ))

        let tier1ConfirmRate = tier1?.confirmationRate ?? 0
        let loopConfirmRate = loop?.confirmationRate ?? 0
        let graphConfirmRate = graph?.confirmationRate ?? 0
        results.append(ExitCriterionResult(
            name: "Safety-gate outcomes identical",
            threshold: "confirmation rates match baseline",
            actual: String(format: "graph=%.1f%% tier1=%.1f%% loop=%.1f%%",
                           graphConfirmRate * 100, tier1ConfirmRate * 100, loopConfirmRate * 100),
            passed: abs(tier1ConfirmRate - graphConfirmRate) < 0.001
                && abs(loopConfirmRate - graphConfirmRate) < 0.001
        ))

        return results
    }

    private static func p95LoopIterations(_ loop: OrchestrationArmSummary?) -> Int {
        guard let loop, !loop.loopIterationHistogram.isEmpty else { return 0 }
        var allIterations: [Int] = []
        for (iterations, count) in loop.loopIterationHistogram {
            allIterations.append(contentsOf: Array(repeating: iterations, count: count))
        }
        allIterations.sort()
        let index = Int(Double(allIterations.count - 1) * 0.95)
        return allIterations[min(index, allIterations.count - 1)]
    }
}
