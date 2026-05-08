import Foundation
import os

public struct LegacyResolutionMetrics: Sendable, Codable, Equatable {
    public var command: String
    public var engine: String
    public var startedAt: Date
    public var finishedAt: Date?
    public var foundationModelAvailable: Bool
    public var usedRuleBasedFallback: Bool
    public var usedFoundationModels: Bool
    public var candidateStrategy: String
    public var retrievedCandidateCount: Int
    public var selectedCandidateIDs: [String]
    public var workerConfidence: Double
    public var candidateConfidence: Double
    public var draftConfidence: Double?
    public var riskLevel: String
    public var outcome: String
    public var requiresConfirmation: Bool
    public var executed: Bool
    public var falseExecutionRiskTracked: Bool
    public var fallbackReason: String?
    public var failureDescription: String?
    public var selectedToolNames: [String]
    public var adapterLoadAttempted: Bool
    public var adapterLoadSucceeded: Bool
    public var adapterLoadErrorDescription: String?
    public var draftAttemptCount: Int
    public var draftAttemptSummaries: [String]
    public var bestDraftAttempt: String?
    public var emittedEventCount: Int
    public var workerDuration: Double?
    public var retrievalDuration: Double?
    public var candidateResolutionDuration: Double?
    public var hydrationDuration: Double?
    public var draftResolutionDuration: Double?
    public var validationDuration: Double?
    public var executionDuration: Double?
    public var totalDuration: Double?
    public var stageDurations: [String: Double]

    public init(
        command: String,
        foundationModelAvailable: Bool
    ) {
        self.command = command
        self.engine = "legacy Resolver"
        self.startedAt = Date()
        self.finishedAt = nil
        self.foundationModelAvailable = foundationModelAvailable
        self.usedRuleBasedFallback = false
        self.usedFoundationModels = false
        self.candidateStrategy = "none"
        self.retrievedCandidateCount = 0
        self.selectedCandidateIDs = []
        self.workerConfidence = 0
        self.candidateConfidence = 0
        self.draftConfidence = nil
        self.riskLevel = "unknown"
        self.outcome = "started"
        self.requiresConfirmation = false
        self.executed = false
        self.falseExecutionRiskTracked = false
        self.fallbackReason = nil
        self.failureDescription = nil
        self.selectedToolNames = []
        self.adapterLoadAttempted = false
        self.adapterLoadSucceeded = false
        self.adapterLoadErrorDescription = nil
        self.draftAttemptCount = 0
        self.draftAttemptSummaries = []
        self.bestDraftAttempt = nil
        self.emittedEventCount = 0
        self.workerDuration = nil
        self.retrievalDuration = nil
        self.candidateResolutionDuration = nil
        self.hydrationDuration = nil
        self.draftResolutionDuration = nil
        self.validationDuration = nil
        self.executionDuration = nil
        self.totalDuration = nil
        self.stageDurations = [:]
    }

    public var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let value = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return value
    }
}

public actor LegacyMetricsCollector {
    private let logger = Logger(subsystem: "HomeAutomation", category: "LegacyResolver")
    private var lastMetrics: LegacyResolutionMetrics?

    public init() {}

    public func store(_ metrics: LegacyResolutionMetrics) {
        lastMetrics = metrics
        logger.info("legacy outcome: \(metrics.outcome, privacy: .public), candidates: \(metrics.retrievedCandidateCount, privacy: .public), strategy: \(metrics.candidateStrategy, privacy: .public)")
    }

    public func lastMetricsJSON() -> String? {
        lastMetrics?.jsonString
    }

    public func lastMetricsValue() -> LegacyResolutionMetrics? {
        lastMetrics
    }
}

struct LegacyStageTimer {
    private let start = Date()

    func elapsedSeconds() -> Double {
        Date().timeIntervalSince(start)
    }
}
