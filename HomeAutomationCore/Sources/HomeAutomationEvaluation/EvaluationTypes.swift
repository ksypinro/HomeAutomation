import Foundation
import HomeAutomationCore
import HomeAutomationOrchestrator

public enum EvaluationMode: String, Sendable, Codable, Hashable {
    case deterministic
    case live
}

public enum EvaluationAllowedOutcome: String, Sendable, Codable, Hashable {
    case ready
    case drafted
    case clarification
    case confirmation
    case unsupported
    case skipped
}

public struct EvaluationFixture: Sendable, Codable, Hashable {
    public let devices: [HomeCandidateRecord]

    public init(devices: [HomeCandidateRecord] = []) {
        self.devices = devices
    }
}

public struct EvaluationExpectedOutput: Sendable, Codable, Hashable {
    public let operation: HomeAutomationOperationKind?
    public let domain: HomeAutomationCommandDomain?
    public let languageCode: String?
    public let expectedDeviceIDs: [String]
    public let capability: String?
    public let command: String?
    public let actionCount: Int?
    public let conditionCount: Int?
    public let smartThingsJSONContains: [String]
    public let allowedOutcome: EvaluationAllowedOutcome
    public let maxDurationMs: Double?
    public let maxModelCallCount: Int?

    public init(
        operation: HomeAutomationOperationKind? = nil,
        domain: HomeAutomationCommandDomain? = nil,
        languageCode: String? = nil,
        expectedDeviceIDs: [String] = [],
        capability: String? = nil,
        command: String? = nil,
        actionCount: Int? = nil,
        conditionCount: Int? = nil,
        smartThingsJSONContains: [String] = [],
        allowedOutcome: EvaluationAllowedOutcome,
        maxDurationMs: Double? = nil,
        maxModelCallCount: Int? = nil
    ) {
        self.operation = operation
        self.domain = domain
        self.languageCode = languageCode
        self.expectedDeviceIDs = expectedDeviceIDs
        self.capability = capability
        self.command = command
        self.actionCount = actionCount
        self.conditionCount = conditionCount
        self.smartThingsJSONContains = smartThingsJSONContains
        self.allowedOutcome = allowedOutcome
        self.maxDurationMs = maxDurationMs
        self.maxModelCallCount = maxModelCallCount
    }
}

public enum EvaluationAssertion: String, Sendable, Codable, Hashable {
    case operationMatches
    case selectedDeviceMatches
    case capabilityMatches
    case commandMatches
    case outcomeAllowed
    case actionCountMatches
    case conditionCountMatches
    case smartThingsJSONContains
    case durationWithinBudget
    case modelCallWithinBudget
    case observabilityTracePresent
    case ragRecallAtK
}

public struct EvaluationCase: Sendable, Codable, Hashable {
    public let id: String
    public let suite: String
    public let tags: [String]
    public let input: String
    public let fixture: EvaluationFixture
    public let expected: EvaluationExpectedOutput

    public init(
        id: String,
        suite: String,
        tags: [String] = [],
        input: String,
        fixture: EvaluationFixture = EvaluationFixture(),
        expected: EvaluationExpectedOutput
    ) {
        self.id = id
        self.suite = suite
        self.tags = tags
        self.input = input
        self.fixture = fixture
        self.expected = expected
    }
}

public struct EvaluationCaseResult: Sendable, Codable, Hashable {
    public let id: String
    public let suite: String
    public let mode: EvaluationMode
    public let status: EvaluationAllowedOutcome
    public let passed: Bool
    public let skipped: Bool
    public let durationMs: Double
    public let traceID: String?
    public let assertionFailures: [String]
    public let selectedDeviceIDs: [String]
    public let modelCallCount: Int
    public let metrics: RunMetricsV2?

    public init(
        id: String,
        suite: String,
        mode: EvaluationMode,
        status: EvaluationAllowedOutcome,
        passed: Bool,
        skipped: Bool = false,
        durationMs: Double,
        traceID: String? = nil,
        assertionFailures: [String] = [],
        selectedDeviceIDs: [String] = [],
        modelCallCount: Int = 0,
        metrics: RunMetricsV2? = nil
    ) {
        self.id = id
        self.suite = suite
        self.mode = mode
        self.status = status
        self.passed = passed
        self.skipped = skipped
        self.durationMs = durationMs
        self.traceID = traceID
        self.assertionFailures = assertionFailures
        self.selectedDeviceIDs = selectedDeviceIDs
        self.modelCallCount = modelCallCount
        self.metrics = metrics
    }
}

public struct EvaluationSummaryMetrics: Sendable, Codable, Hashable {
    public let totalCaseCount: Int
    public let passedCaseCount: Int
    public let skippedCaseCount: Int
    public let failedCaseCount: Int
    public let passRate: Double
    public let passRateBySuite: [String: Double]
    public let exactMatchAccuracy: Double
    public let partialMatchAccuracy: Double
    public let clarificationRate: Double
    public let unsupportedRate: Double
    public let confirmationRate: Double
    public let contextWindowFailureRate: Double
    public let modelCallCount: Int
    public let averageLatencyMsBySuite: [String: Double]
    public let topFailingCaseIDs: [String]

    public static func make(from results: [EvaluationCaseResult]) -> EvaluationSummaryMetrics {
        let total = results.count
        let passed = results.filter { $0.passed && !$0.skipped }.count
        let skipped = results.filter(\.skipped).count
        let failed = total - passed - skipped
        let grouped = Dictionary(grouping: results, by: \.suite)
        let passRateBySuite = grouped.mapValues { suiteResults in
            let suiteSkipped = suiteResults.filter(\.skipped).count
            let suitePassed = suiteResults.filter { $0.passed && !$0.skipped }.count
            return ratio(suitePassed, suiteResults.count - suiteSkipped)
        }
        let averageLatencyBySuite = grouped.mapValues { suiteResults in
            suiteResults.map(\.durationMs).reduce(0, +) / Double(max(suiteResults.count, 1))
        }
        let modelCalls = results.map(\.modelCallCount).reduce(0, +)
        let contextWindowFailures = results.reduce(0) { total, result in
            total + (result.metrics?.modelCalls.contextWindowFailuresByAgent.values.reduce(0, +) ?? 0)
        }
        return EvaluationSummaryMetrics(
            totalCaseCount: total,
            passedCaseCount: passed,
            skippedCaseCount: skipped,
            failedCaseCount: failed,
            passRate: ratio(passed, total - skipped),
            passRateBySuite: passRateBySuite,
            exactMatchAccuracy: ratio(passed, total - skipped),
            partialMatchAccuracy: ratio(results.filter { $0.assertionFailures.count <= 1 && !$0.skipped }.count, total - skipped),
            clarificationRate: ratio(results.filter { $0.status == .clarification }.count, total),
            unsupportedRate: ratio(results.filter { $0.status == .unsupported }.count, total),
            confirmationRate: ratio(results.filter { $0.status == .confirmation }.count, total),
            contextWindowFailureRate: ratio(contextWindowFailures, max(modelCalls, 1)),
            modelCallCount: modelCalls,
            averageLatencyMsBySuite: averageLatencyBySuite,
            topFailingCaseIDs: results.filter { !$0.passed && !$0.skipped }.prefix(10).map(\.id)
        )
    }

    private static func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }
}

public struct EvaluationSuiteResult: Sendable, Codable, Hashable {
    public let mode: EvaluationMode
    public let generatedAt: Date
    public let results: [EvaluationCaseResult]
    public let summary: EvaluationSummaryMetrics

    public init(mode: EvaluationMode, results: [EvaluationCaseResult]) {
        self.mode = mode
        self.generatedAt = Date()
        self.results = results
        self.summary = EvaluationSummaryMetrics.make(from: results)
    }
}
