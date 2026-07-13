import Foundation

public enum AdaptiveReleaseGateKind: String, Sendable, Codable, Hashable, CaseIterable {
    case deterministicCI
    case goldenDataset
    case traceContracts
    case graphValidation
    case routerEligibility
    case hardwareColdWarm
    case hardwareConcurrency
    case canaryHoldback
    case rollbackDrill
}

public struct AdaptiveReleaseGateResult: Sendable, Codable, Hashable {
    public let kind: AdaptiveReleaseGateKind
    public let name: String
    public let threshold: String
    public let actual: String
    public let passed: Bool

    public init(
        kind: AdaptiveReleaseGateKind,
        name: String,
        threshold: String,
        actual: String,
        passed: Bool
    ) {
        self.kind = kind
        self.name = name
        self.threshold = threshold
        self.actual = actual
        self.passed = passed
    }
}

public struct AdaptiveReleaseGateReport: Sendable, Codable, Hashable {
    public let generatedAt: Date
    public let configVersion: String
    public let rolloutMode: String
    public let results: [AdaptiveReleaseGateResult]

    public init(
        generatedAt: Date = Date(),
        configVersion: String,
        rolloutMode: String,
        results: [AdaptiveReleaseGateResult]
    ) {
        self.generatedAt = generatedAt
        self.configVersion = configVersion
        self.rolloutMode = rolloutMode
        self.results = results
    }

    public var passed: Bool {
        results.allSatisfy(\.passed)
    }

    public static func make(
        comparison: OrchestrationComparisonReport? = nil,
        router: PortfolioRouterEvaluationReport? = nil,
        configVersion: String = "local",
        rolloutMode: String = "disabled",
        rollbackDrillPassed: Bool = false,
        hardwareGatePassed: Bool = false
    ) -> AdaptiveReleaseGateReport {
        var results: [AdaptiveReleaseGateResult] = []
        let comparisonPassed = comparison?.exitCriteriaResults.allSatisfy(\.passed) ?? false
        results.append(AdaptiveReleaseGateResult(
            kind: .deterministicCI,
            name: "Deterministic CI gates",
            threshold: "all orchestration exit criteria pass",
            actual: comparison == nil ? "missing comparison report" : "\(comparison!.exitCriteriaResults.filter(\.passed).count)/\(comparison!.exitCriteriaResults.count)",
            passed: comparisonPassed
        ))
        results.append(AdaptiveReleaseGateResult(
            kind: .routerEligibility,
            name: "Router regret and safety",
            threshold: "mean regret ≤ 0.05, max regret ≤ 0.15, unsafe selections = 0",
            actual: router.map { String(format: "mean=%.4f max=%.4f unsafe=%d", $0.meanRegret, $0.maxRegret, $0.unsafeSelectionCount) } ?? "missing router report",
            passed: router.map { $0.meanRegret <= 0.05 && $0.maxRegret <= 0.15 && $0.unsafeSelectionCount == 0 } ?? false
        ))
        results.append(AdaptiveReleaseGateResult(
            kind: .hardwareColdWarm,
            name: "Hardware cold/warm live-model gates",
            threshold: "counterbalanced live suite attached and passing",
            actual: hardwareGatePassed ? "passing" : "missing or failing",
            passed: hardwareGatePassed
        ))
        results.append(AdaptiveReleaseGateResult(
            kind: .rollbackDrill,
            name: "Rollback drill",
            threshold: "graph fallback switch returns new runs to graph without restart",
            actual: rollbackDrillPassed ? "passing" : "not proven",
            passed: rollbackDrillPassed
        ))
        results.append(AdaptiveReleaseGateResult(
            kind: .canaryHoldback,
            name: "Graph holdback",
            threshold: "≥10% graph holdback retained for adaptive rollout",
            actual: "configured outside report",
            passed: rolloutMode == "disabled" || rolloutMode.hasPrefix("shadow")
        ))
        return AdaptiveReleaseGateReport(
            configVersion: configVersion,
            rolloutMode: rolloutMode,
            results: results
        )
    }

    public static func write(_ report: AdaptiveReleaseGateReport, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: url)
    }
}
