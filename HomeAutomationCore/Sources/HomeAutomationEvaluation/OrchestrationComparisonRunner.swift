import Foundation
import FoundationModels
import HomeAutomationCore
import HomeAutomationOrchestrator

public enum OrchestrationArm: String, Sendable, Codable, Hashable, CaseIterable {
    case graph
    case graphWithTier1
    case verifierLoop
    case adaptiveStatic
    case adaptiveShadow
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
    public let repetitionIndex: Int
    public let isWarmup: Bool
    public let armOrderIndex: Int
    public let telemetryComplete: Bool
    public let passed: Bool
    public let durationMs: Double
    public let modelCallCount: Int
    public let fmQueueWaitMs: Double
    public let fmServiceMs: Double
    public let telemetryOverheadMs: Double
    public let outcome: EvaluationAllowedOutcome
    public let resolutionSummary: String?
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
    /// Phase 0: orchestration strategy classification
    public let strategy: OrchestrationStrategy?
    /// Phase 0: root-routing source ("normal", "adaptive", "prepared")
    public let rootRoutingSource: String?
    /// Phase 0: selected arm in portfolio routing
    public let selectedArm: String?
    /// Phase 0: actually executing arm, which differs from selected arm in shadow mode.
    public let executingArm: String?
    /// Phase 0: router rule ID for routing decision audit trail
    public let routerRuleID: String?

    public init(
        arm: OrchestrationArm,
        caseID: String,
        suite: String,
        tags: [String],
        repetitionIndex: Int = 0,
        isWarmup: Bool = false,
        armOrderIndex: Int = 0,
        telemetryComplete: Bool = true,
        passed: Bool,
        durationMs: Double,
        modelCallCount: Int,
        fmQueueWaitMs: Double,
        fmServiceMs: Double = 0,
        telemetryOverheadMs: Double = 0,
        outcome: EvaluationAllowedOutcome,
        resolutionSummary: String? = nil,
        loopIterations: Int?,
        escalated: Bool,
        clarification: Bool,
        confirmation: Bool,
        selectedDeviceIDs: [String],
        capability: String?,
        command: String?,
        requiresFinalizationReceipt: Bool = false,
        finalizationReceiptStatus: String? = nil,
        finalizationReceiptGraphID: String? = nil,
        strategy: OrchestrationStrategy? = nil,
        rootRoutingSource: String? = nil,
        selectedArm: String? = nil,
        executingArm: String? = nil,
        routerRuleID: String? = nil
    ) {
        self.arm = arm
        self.caseID = caseID
        self.suite = suite
        self.tags = tags
        self.repetitionIndex = repetitionIndex
        self.isWarmup = isWarmup
        self.armOrderIndex = armOrderIndex
        self.telemetryComplete = telemetryComplete
        self.passed = passed
        self.durationMs = durationMs
        self.modelCallCount = modelCallCount
        self.fmQueueWaitMs = fmQueueWaitMs
        self.fmServiceMs = fmServiceMs
        self.telemetryOverheadMs = telemetryOverheadMs
        self.outcome = outcome
        self.resolutionSummary = resolutionSummary
        self.loopIterations = loopIterations
        self.escalated = escalated
        self.clarification = clarification
        self.confirmation = confirmation
        self.strategy = strategy
        self.rootRoutingSource = rootRoutingSource
        self.selectedArm = selectedArm
        self.executingArm = executingArm
        self.routerRuleID = routerRuleID
        self.selectedDeviceIDs = selectedDeviceIDs
        self.capability = capability
        self.command = command
        self.requiresFinalizationReceipt = requiresFinalizationReceipt
        self.finalizationReceiptStatus = finalizationReceiptStatus
        self.finalizationReceiptGraphID = finalizationReceiptGraphID
    }
}

public struct OrchestrationComparisonReport: Sendable, Codable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let caseCount: Int
    public let includedRunCount: Int
    public let seed: UInt64
    public let repetitions: Int
    public let warmups: Int
    public let gateConcurrency: Int
    public let prewarmMode: String
    public let modelAvailabilityLabel: String
    public let hardwareLabel: String
    public let buildLabel: String
    public let telemetryComplete: Bool
    public let armSummaries: [OrchestrationArmSummary]
    public let armCategorySummaries: [String: [OrchestrationArmSummary]]
    public let perCaseResults: [String: [OrchestrationArmResult]]
    public let exitCriteriaResults: [ExitCriterionResult]

    public init(
        schemaVersion: Int = 2,
        generatedAt: Date = Date(),
        caseCount: Int,
        includedRunCount: Int? = nil,
        seed: UInt64 = 0,
        repetitions: Int = 1,
        warmups: Int = 0,
        gateConcurrency: Int = 2,
        prewarmMode: String = "default",
        modelAvailabilityLabel: String = "deterministic",
        hardwareLabel: String = ProcessInfo.processInfo.hostName,
        buildLabel: String = "debug",
        telemetryComplete: Bool = true,
        armSummaries: [OrchestrationArmSummary],
        armCategorySummaries: [String: [OrchestrationArmSummary]] = [:],
        perCaseResults: [String: [OrchestrationArmResult]],
        exitCriteriaResults: [ExitCriterionResult]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.caseCount = caseCount
        self.includedRunCount = includedRunCount ?? armSummaries.map(\.totalCases).reduce(0, +)
        self.seed = seed
        self.repetitions = repetitions
        self.warmups = warmups
        self.gateConcurrency = gateConcurrency
        self.prewarmMode = prewarmMode
        self.modelAvailabilityLabel = modelAvailabilityLabel
        self.hardwareLabel = hardwareLabel
        self.buildLabel = buildLabel
        self.telemetryComplete = telemetryComplete
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
    private let seed: UInt64
    private let repetitions: Int
    private let warmups: Int
    private let gateConcurrency: Int
    private let prewarmMode: String

    public init(
        caseLimit: Int? = nil,
        requireLiveModel: Bool = false,
        seed: UInt64 = 0,
        repetitions: Int = 1,
        warmups: Int = 0,
        gateConcurrency: Int = 2,
        prewarmMode: String = "default"
    ) {
        self.caseLimit = caseLimit
        self.requireLiveModel = requireLiveModel
        self.seed = seed
        self.repetitions = max(1, repetitions)
        self.warmups = max(0, warmups)
        self.gateConcurrency = max(1, gateConcurrency)
        self.prewarmMode = prewarmMode
    }

    public func run(
        cases: [EvaluationCase] = EvaluationCorpus.defaultCases
    ) async -> OrchestrationComparisonReport {
        let selectedCases = Array(cases.prefix(caseLimit ?? cases.count))
        var perCase: [String: [OrchestrationArmResult]] = [:]

        for (caseIndex, testCase) in selectedCases.enumerated() {
            var armResults: [OrchestrationArmResult] = []
            for repetition in 0..<(warmups + repetitions) {
                let isWarmup = repetition < warmups
                let reportedRepetition = isWarmup ? -(warmups - repetition) : (repetition - warmups)
                let orderedArms = Self.armOrder(caseIndex: caseIndex, repetitionIndex: repetition, seed: seed)
                for (orderIndex, arm) in orderedArms.enumerated() {
                    let result = await runArm(
                        arm,
                        testCase: testCase,
                        repetitionIndex: reportedRepetition,
                        isWarmup: isWarmup,
                        armOrderIndex: orderIndex
                    )
                    armResults.append(result)
                }
            }
            perCase[testCase.id] = armResults
        }

        let allRunResults = perCase.values.flatMap { $0 }
        let allResults = allRunResults.filter { !$0.isWarmup }
        let telemetryComplete = allRunResults.allSatisfy(\.telemetryComplete)
        let summaries = OrchestrationArm.allCases.map { arm in
            OrchestrationArmSummary.make(
                arm: arm,
                results: allResults.filter { $0.arm == arm }
            )
        }

        let categorySummaries = makeCategorySummaries(for: allResults)
        let exitCriteriaResults = allResults.filter { result in
            !result.tags.contains("conditionResolution:unsupported")
        }
        let exitSummaries = OrchestrationArm.allCases.map { arm in
            OrchestrationArmSummary.make(
                arm: arm,
                results: exitCriteriaResults.filter { $0.arm == arm }
            )
        }
        let exitCategorySummaries = makeCategorySummaries(for: exitCriteriaResults)

        var exitResults = OrchestrationExitCriteria.evaluate(
            summaries: exitSummaries,
            categorySummaries: exitCategorySummaries
        )
        exitResults.append(contentsOf: pairedConditionalExitCriteria(
            results: allResults,
            arms: OrchestrationArm.allCases
        ))
        exitResults.append(ExitCriterionResult(
            name: "Telemetry completeness",
            threshold: "100%",
            actual: telemetryComplete ? "100%" : "incomplete",
            passed: telemetryComplete
        ))

        return OrchestrationComparisonReport(
            caseCount: selectedCases.count,
            includedRunCount: allResults.count,
            seed: seed,
            repetitions: repetitions,
            warmups: warmups,
            gateConcurrency: gateConcurrency,
            prewarmMode: prewarmMode,
            modelAvailabilityLabel: requireLiveModel ? FoundationModelDiagnostics.availabilityStatus() : "deterministic",
            telemetryComplete: telemetryComplete,
            armSummaries: summaries,
            armCategorySummaries: categorySummaries,
            perCaseResults: perCase,
            exitCriteriaResults: exitResults
        )
    }

    private func makeCategorySummaries(
        for results: [OrchestrationArmResult]
    ) -> [String: [OrchestrationArmSummary]] {
        var categorySummaries: [String: [OrchestrationArmSummary]] = [:]
        for category in OrchestrationSuiteCategory.allCases {
            let categoryResults = results.filter { result in
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
        return categorySummaries
    }

    public static func armOrder(
        caseIndex: Int,
        repetitionIndex: Int,
        seed: UInt64
    ) -> [OrchestrationArm] {
        let arms = OrchestrationArm.allCases
        guard !arms.isEmpty else { return [] }
        let rotation = (caseIndex + repetitionIndex + Int(seed % UInt64(arms.count))) % arms.count
        return Array(arms[rotation...]) + Array(arms[..<rotation])
    }

    private func runArm(
        _ arm: OrchestrationArm,
        testCase: EvaluationCase,
        repetitionIndex: Int,
        isWarmup: Bool,
        armOrderIndex: Int
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
            foundationModelAvailability: foundationModelAvailability,
            circuitBreakers: CircuitBreakerRegistry(threshold: 1_000, recoveryInterval: 0, persistenceKey: nil)
        )

        let deps: HomeAutomationRuntimeDependencies
        switch arm {
        case .graph:
            deps = coordinator.makeRuntimeDependencies()
        case .graphWithTier1:
            deps = coordinator.makeRuntimeDependencies(useMiniPipeline: true)
        case .verifierLoop:
            deps = coordinator.makeRuntimeDependencies(orchestrationMode: .verifierLoop)
        case .adaptiveStatic:
            deps = coordinator.makeRuntimeDependencies(
                orchestrationMode: .adaptivePortfolio,
                portfolioRolloutMode: .activeStatic,
                portfolioEligibilityPolicy: PortfolioEligibilityPolicy(conditionalTier1Enabled: true)
            )
        case .adaptiveShadow:
            deps = coordinator.makeRuntimeDependencies(
                orchestrationMode: .adaptivePortfolio,
                portfolioRolloutMode: .shadowStatic,
                portfolioEligibilityPolicy: PortfolioEligibilityPolicy(conditionalTier1Enabled: true)
            )
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
                repetitionIndex: repetitionIndex,
                isWarmup: isWarmup,
                armOrderIndex: armOrderIndex,
                telemetryComplete: metrics?.foundationModelUsageSnapshot != nil,
                passed: matchesExpected(result: result, expected: testCase.expected),
                durationMs: durationMs,
                modelCallCount: metrics?.foundationModelUsage.modelCallCount ?? 0,
                fmQueueWaitMs: metrics?.foundationModelUsage.queueWaitTotalMs ?? 0,
                fmServiceMs: metrics?.foundationModelUsage.serviceTotalMs ?? 0,
                telemetryOverheadMs: metrics?.foundationModelUsage.telemetryOverheadMs ?? 0,
                outcome: outcome,
                resolutionSummary: result.resolution.displaySummary,
                loopIterations: metrics?.loop?.iterations,
                escalated: metrics?.loop?.escalationReason != nil,
                clarification: outcome == .clarification,
                confirmation: outcome == .confirmation,
                selectedDeviceIDs: selectedDeviceIDs(from: result),
                capability: result.draft?.capability,
                command: result.draft?.command,
                requiresFinalizationReceipt: requiresReceipt,
                finalizationReceiptStatus: receipt?.status.rawValue,
                finalizationReceiptGraphID: receipt?.graphID,
                strategy: strategy(for: arm),
                rootRoutingSource: rootRoutingSource(for: arm),
                selectedArm: metrics?.portfolioExecutionPlan?.selectedArm.rawValue ?? selectedArm(for: arm),
                executingArm: metrics?.portfolioExecutionPlan?.executingArm.rawValue ?? executingArm(for: arm),
                routerRuleID: metrics?.portfolioDecision?.ruleID
            )
        } catch {
            let durationMs = Date().timeIntervalSince(startedAt) * 1_000
            return OrchestrationArmResult(
                arm: arm,
                caseID: testCase.id,
                suite: testCase.suite,
                tags: testCase.tags,
                repetitionIndex: repetitionIndex,
                isWarmup: isWarmup,
                armOrderIndex: armOrderIndex,
                telemetryComplete: false,
                passed: false,
                durationMs: durationMs,
                modelCallCount: 0,
                fmQueueWaitMs: 0,
                outcome: .unsupported,
                resolutionSummary: error.localizedDescription,
                loopIterations: nil,
                escalated: false,
                clarification: false,
                confirmation: false,
                selectedDeviceIDs: [],
                capability: nil,
                command: nil,
                requiresFinalizationReceipt: false,
                finalizationReceiptStatus: nil,
                finalizationReceiptGraphID: nil,
                strategy: strategy(for: arm),
                rootRoutingSource: rootRoutingSource(for: arm),
                selectedArm: selectedArm(for: arm),
                executingArm: executingArm(for: arm),
                routerRuleID: nil
            )
        }
    }

    private func strategy(for arm: OrchestrationArm) -> OrchestrationStrategy {
        switch arm {
        case .graph:
            return .graph
        case .graphWithTier1:
            return .graphWithTier1
        case .verifierLoop:
            return .verifierLoop
        case .adaptiveStatic:
            return .adaptiveStatic
        case .adaptiveShadow:
            return .adaptiveShadow
        }
    }

    private func rootRoutingSource(for arm: OrchestrationArm) -> String {
        switch arm {
        case .adaptiveStatic, .adaptiveShadow:
            return "adaptive"
        case .graph, .graphWithTier1, .verifierLoop:
            return "normal"
        }
    }

    private func selectedArm(for arm: OrchestrationArm) -> String? {
        switch arm {
        case .graph, .adaptiveShadow:
            return FoundationModelCallArm.graph.rawValue
        case .graphWithTier1, .adaptiveStatic:
            return FoundationModelCallArm.graphWithTier1.rawValue
        case .verifierLoop:
            return FoundationModelCallArm.verifierLoop.rawValue
        }
    }

    private func executingArm(for arm: OrchestrationArm) -> String? {
        switch arm {
        case .adaptiveShadow:
            return FoundationModelCallArm.graph.rawValue
        default:
            return selectedArm(for: arm)
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
        case .readyToExecute, .executed:
            return .ready
        case .needsClarification:
            return .clarification
        case .requiresConfirmation, .automationRequiresConfirmation:
            return .confirmation
        case .unsupported:
            return .unsupported
        case .automationDrafted:
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
        if !outcomeMatches(outcome, expected: expected.allowedOutcome) { return false }
        return true
    }

    private func outcomeMatches(
        _ outcome: EvaluationAllowedOutcome,
        expected: EvaluationAllowedOutcome
    ) -> Bool {
        if outcome == expected { return true }
        return expected == .unsupported && outcome == .clarification
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
        lines.append("Schema: \(report.schemaVersion)")
        lines.append("Cases evaluated: \(report.caseCount)")
        lines.append("Included runs: \(report.includedRunCount)")
        lines.append("Seed: \(report.seed)")
        lines.append("Repetitions: \(report.repetitions)")
        lines.append("Warmups: \(report.warmups)")
        lines.append("Telemetry complete: \(report.telemetryComplete ? "yes" : "no")")
        lines.append("Model availability: \(report.modelAvailabilityLabel)")
        lines.append("Gate concurrency: \(report.gateConcurrency)")
        lines.append("Prewarm mode: \(report.prewarmMode)")
        lines.append("")

        lines.append("## Arm Summary")
        lines.append("")
        lines.append("| Metric | graph | graph+Tier1 | verifierLoop | adaptiveStatic | adaptiveShadow |")
        lines.append("|---|---|---|---|---|---|")

        let byArm = Dictionary(uniqueKeysWithValues: report.armSummaries.map { ($0.arm, $0) })
        let arms: [OrchestrationArm] = [.graph, .graphWithTier1, .verifierLoop, .adaptiveStatic, .adaptiveShadow]

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
        lines.append("| Telemetry overhead (ms) | \(arms.map { cell($0) { summary in String(format: "%.1f", allOverheadMean(report: report, arm: summary.arm)) } }.joined(separator: " | ")) |")
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
            lines.append("| Category | graph | graph+Tier1 | verifierLoop | adaptiveStatic | adaptiveShadow |")
            lines.append("|---|---|---|---|---|---|")
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

        let pairedSummaries = pairedConditionalOverheadSummaries(report: report, arms: arms)
        if !pairedSummaries.isEmpty {
            lines.append("")
            lines.append("## Paired Conditional Latency Overhead")
            lines.append("")
            lines.append("| Metric | graph | graph+Tier1 | verifierLoop | adaptiveStatic | adaptiveShadow |")
            lines.append("|---|---|---|---|---|---|")

            func pairedCell(_ arm: OrchestrationArm, _ f: (PairedConditionalOverheadSummary) -> String) -> String {
                pairedSummaries[arm].map(f) ?? "—"
            }

            lines.append("| Correct conditioned/base pairs | \(arms.map { pairedCell($0) { "\($0.correctPairCount)" } }.joined(separator: " | ")) |")
            lines.append("| Mean added condition latency (ms) | \(arms.map { pairedCell($0) { String(format: "%.1f", $0.meanAddedLatencyMs) } }.joined(separator: " | ")) |")
            lines.append("| p50 added condition latency (ms) | \(arms.map { pairedCell($0) { String(format: "%.1f", $0.p50AddedLatencyMs) } }.joined(separator: " | ")) |")
            lines.append("| p95 added condition latency (ms) | \(arms.map { pairedCell($0) { String(format: "%.1f", $0.p95AddedLatencyMs) } }.joined(separator: " | ")) |")
            lines.append("| Mean added FM calls | \(arms.map { pairedCell($0) { String(format: "%.2f", $0.meanAddedFMCalls) } }.joined(separator: " | ")) |")
            lines.append("| Incorrect/missing pairs | \(arms.map { pairedCell($0) { "\($0.incorrectOrMissingPairCount)" } }.joined(separator: " | ")) |")
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

private func allOverheadMean(report: OrchestrationComparisonReport, arm: OrchestrationArm) -> Double {
    let values = report.perCaseResults.values
        .flatMap { $0 }
        .filter { $0.arm == arm && !$0.isWarmup }
        .map(\.telemetryOverheadMs)
    guard !values.isEmpty else { return 0 }
    return values.reduce(0, +) / Double(values.count)
}

private struct PairedConditionalOverheadSummary {
    let correctPairCount: Int
    let incorrectOrMissingPairCount: Int
    let meanAddedLatencyMs: Double
    let p50AddedLatencyMs: Double
    let p95AddedLatencyMs: Double
    let meanAddedFMCalls: Double
}

private func pairedConditionalOverheadSummaries(
    report: OrchestrationComparisonReport,
    arms: [OrchestrationArm]
) -> [OrchestrationArm: PairedConditionalOverheadSummary] {
    let results = report.perCaseResults.values
        .flatMap { $0 }
        .filter { !$0.isWarmup && $0.tags.contains("conditional-latency") }
    return pairedConditionalOverheadSummaries(results: results, arms: arms)
}

private func pairedConditionalExitCriteria(
    results: [OrchestrationArmResult],
    arms: [OrchestrationArm]
) -> [ExitCriterionResult] {
    let conditionalResults = results.filter {
        !$0.isWarmup && $0.tags.contains("conditional-latency")
    }
    guard !conditionalResults.isEmpty else { return [] }

    let summaries = pairedConditionalOverheadSummaries(
        results: conditionalResults,
        arms: arms
    )
    let actual = arms.map { arm in
        let invalid = summaries[arm]?.incorrectOrMissingPairCount ?? 0
        let correct = summaries[arm]?.correctPairCount ?? 0
        return "\(arm.rawValue)=\(correct) ok/\(invalid) bad"
    }.joined(separator: ", ")
    let passed = arms.allSatisfy { arm in
        guard let summary = summaries[arm] else { return false }
        return summary.correctPairCount > 0 && summary.incorrectOrMissingPairCount == 0
    }

    return [
        ExitCriterionResult(
            name: "Paired conditional correctness",
            threshold: "each arm has >0 correct pairs and 0 incorrect/missing pairs",
            actual: actual,
            passed: passed
        )
    ]
}

private func pairedConditionalOverheadSummaries(
    results: [OrchestrationArmResult],
    arms: [OrchestrationArm]
) -> [OrchestrationArm: PairedConditionalOverheadSummary] {
    guard !results.isEmpty else { return [:] }

    var summaries: [OrchestrationArm: PairedConditionalOverheadSummary] = [:]
    for arm in arms {
        let armResults = results.filter { $0.arm == arm }
        let pairIDs = Set(armResults.compactMap(pairID))
        guard !pairIDs.isEmpty else { continue }

        var addedLatencies: [Double] = []
        var addedFMCalls: [Double] = []
        var invalidPairs = 0

        for currentPairID in pairIDs {
            let pairResults = armResults.filter { pairID(for: $0) == currentPairID }
            let repetitions = Set(pairResults.map(\.repetitionIndex))
            for repetition in repetitions {
                let repetitionResults = pairResults.filter { $0.repetitionIndex == repetition }
                guard let base = repetitionResults.first(where: { $0.tags.contains("base") }),
                      let conditioned = repetitionResults.first(where: { $0.tags.contains("conditioned") }),
                      base.passed,
                      conditioned.passed else {
                    invalidPairs += 1
                    continue
                }
                addedLatencies.append(conditioned.durationMs - base.durationMs)
                addedFMCalls.append(Double(conditioned.modelCallCount - base.modelCallCount))
            }
        }

        let sortedLatencies = addedLatencies.sorted()
        summaries[arm] = PairedConditionalOverheadSummary(
            correctPairCount: addedLatencies.count,
            incorrectOrMissingPairCount: invalidPairs,
            meanAddedLatencyMs: mean(addedLatencies),
            p50AddedLatencyMs: percentile(sortedLatencies, p: 0.50),
            p95AddedLatencyMs: percentile(sortedLatencies, p: 0.95),
            meanAddedFMCalls: mean(addedFMCalls)
        )
    }
    return summaries
}

private func pairID(for result: OrchestrationArmResult) -> String? {
    result.tags.first { $0.hasPrefix("pair:") }?.replacingOccurrences(of: "pair:", with: "")
}

private func mean(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    return values.reduce(0, +) / Double(values.count)
}

private func percentile(_ sorted: [Double], p: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let index = p * Double(sorted.count - 1)
    let lower = Int(index)
    let upper = min(lower + 1, sorted.count - 1)
    let fraction = index - Double(lower)
    return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
}
