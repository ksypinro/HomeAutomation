import Foundation
import HomeAutomationCore

public enum PortfolioFeatureSchema {
    public static let currentVersion = 1
}

public enum PortfolioFeatureAvailability: String, Sendable, Codable, Hashable {
    case available
    case unavailable
    case unknown
}

public enum PortfolioFeatureSource: String, Sendable, Codable, Hashable {
    case deterministicParser
    case deterministicDraftPipeline
    case registrySnapshot
    case memoryDetector
    case runtimeAvailability
    case injectedFixture
    case fallbackDefault
    case unavailable
}

public enum PortfolioMissingReason: String, Sendable, Codable, Hashable {
    case notMissing
    case unknown
    case notApplicable
    case unavailable
    case extractionFailed
}

public struct PortfolioFeatureValue<Value: Sendable & Codable & Hashable>: Sendable, Codable, Hashable {
    public let value: Value?
    public let missingReason: PortfolioMissingReason
    public let source: PortfolioFeatureSource

    public init(
        _ value: Value?,
        missingReason: PortfolioMissingReason = .notMissing,
        source: PortfolioFeatureSource
    ) {
        if value == nil {
            self.value = nil
            self.missingReason = missingReason == .notMissing ? .unknown : missingReason
        } else {
            self.value = value
            self.missingReason = missingReason
        }
        self.source = source
    }

    public static func present(_ value: Value, source: PortfolioFeatureSource) -> Self {
        Self(value, source: source)
    }

    public static func missing(
        _ reason: PortfolioMissingReason,
        source: PortfolioFeatureSource
    ) -> Self {
        Self(nil, missingReason: reason, source: source)
    }
}

public enum PortfolioTextSizeBucket: String, Sendable, Codable, Hashable {
    case empty
    case short
    case medium
    case long
    case veryLong

    public init(characterCount: Int) {
        switch characterCount {
        case ..<1:
            self = .empty
        case 1...80:
            self = .short
        case 81...240:
            self = .medium
        case 241...800:
            self = .long
        default:
            self = .veryLong
        }
    }
}

public enum PortfolioOODSignal: String, Sendable, Codable, Hashable {
    case inDomain
    case mixedLanguage
    case unsupportedLanguage
    case unsupportedDomain
    case lowConfidence
    case unknown
}

public enum PortfolioWarmStateHint: String, Sendable, Codable, Hashable {
    case unknown
    case likelyCold
    case likelyWarm
}

public enum PortfolioGateDepthBucket: String, Sendable, Codable, Hashable {
    case none
    case shallow
    case moderate
    case deep
    case unknown
}

public struct PortfolioFeatureSnapshot: Sendable, Codable, Hashable {
    public let featureSchemaVersion: Int
    public let operation: PortfolioFeatureValue<HomeAutomationOperationKind>
    public let operationConfidence: PortfolioFeatureValue<Double>
    public let languageOODSignal: PortfolioFeatureValue<PortfolioOODSignal>
    public let textSizeBucket: PortfolioFeatureValue<PortfolioTextSizeBucket>
    public let actionCount: PortfolioFeatureValue<Int>
    public let conditionCount: PortfolioFeatureValue<Int>
    public let minimumFieldConfidence: PortfolioFeatureValue<Double>
    public let p50FieldConfidence: PortfolioFeatureValue<Double>
    public let p90FieldConfidence: PortfolioFeatureValue<Double>
    public let candidateCount: PortfolioFeatureValue<Int>
    public let candidateTopTwoMargin: PortfolioFeatureValue<Double>
    public let unsupportedFragmentCount: PortfolioFeatureValue<Int>
    public let precedenceAmbiguity: PortfolioFeatureValue<Bool>
    public let riskFloor: PortfolioFeatureValue<HomeAutomationRiskLevel>
    public let memoryReference: PortfolioFeatureValue<Bool>
    public let exactTemplateMatch: PortfolioFeatureValue<Bool>
    public let foundationModelAvailability: PortfolioFeatureValue<PortfolioFeatureAvailability>
    public let ragAvailability: PortfolioFeatureValue<PortfolioFeatureAvailability>
    public let gateDepth: PortfolioFeatureValue<PortfolioGateDepthBucket>
    public let warmStateHint: PortfolioFeatureValue<PortfolioWarmStateHint>
    public let extractionDurationMs: Double

    public init(
        featureSchemaVersion: Int = PortfolioFeatureSchema.currentVersion,
        operation: PortfolioFeatureValue<HomeAutomationOperationKind>,
        operationConfidence: PortfolioFeatureValue<Double>,
        languageOODSignal: PortfolioFeatureValue<PortfolioOODSignal>,
        textSizeBucket: PortfolioFeatureValue<PortfolioTextSizeBucket>,
        actionCount: PortfolioFeatureValue<Int>,
        conditionCount: PortfolioFeatureValue<Int>,
        minimumFieldConfidence: PortfolioFeatureValue<Double>,
        p50FieldConfidence: PortfolioFeatureValue<Double>,
        p90FieldConfidence: PortfolioFeatureValue<Double>,
        candidateCount: PortfolioFeatureValue<Int>,
        candidateTopTwoMargin: PortfolioFeatureValue<Double>,
        unsupportedFragmentCount: PortfolioFeatureValue<Int>,
        precedenceAmbiguity: PortfolioFeatureValue<Bool>,
        riskFloor: PortfolioFeatureValue<HomeAutomationRiskLevel>,
        memoryReference: PortfolioFeatureValue<Bool>,
        exactTemplateMatch: PortfolioFeatureValue<Bool>,
        foundationModelAvailability: PortfolioFeatureValue<PortfolioFeatureAvailability>,
        ragAvailability: PortfolioFeatureValue<PortfolioFeatureAvailability>,
        gateDepth: PortfolioFeatureValue<PortfolioGateDepthBucket>,
        warmStateHint: PortfolioFeatureValue<PortfolioWarmStateHint>,
        extractionDurationMs: Double
    ) {
        self.featureSchemaVersion = featureSchemaVersion
        self.operation = operation
        self.operationConfidence = operationConfidence
        self.languageOODSignal = languageOODSignal
        self.textSizeBucket = textSizeBucket
        self.actionCount = actionCount
        self.conditionCount = conditionCount
        self.minimumFieldConfidence = minimumFieldConfidence
        self.p50FieldConfidence = p50FieldConfidence
        self.p90FieldConfidence = p90FieldConfidence
        self.candidateCount = candidateCount
        self.candidateTopTwoMargin = candidateTopTwoMargin
        self.unsupportedFragmentCount = unsupportedFragmentCount
        self.precedenceAmbiguity = precedenceAmbiguity
        self.riskFloor = riskFloor
        self.memoryReference = memoryReference
        self.exactTemplateMatch = exactTemplateMatch
        self.foundationModelAvailability = foundationModelAvailability
        self.ragAvailability = ragAvailability
        self.gateDepth = gateDepth
        self.warmStateHint = warmStateHint
        self.extractionDurationMs = max(0, extractionDurationMs)
    }

    public func validateSchemaVersion(
        expected expectedVersion: Int = PortfolioFeatureSchema.currentVersion
    ) throws {
        guard featureSchemaVersion == expectedVersion else {
            throw PortfolioFeatureSnapshotError.schemaMismatch(
                expected: expectedVersion,
                actual: featureSchemaVersion
            )
        }
    }
}

public enum PortfolioFeatureSnapshotError: Error, Sendable, Hashable, LocalizedError {
    case schemaMismatch(expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case .schemaMismatch(let expected, let actual):
            "Portfolio feature schema mismatch: expected \(expected), got \(actual)"
        }
    }
}
