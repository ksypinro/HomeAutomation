import Foundation
import HomeAutomationCore

public struct PortfolioCalibrationMetadata: Sendable, Codable, Hashable {
    public let method: String
    public let sampleCount: Int
    public let expectedCalibrationError: Double

    public init(
        method: String = "none",
        sampleCount: Int = 0,
        expectedCalibrationError: Double = 0
    ) {
        self.method = method
        self.sampleCount = max(0, sampleCount)
        self.expectedCalibrationError = max(0, expectedCalibrationError)
    }
}

public struct PortfolioLinearUtilityCoefficients: Sendable, Codable, Hashable {
    public let intercept: Double
    public let operationWeights: [String: Double]
    public let textSizeWeights: [String: Double]
    public let riskWeights: [String: Double]
    public let actionCountWeight: Double
    public let conditionCountWeight: Double
    public let candidateCountWeight: Double
    public let confidenceWeight: Double
    public let candidateMarginWeight: Double
    public let memoryReferenceWeight: Double
    public let exactTemplateWeight: Double
    public let warmStateWeights: [String: Double]
    public let oodPenalty: Double
    public let unavailableModelPenalty: Double

    public init(
        intercept: Double = 0,
        operationWeights: [String: Double] = [:],
        textSizeWeights: [String: Double] = [:],
        riskWeights: [String: Double] = [:],
        actionCountWeight: Double = 0,
        conditionCountWeight: Double = 0,
        candidateCountWeight: Double = 0,
        confidenceWeight: Double = 0,
        candidateMarginWeight: Double = 0,
        memoryReferenceWeight: Double = 0,
        exactTemplateWeight: Double = 0,
        warmStateWeights: [String: Double] = [:],
        oodPenalty: Double = 0,
        unavailableModelPenalty: Double = 0
    ) {
        self.intercept = intercept
        self.operationWeights = operationWeights
        self.textSizeWeights = textSizeWeights
        self.riskWeights = riskWeights
        self.actionCountWeight = actionCountWeight
        self.conditionCountWeight = conditionCountWeight
        self.candidateCountWeight = candidateCountWeight
        self.confidenceWeight = confidenceWeight
        self.candidateMarginWeight = candidateMarginWeight
        self.memoryReferenceWeight = memoryReferenceWeight
        self.exactTemplateWeight = exactTemplateWeight
        self.warmStateWeights = warmStateWeights
        self.oodPenalty = oodPenalty
        self.unavailableModelPenalty = unavailableModelPenalty
    }

    public func score(_ features: PortfolioFeatureSnapshot) -> Double {
        var value = intercept
        if let operation = features.operation.value {
            value += operationWeights[operation.rawValue, default: 0]
        }
        if let textSize = features.textSizeBucket.value {
            value += textSizeWeights[textSize.rawValue, default: 0]
        }
        if let risk = features.riskFloor.value {
            value += riskWeights[String(describing: risk), default: 0]
        }
        if let actionCount = features.actionCount.value {
            value += Double(actionCount) * actionCountWeight
        }
        if let conditionCount = features.conditionCount.value {
            value += Double(conditionCount) * conditionCountWeight
        }
        if let candidateCount = features.candidateCount.value {
            value += Double(candidateCount) * candidateCountWeight
        }
        if let operationConfidence = features.operationConfidence.value {
            value += operationConfidence * confidenceWeight
        }
        if let margin = features.candidateTopTwoMargin.value {
            value += margin * candidateMarginWeight
        }
        if features.memoryReference.value == true {
            value += memoryReferenceWeight
        }
        if features.exactTemplateMatch.value == true {
            value += exactTemplateWeight
        }
        if let warmState = features.warmStateHint.value {
            value += warmStateWeights[warmState.rawValue, default: 0]
        }
        if features.languageOODSignal.value != .inDomain {
            value -= oodPenalty
        }
        if features.foundationModelAvailability.value == .unavailable {
            value -= unavailableModelPenalty
        }
        return value
    }
}

public struct PortfolioArmModel: Sendable, Codable, Hashable {
    public let arm: FoundationModelCallArm
    public let coefficients: PortfolioLinearUtilityCoefficients
    public let calibration: PortfolioCalibrationMetadata

    public init(
        arm: FoundationModelCallArm,
        coefficients: PortfolioLinearUtilityCoefficients,
        calibration: PortfolioCalibrationMetadata = PortfolioCalibrationMetadata()
    ) {
        self.arm = arm
        self.coefficients = coefficients
        self.calibration = calibration
    }

    public func score(_ features: PortfolioFeatureSnapshot) -> Double {
        coefficients.score(features)
    }
}

public struct PortfolioModelArtifact: Sendable, Codable, Hashable {
    public static let currentArtifactVersion = 1

    public let artifactVersion: Int
    public let modelVersion: String
    public let featureSchemaVersion: Int
    public let policyVersion: Int
    public let createdAt: Date
    public let trainingDatasetID: String
    public let minimumUtilityMargin: Double
    public let oodPolicy: String
    public let armModels: [PortfolioArmModel]
    public let calibration: PortfolioCalibrationMetadata

    public init(
        artifactVersion: Int = Self.currentArtifactVersion,
        modelVersion: String,
        featureSchemaVersion: Int = PortfolioFeatureSchema.currentVersion,
        policyVersion: Int = PortfolioEligibilityPolicy.currentPolicyVersion,
        createdAt: Date = Date(),
        trainingDatasetID: String,
        minimumUtilityMargin: Double = 0.08,
        oodPolicy: String = "reject-to-static",
        armModels: [PortfolioArmModel],
        calibration: PortfolioCalibrationMetadata = PortfolioCalibrationMetadata()
    ) {
        self.artifactVersion = artifactVersion
        self.modelVersion = modelVersion
        self.featureSchemaVersion = featureSchemaVersion
        self.policyVersion = policyVersion
        self.createdAt = createdAt
        self.trainingDatasetID = trainingDatasetID
        self.minimumUtilityMargin = max(0, minimumUtilityMargin)
        self.oodPolicy = oodPolicy
        self.armModels = armModels
        self.calibration = calibration
    }

    public func validate(
        featureSchemaVersion expectedFeatureSchemaVersion: Int = PortfolioFeatureSchema.currentVersion,
        policyVersion expectedPolicyVersion: Int = PortfolioEligibilityPolicy.currentPolicyVersion
    ) throws {
        guard artifactVersion == Self.currentArtifactVersion else {
            throw PortfolioModelArtifactError.unsupportedArtifactVersion(
                expected: Self.currentArtifactVersion,
                actual: artifactVersion
            )
        }
        guard featureSchemaVersion == expectedFeatureSchemaVersion else {
            throw PortfolioModelArtifactError.schemaMismatch(
                expected: expectedFeatureSchemaVersion,
                actual: featureSchemaVersion
            )
        }
        guard policyVersion == expectedPolicyVersion else {
            throw PortfolioModelArtifactError.policyMismatch(
                expected: expectedPolicyVersion,
                actual: policyVersion
            )
        }
    }

    public func model(for arm: FoundationModelCallArm) throws -> PortfolioArmModel {
        guard let model = armModels.first(where: { $0.arm == arm }) else {
            throw PortfolioModelArtifactError.missingArmModel(arm)
        }
        return model
    }

    public var stableFingerprint: String {
        [
            String(artifactVersion),
            modelVersion,
            String(featureSchemaVersion),
            String(policyVersion),
            trainingDatasetID,
            armModels.map { $0.arm.rawValue }.sorted().joined(separator: ",")
        ].joined(separator: "|")
    }
}

public enum PortfolioModelArtifactError: Error, Sendable, Hashable, LocalizedError {
    case unsupportedArtifactVersion(expected: Int, actual: Int)
    case schemaMismatch(expected: Int, actual: Int)
    case policyMismatch(expected: Int, actual: Int)
    case missingArmModel(FoundationModelCallArm)

    public var errorDescription: String? {
        switch self {
        case .unsupportedArtifactVersion(let expected, let actual):
            "Unsupported portfolio model artifact version: expected \(expected), got \(actual)"
        case .schemaMismatch(let expected, let actual):
            "Portfolio model feature schema mismatch: expected \(expected), got \(actual)"
        case .policyMismatch(let expected, let actual):
            "Portfolio model policy mismatch: expected \(expected), got \(actual)"
        case .missingArmModel(let arm):
            "Portfolio model artifact is missing an arm model for \(arm.rawValue)"
        }
    }
}
