import Foundation
import HomeAutomationCore
import HomeAutomationOrchestrator

public struct PortfolioTrainingUtilityWeights: Sendable, Codable, Hashable {
    public let p95LatencyWeight: Double
    public let callWeight: Double
    public let queueWaitWeight: Double
    public let escalationWeight: Double
    public let uncertaintyWeight: Double

    public init(
        p95LatencyWeight: Double = 0.0004,
        callWeight: Double = 0.04,
        queueWaitWeight: Double = 0.0002,
        escalationWeight: Double = 0.25,
        uncertaintyWeight: Double = 0.10
    ) {
        self.p95LatencyWeight = p95LatencyWeight
        self.callWeight = callWeight
        self.queueWaitWeight = queueWaitWeight
        self.escalationWeight = escalationWeight
        self.uncertaintyWeight = uncertaintyWeight
    }
}

public struct PortfolioTrainingRow: Sendable, Codable, Hashable {
    public let datasetID: String
    public let caseID: String
    public let arm: FoundationModelCallArm
    public let features: PortfolioFeatureSnapshot
    public let eligible: Bool
    public let rejectionReasons: [PortfolioRejectionReason]
    public let correctness: Double
    public let durationMs: Double
    public let durationP95Ms: Double
    public let actualModelCalls: Int
    public let queueWaitMs: Double
    public let escalated: Bool
    public let clarification: Bool
    public let confirmation: Bool
    public let failed: Bool
    public let safetyFailure: Bool
    public let utility: Double

    public init(
        datasetID: String,
        caseID: String,
        arm: FoundationModelCallArm,
        features: PortfolioFeatureSnapshot,
        eligible: Bool,
        rejectionReasons: [PortfolioRejectionReason],
        correctness: Double,
        durationMs: Double,
        durationP95Ms: Double,
        actualModelCalls: Int,
        queueWaitMs: Double,
        escalated: Bool,
        clarification: Bool,
        confirmation: Bool,
        failed: Bool,
        safetyFailure: Bool,
        utility: Double
    ) {
        self.datasetID = datasetID
        self.caseID = caseID
        self.arm = arm
        self.features = features
        self.eligible = eligible
        self.rejectionReasons = rejectionReasons
        self.correctness = min(1, max(0, correctness))
        self.durationMs = max(0, durationMs)
        self.durationP95Ms = max(0, durationP95Ms)
        self.actualModelCalls = max(0, actualModelCalls)
        self.queueWaitMs = max(0, queueWaitMs)
        self.escalated = escalated
        self.clarification = clarification
        self.confirmation = confirmation
        self.failed = failed
        self.safetyFailure = safetyFailure
        self.utility = utility
    }
}

public struct PortfolioTrainingDataset: Sendable, Codable, Hashable {
    public let datasetID: String
    public let generatedAt: Date
    public let featureSchemaVersion: Int
    public let utilityWeights: PortfolioTrainingUtilityWeights
    public let rows: [PortfolioTrainingRow]

    public init(
        datasetID: String,
        generatedAt: Date = Date(),
        featureSchemaVersion: Int = PortfolioFeatureSchema.currentVersion,
        utilityWeights: PortfolioTrainingUtilityWeights = PortfolioTrainingUtilityWeights(),
        rows: [PortfolioTrainingRow]
    ) {
        self.datasetID = datasetID
        self.generatedAt = generatedAt
        self.featureSchemaVersion = featureSchemaVersion
        self.utilityWeights = utilityWeights
        self.rows = rows
    }

    public static func make(
        from report: OrchestrationComparisonReport,
        datasetID: String? = nil,
        utilityWeights: PortfolioTrainingUtilityWeights = PortfolioTrainingUtilityWeights()
    ) -> PortfolioTrainingDataset {
        let id = datasetID ?? "portfolio-training-\(report.seed)-\(report.caseCount)-\(report.repetitions)"
        let nonWarmup = report.perCaseResults.mapValues { $0.filter { !$0.isWarmup } }
        let p95ByCaseArm = Self.p95ByCaseArm(nonWarmup)

        var rows: [PortfolioTrainingRow] = []
        for caseID in nonWarmup.keys.sorted() {
            guard let results = nonWarmup[caseID] else { continue }
            for result in results.sorted(by: { $0.arm.rawValue < $1.arm.rawValue }) {
                guard let portfolioArm = result.arm.portfolioArm else { continue }
                let features = conservativeFeatureSnapshot(from: result)
                let eligible = !result.requiresFinalizationReceipt || result.finalizationReceiptStatus == FinalizationReceiptStatus.completed.rawValue
                let safetyFailure = result.requiresFinalizationReceipt && result.finalizationReceiptStatus != FinalizationReceiptStatus.completed.rawValue
                let rejectionReasons: [PortfolioRejectionReason] = safetyFailure ? [.finalizerReadinessUnknown] : []
                let p95 = p95ByCaseArm["\(caseID)|\(result.arm.rawValue)"] ?? result.durationMs
                let utility = Self.utility(
                    correctness: result.passed ? 1 : 0,
                    p95LatencyMs: p95,
                    calls: result.modelCallCount,
                    queueWaitMs: result.fmQueueWaitMs,
                    escalated: result.escalated,
                    uncertainty: features.languageOODSignal.value == .inDomain ? 0 : 1,
                    safetyFailure: safetyFailure,
                    weights: utilityWeights
                )
                rows.append(PortfolioTrainingRow(
                    datasetID: id,
                    caseID: caseID,
                    arm: portfolioArm,
                    features: features,
                    eligible: eligible,
                    rejectionReasons: rejectionReasons,
                    correctness: result.passed ? 1 : 0,
                    durationMs: result.durationMs,
                    durationP95Ms: p95,
                    actualModelCalls: result.modelCallCount,
                    queueWaitMs: result.fmQueueWaitMs,
                    escalated: result.escalated,
                    clarification: result.clarification,
                    confirmation: result.confirmation,
                    failed: !result.passed,
                    safetyFailure: safetyFailure,
                    utility: utility
                ))
            }
        }

        return PortfolioTrainingDataset(
            datasetID: id,
            generatedAt: report.generatedAt,
            utilityWeights: utilityWeights,
            rows: rows
        )
    }

    public static func utility(
        correctness: Double,
        p95LatencyMs: Double,
        calls: Int,
        queueWaitMs: Double,
        escalated: Bool,
        uncertainty: Double,
        safetyFailure: Bool,
        weights: PortfolioTrainingUtilityWeights = PortfolioTrainingUtilityWeights()
    ) -> Double {
        guard !safetyFailure else { return -.infinity }
        return correctness
            - (weights.p95LatencyWeight * max(0, p95LatencyMs))
            - (weights.callWeight * Double(max(0, calls)))
            - (weights.queueWaitWeight * max(0, queueWaitMs))
            - (escalated ? weights.escalationWeight : 0)
            - (weights.uncertaintyWeight * min(1, max(0, uncertainty)))
    }

    public static func write(_ dataset: PortfolioTrainingDataset, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(dataset).write(to: url)
    }

    public static func load(from url: URL) throws -> PortfolioTrainingDataset {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PortfolioTrainingDataset.self, from: Data(contentsOf: url))
    }

    private static func p95ByCaseArm(_ results: [String: [OrchestrationArmResult]]) -> [String: Double] {
        var values: [String: [Double]] = [:]
        for (caseID, caseResults) in results {
            for result in caseResults {
                values["\(caseID)|\(result.arm.rawValue)", default: []].append(result.durationMs)
            }
        }
        return values.mapValues { durations in
            let sorted = durations.sorted()
            guard !sorted.isEmpty else { return 0 }
            let index = min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)
            return sorted[max(0, index)]
        }
    }

    private static func conservativeFeatureSnapshot(from result: OrchestrationArmResult) -> PortfolioFeatureSnapshot {
        let operation: HomeAutomationOperationKind = OrchestrationSuiteCategory(suite: result.suite) == .automation ? .automationCreation : .executeDeviceCommand
        return PortfolioFeatureSnapshot(
            operation: .present(operation, source: .injectedFixture),
            operationConfidence: .present(result.passed ? 0.90 : 0.60, source: .injectedFixture),
            languageOODSignal: .present(.inDomain, source: .injectedFixture),
            textSizeBucket: .present(PortfolioTextSizeBucket(characterCount: result.command?.count ?? 40), source: .injectedFixture),
            actionCount: .present(max(1, result.selectedDeviceIDs.count), source: .injectedFixture),
            conditionCount: .present(result.suite.lowercased().contains("condition") ? 1 : 0, source: .injectedFixture),
            minimumFieldConfidence: .present(result.passed ? 0.85 : 0.55, source: .injectedFixture),
            p50FieldConfidence: .present(result.passed ? 0.88 : 0.60, source: .injectedFixture),
            p90FieldConfidence: .present(result.passed ? 0.93 : 0.70, source: .injectedFixture),
            candidateCount: .present(max(1, result.selectedDeviceIDs.count), source: .injectedFixture),
            candidateTopTwoMargin: .present(result.passed ? 0.50 : 0.15, source: .injectedFixture),
            unsupportedFragmentCount: .present(result.outcome == .unsupported ? 1 : 0, source: .injectedFixture),
            precedenceAmbiguity: .present(false, source: .injectedFixture),
            riskFloor: .present(.low, source: .injectedFixture),
            memoryReference: .present(false, source: .injectedFixture),
            exactTemplateMatch: .present(result.modelCallCount == 0, source: .injectedFixture),
            foundationModelAvailability: .present(.unknown, source: .injectedFixture),
            ragAvailability: .present(.unknown, source: .injectedFixture),
            gateDepth: .present(result.requiresFinalizationReceipt ? .moderate : .shallow, source: .injectedFixture),
            warmStateHint: .present(result.repetitionIndex > 0 ? .likelyWarm : .likelyCold, source: .injectedFixture),
            extractionDurationMs: 0
        )
    }
}

extension OrchestrationArm {
    public var portfolioArm: FoundationModelCallArm? {
        switch self {
        case .graph: return .graph
        case .graphWithTier1: return .graphWithTier1
        case .verifierLoop: return .verifierLoop
        case .adaptiveStatic: return .graph
        case .adaptiveShadow: return .graph
        }
    }
}
