import Foundation
import FoundationModels
import HomeAutomationCore
import HomeAutomationOrchestrator

public enum OrchestrationArm: String, Sendable, Codable, Hashable, CaseIterable {
    case graph
    case graphWithTier1
    case verifierLoop
}

/// Coarse workload category used to split arm summaries so exit gates can
/// distinguish direct-command cost from automation cost.
public enum OrchestrationSuiteCategory: String, Sendable, Codable, Hashable, CaseIterable {
    case directCommand
    case automation

    public init(suite: String) {
        let lowered = suite.lowercased()
        if lowered.contains("automation") || lowered.contains("trigger") || lowered.contains("condition") {
            self = .automation
        } else {
            self = .directCommand
        }
    }
}

public struct OrchestrationArmResult: Sendable, Codable, Hashable {
    public let arm: OrchestrationArm
    public let caseID: String
    public let suite: String
    public let tags: [String]
    public let passed: Bool
    public let durationMs: Double
    public let modelCallCount: Int
    public let fmQueueWaitMs: Double
    public let outcome: EvaluationAllowedOutcome
    public let loopIterations: Int?
    public let escalated: Bool
    public let clarification: Bool
    public let confirmation: Bool
    public let selectedDeviceIDs: [String]
    public let capability: String?
    public let command: String?
    public let requiresFinalizationReceipt: Bool
    public let finalizationReceiptStatus: String?
    public let finalizationReceiptGraphID: String?

    public init(
        arm: OrchestrationArm,
        caseID: String,
        suite: String,
        tags: [String],
        passed: Bool,
        durationMs: Double,
        modelCallCount: Int,
        fmQueueWaitMs: Double,
        outcome: EvaluationAllowedOutcome,
        loopIterations: Int?,
        escalated: Bool,
        clarification: Bool,
        confirmation: Bool,
        selectedDeviceIDs: [String],
        capability: String?,
        command: String?,
        requiresFinalizationReceipt: Bool = false,
        finalizationReceiptStatus: String? = nil,
        finalizationReceiptGraphID: String? = nil
    ) {
        self.arm = arm
        self.caseID = caseID
        self.suite = suite
        self.tags = tags
        self.passed = passed
        self.durationMs = durationMs
        self.modelCallCount = modelCallCount
        self.fmQueueWaitMs = fmQueueWaitMs
        self.outcome = outcome
        self.loopIterations = loopIterations
        self.escalated = escalated
        self.clarification = clarification
        self.confirmation = confirmation
        self.selectedDeviceIDs = selectedDeviceIDs
        self.capability = capability
        self.command = command
        self.requiresFinalizationReceipt = requiresFinalizationReceipt
        self.finalizationReceiptStatus = finalizationReceiptStatus
        self.finalizationReceiptGraphID = finalizationReceiptGraphID
    }
}

public struct OrchestrationComparisonReport: Sendable, Codable {
    public let generatedAt: Date
    public let caseCount: Int
    public let armSummaries: [OrchestrationArmSummary]
    public let armCategorySummaries: [String: [OrchestrationArmSummary]]
    public let perCaseResults: [String: [OrchestrationArmResult]]
    public let exitCriteriaResults: [ExitCriterionResult]

    public init(
        generatedAt: Date = Date(),
        caseCount: Int,
        armSummaries: [OrchestrationArmSummary],
        armCategorySummaries: [String: [OrchestrationArmSummary]] = [:],
        perCaseResults: [String: [OrchestrationArmResult]],
        exitCriteriaResults: [ExitCriterionResult]
    ) {
        self.generatedAt = generatedAt
        self.caseCount = caseCount
        self.armSummaries = armSummaries
        self.armCategorySummaries = armCategorySummaries
        self.perCaseResults = perCaseResults
        self.exitCriteriaResults = exitCriteriaResults
    }
}

public struct OrchestrationArmSummary: Sendable, Codable {
    public let arm: OrchestrationArm
    public let totalCases: Int
    public let passedCases: Int
    public let accuracy: Double
    public let meanFMCalls: Double
    public let maxFMCalls: Int
    public let meanDurationMs: Double
    public let p50DurationMs: Double
    public let p95DurationMs: Double
    public let fmQueueWaitMsMean: Double
    public let clarificationRate: Double
    public let confirmationRate: Double
    public let escalationRate: Double
    public let finalizationReceiptRequiredCases: Int
    public let finalizationReceiptPresentCases: Int
    public let finalizationReceiptCompletedCases: Int
    public let actionableWithoutCompletedReceiptCases: Int
    public let finalizationReceiptCoverageRate: Double
    public let finalizationReceiptCompletedRate: Double
    public let loopIterationHistogram: [Int: Int]

    public static func make(
        arm: OrchestrationArm,
        results: [OrchestrationArmResult]
    ) -> OrchestrationArmSummary {
        let total = results.count
        guard total > 0 else {
            return OrchestrationArmSummary(
                arm: arm, totalCases: 0, passedCases: 0, accuracy: 0,
                meanFMCalls: 0, maxFMCalls: 0, meanDurationMs: 0,
                p50DurationMs: 0, p95DurationMs: 0, fmQueueWaitMsMean: 0,
                clarificationRate: 0, confirmationRate: 0, escalationRate: 0,
                finalizationReceiptRequiredCases: 0,
                finalizationReceiptPresentCases: 0,
                finalizationReceiptCompletedCases: 0,
                actionableWithoutCompletedReceiptCases: 0,
                finalizationReceiptCoverageRate: 0,
                finalizationReceiptCompletedRate: 0,
                loopIterationHistogram: [:]
            )
        }
        let passed = results.filter(\.passed).count
        let durations = results.map(\.durationMs).sorted()
        let fmCalls = results.map(\.modelCallCount)
        let iterationCounts = results.compactMap(\.loopIterations)
        let receiptRequired = results.filter(\.requiresFinalizationReceipt)
        let receiptPresent = receiptRequired.filter { $0.finalizationReceiptStatus != nil }
        let receiptCompleted = receiptRequired.filter { $0.finalizationReceiptStatus == FinalizationReceiptStatus.completed.rawValue }
        var histogram: [Int: Int] = [:]
        for iter in iterationCounts {
            histogram[iter, default: 0] += 1
        }

        return OrchestrationArmSummary(
            arm: arm,
            totalCases: total,
            passedCases: passed,
            accuracy: Double(passed) / Double(total),
            meanFMCalls: Double(fmCalls.reduce(0, +)) / Double(total),
            maxFMCalls: fmCalls.max() ?? 0,
            meanDurationMs: durations.reduce(0, +) / Double(total),
            p50DurationMs: percentile(durations, p: 0.50),
            p95DurationMs: percentile(durations, p: 0.95),
            fmQueueWaitMsMean: results.map(\.fmQueueWaitMs).reduce(0, +) / Double(total),
            clarificationRate: Double(results.filter(\.clarification).count) / Double(total),
            confirmationRate: Double(results.filter(\.confirmation).count) / Double(total),
            escalationRate: Double(results.filter(\.escalated).count) / Double(total),
            finalizationReceiptRequiredCases: receiptRequired.count,
            finalizationReceiptPresentCases: receiptPresent.count,
            finalizationReceiptCompletedCases: receiptCompleted.count,
            actionableWithoutCompletedReceiptCases: receiptRequired.count - receiptCompleted.count,
            finalizationReceiptCoverageRate: receiptRequired.isEmpty ? 0 : Double(receiptPresent.count) / Double(receiptRequired.count),
            finalizationReceiptCompletedRate: receiptRequired.isEmpty ? 0 : Double(receiptCompleted.count) / Double(receiptRequired.count),
            loopIterationHistogram: histogram
        )
    }
}

public struct OrchestrationComparisonRunner: Sendable {
    private let caseLimit: Int?
    private let requireLiveModel: Bool

    public init(caseLimit: Int? = nil, requireLiveModel: Bool = false) {
        self.caseLimit = caseLimit
        self.requireLiveModel = requireLiveModel
    }

    public func run(
        cases: [EvaluationCase] = EvaluationCorpus.defaultCases
    ) async -> OrchestrationComparisonReport {
        let selectedCases = Array(cases.prefix(caseLimit ?? cases.count))
        var perCase: [String: [OrchestrationArmResult]] = [:]

        for testCase in selectedCases {
            var armResults: [OrchestrationArmResult] = []
            for arm in OrchestrationArm.allCases {
                let result = await runArm(arm, testCase: testCase)
                armResults.append(result)
            }
            perCase[testCase.id] = armResults
        }

        let allResults = perCase.values.flatMap { $0 }
        let summaries = OrchestrationArm.allCases.map { arm in
            OrchestrationArmSummary.make(
                arm: arm,
                results: allResults.filter { $0.arm == arm }
            )
        }

        var categorySummaries: [String: [OrchestrationArmSummary]] = [:]
        for category in OrchestrationSuiteCategory.allCases {
            let categoryResults = allResults.filter { result in
                OrchestrationSuiteCategory(suite: result.suite) == category
            }
            var categoryArmSummaries: [OrchestrationArmSummary] = []
            for arm in OrchestrationArm.allCases {
                categoryArmSummaries.append(
                    OrchestrationArmSummary.make(
                        arm: arm,
                        results: categoryResults.filter { $0.arm == arm }
                    )
                )
            }
            categorySummaries[category.rawValue] = categoryArmSummaries
        }

        let exitResults = OrchestrationExitCriteria.evaluate(
            summaries: summaries,
            categorySummaries: categorySummaries
        )

        return OrchestrationComparisonReport(
            caseCount: selectedCases.count,
            armSummaries: summaries,
            armCategorySummaries: categorySummaries,
            perCaseResults: perCase,
            exitCriteriaResults: exitResults
        )
    }

    private func runArm(
        _ arm: OrchestrationArm,
        testCase: EvaluationCase
    ) async -> OrchestrationArmResult {
        let registry = DeviceCoordinator.makeMockDeviceRegistry(
            devices: testCase.fixture.devices.isEmpty ? nil : testCase.fixture.devices
        )
        let foundationModelAvailability: @Sendable () -> Bool
        if requireLiveModel {
            foundationModelAvailability = { SystemLanguageModel.default.isAvailable }
        } else {
            foundationModelAvailability = { false }
        }
        let coordinator = HomeAutomationCoordinator(
            deviceRegistry: registry,
            foundationModelAvailability: foundationModelAvailability
        )

        let deps: HomeAutomationRuntimeDependencies
        switch arm {
        case .graph:
            deps = coordinator.makeRuntimeDependencies()
        case .graphWithTier1:
            deps = coordinator.makeRuntimeDependencies(useMiniPipeline: true)
        case .verifierLoop:
            deps = coordinator.makeRuntimeDependencies(orchestrationMode: .verifierLoop)
        }

        let orchestrator = HomeCommandOrchestrator(dependencies: deps)
        let startedAt = Date()

        do {
            let result = try await orchestrator.resolve(testCase.input, executeLowRiskCommands: false)
            let metrics = await orchestrator.lastMetrics()
            let durationMs = Date().timeIntervalSince(startedAt) * 1_000
            let outcome = allowedOutcome(for: result.resolution)
            let receipt = metrics?.safetyMetrics.finalizationReceipt
            let requiresReceipt = requiresFinalizationReceipt(result.resolution)

            return OrchestrationArmResult(
                arm: arm,
                caseID: testCase.id,
                suite: testCase.suite,
                tags: testCase.tags,
                passed: matchesExpected(result: result, expected: testCase.expected),
                durationMs: durationMs,
                modelCallCount: metrics?.foundationModelUsage.modelCallCount ?? 0,
                fmQueueWaitMs: metrics?.graphRun?.nodeQueueDurations.values.reduce(0, +) ?? 0,
                outcome: outcome,
                loopIterations: metrics?.loop?.iterations,
                escalated: metrics?.loop?.escalationReason != nil,
                clarification: outcome == .clarification,
                confirmation: outcome == .confirmation,
                selectedDeviceIDs: selectedDeviceIDs(from: result),
                capability: result.draft?.capability,
                command: result.draft?.command,
                requiresFinalizationReceipt: requiresReceipt,
                finalizationReceiptStatus: receipt?.status.rawValue,
                finalizationReceiptGraphID: receipt?.graphID
            )
        } catch {
            let durationMs = Date().timeIntervalSince(startedAt) * 1_000
            return OrchestrationArmResult(
                arm: arm,
                caseID: testCase.id,
                suite: testCase.suite,
                tags: testCase.tags,
                passed: false,
                durationMs: durationMs,
                modelCallCount: 0,
                fmQueueWaitMs: 0,
                outcome: .unsupported,
                loopIterations: nil,
                escalated: false,
                clarification: false,
                confirmation: false,
                selectedDeviceIDs: [],
                capability: nil,
                command: nil,
                requiresFinalizationReceipt: false,
                finalizationReceiptStatus: nil,
                finalizationReceiptGraphID: nil
            )
        }
    }

    private func requiresFinalizationReceipt(_ resolution: HomeCommandResolution) -> Bool {
        switch resolution {
        case .readyToExecute,
             .executed,
             .requiresConfirmation,
             .automationDrafted,
             .automationRequiresConfirmation:
            return true
        case .needsClarification, .unsupported:
            return false
        }
    }

    private func allowedOutcome(for resolution: HomeCommandResolution) -> EvaluationAllowedOutcome {
        switch resolution {
        case .readyToExecute:
            return .ready
        case .needsClarification:
            return .clarification
        case .requiresConfirmation:
            return .confirmation
        case .unsupported:
            return .unsupported
        default:
            return .drafted
        }
    }

    private func matchesExpected(
        result: HomeAutomationResolverResult,
        expected: EvaluationExpectedOutput
    ) -> Bool {
        let draft = result.draft
        if let expectedCap = expected.capability, draft?.capability != expectedCap { return false }
        if let expectedCmd = expected.command, draft?.command != expectedCmd { return false }
        if !expected.expectedDeviceIDs.isEmpty {
            let actual = selectedDeviceIDs(from: result)
            if !Set(expected.expectedDeviceIDs).isSubset(of: Set(actual)) { return false }
        }
        let outcome = allowedOutcome(for: result.resolution)
        if outcome != expected.allowedOutcome { return false }
        return true
    }

    private func selectedDeviceIDs(from result: HomeAutomationResolverResult) -> [String] {
        if let deviceID = result.draft?.targetDeviceID {
            return [deviceID]
        }
        return []
    }

    public static func writeReport(
        _ report: OrchestrationComparisonReport,
        to directoryURL: URL
    ) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData = try encoder.encode(report)
        try jsonData.write(to: directoryURL.appendingPathComponent("orchestration-comparison.json"))

        let markdown = markdownReport(report)
        try markdown.write(
            to: directoryURL.appendingPathComponent("orchestration-comparison.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func markdownReport(_ report: OrchestrationComparisonReport) -> String {
        var lines: [String] = []
        lines.append("# Orchestration Comparison Report")
        lines.append("")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: report.generatedAt))")
        lines.append("Cases evaluated: \(report.caseCount)")
        lines.append("")

        lines.append("## Arm Summary")
        lines.append("")
        lines.append("| Metric | graph | graph+Tier1 | verifierLoop |")
        lines.append("|---|---|---|---|")

        let byArm = Dictionary(uniqueKeysWithValues: report.armSummaries.map { ($0.arm, $0) })
        let arms: [OrchestrationArm] = [.graph, .graphWithTier1, .verifierLoop]

        func cell(_ arm: OrchestrationArm, _ f: (OrchestrationArmSummary) -> String) -> String {
            byArm[arm].map(f) ?? "—"
        }

        lines.append("| Accuracy | \(arms.map { cell($0) { String(format: "%.1f%%", $0.accuracy * 100) } }.joined(separator: " | ")) |")
        lines.append("| Mean FM calls | \(arms.map { cell($0) { String(format: "%.2f", $0.meanFMCalls) } }.joined(separator: " | ")) |")
        lines.append("| Max FM calls | \(arms.map { cell($0) { "\($0.maxFMCalls)" } }.joined(separator: " | ")) |")
        lines.append("| Mean duration (ms) | \(arms.map { cell($0) { String(format: "%.1f", $0.meanDurationMs) } }.joined(separator: " | ")) |")
        lines.append("| p50 duration (ms) | \(arms.map { cell($0) { String(format: "%.1f", $0.p50DurationMs) } }.joined(separator: " | ")) |")
        lines.append("| p95 duration (ms) | \(arms.map { cell($0) { String(format: "%.1f", $0.p95DurationMs) } }.joined(separator: " | ")) |")
        lines.append("| FM queue wait (ms) | \(arms.map { cell($0) { String(format: "%.1f", $0.fmQueueWaitMsMean) } }.joined(separator: " | ")) |")
        lines.append("| Clarification rate | \(arms.map { cell($0) { String(format: "%.1f%%", $0.clarificationRate * 100) } }.joined(separator: " | ")) |")
        lines.append("| Confirmation rate | \(arms.map { cell($0) { String(format: "%.1f%%", $0.confirmationRate * 100) } }.joined(separator: " | ")) |")
        lines.append("| Escalation rate | \(arms.map { cell($0) { String(format: "%.1f%%", $0.escalationRate * 100) } }.joined(separator: " | ")) |")
        lines.append("| Finalization receipt required cases | \(arms.map { cell($0) { "\($0.finalizationReceiptRequiredCases)" } }.joined(separator: " | ")) |")
        lines.append("| Finalization receipt coverage | \(arms.map { cell($0) { String(format: "%.1f%%", $0.finalizationReceiptCoverageRate * 100) } }.joined(separator: " | ")) |")
        lines.append("| Finalization receipt completed | \(arms.map { cell($0) { String(format: "%.1f%%", $0.finalizationReceiptCompletedRate * 100) } }.joined(separator: " | ")) |")
        lines.append("| Actionable without completed receipt | \(arms.map { cell($0) { "\($0.actionableWithoutCompletedReceiptCases)" } }.joined(separator: " | ")) |")

        if !report.armCategorySummaries.isEmpty {
            lines.append("")
            lines.append("## Per-Category Mean FM Calls")
            lines.append("")
            lines.append("| Category | graph | graph+Tier1 | verifierLoop |")
            lines.append("|---|---|---|---|")
            for category in OrchestrationSuiteCategory.allCases {
                guard let categoryArms = report.armCategorySummaries[category.rawValue] else { continue }
                let byCategoryArm = Dictionary(uniqueKeysWithValues: categoryArms.map { ($0.arm, $0) })
                let cells = arms.map { arm -> String in
                    guard let summary = byCategoryArm[arm], summary.totalCases > 0 else { return "—" }
                    return String(format: "%.2f (n=%d)", summary.meanFMCalls, summary.totalCases)
                }
                lines.append("| \(category.rawValue) | \(cells.joined(separator: " | ")) |")
            }
        }

        if let loopArm = byArm[.verifierLoop], !loopArm.loopIterationHistogram.isEmpty {
            lines.append("")
            lines.append("## Loop Iteration Histogram")
            lines.append("")
            lines.append("| Iterations | Count |")
            lines.append("|---|---|")
            for key in loopArm.loopIterationHistogram.keys.sorted() {
                lines.append("| \(key) | \(loopArm.loopIterationHistogram[key]!) |")
            }
        }

        lines.append("")
        lines.append("## Exit Criteria")
        lines.append("")
        lines.append("| Gate | Threshold | Actual | Pass |")
        lines.append("|---|---|---|---|")
        for criterion in report.exitCriteriaResults {
            let pass = criterion.passed ? "YES" : "**NO**"
            lines.append("| \(criterion.name) | \(criterion.threshold) | \(criterion.actual) | \(pass) |")
        }

        let allPassed = report.exitCriteriaResults.allSatisfy(\.passed)
        lines.append("")
        lines.append(allPassed
            ? "**All exit criteria passed.** Ready for default flip."
            : "**Some exit criteria failed.** Not ready for default flip.")

        lines.append("")
        return lines.joined(separator: "\n")
    }
}

private func percentile(_ sorted: [Double], p: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let index = p * Double(sorted.count - 1)
    let lower = Int(index)
    let upper = min(lower + 1, sorted.count - 1)
    let fraction = index - Double(lower)
    return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
}
