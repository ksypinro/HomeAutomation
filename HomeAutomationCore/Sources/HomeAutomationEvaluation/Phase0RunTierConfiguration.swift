import Foundation
import FoundationModels

/// Phase 0 baseline run tier configuration.
/// Defines warmup, measurement, and validation requirements for each tier.
public enum Phase0RunTier: String, Sendable, CaseIterable {
    case prDeterministic = "pr-deterministic"
    case liveSmoke = "live-smoke"
    case release = "release"

    public var description: String {
        switch self {
        case .prDeterministic:
            return "PR deterministic (no model required, assertion-only)"
        case .liveSmoke:
            return "Live smoke (model required, 5 reps)"
        case .release:
            return "Release (model required, 10+ reps, strict validation)"
        }
    }

    public var requiresLiveModel: Bool {
        switch self {
        case .prDeterministic:
            return false
        case .liveSmoke, .release:
            return true
        }
    }

    public var warmupRepetitions: Int {
        switch self {
        case .prDeterministic, .liveSmoke:
            return 1
        case .release:
            return 2
        }
    }

    public var measuredRepetitions: Int {
        switch self {
        case .prDeterministic:
            return 3
        case .liveSmoke:
            return 5
        case .release:
            return 10
        }
    }

    public var hasLatencyGate: Bool {
        switch self {
        case .prDeterministic:
            return false
        case .liveSmoke, .release:
            return true
        }
    }

    public var requiredStrategies: [OrchestrationArm] {
        switch self {
        case .prDeterministic:
            return [.graph, .graphWithTier1, .verifierLoop]
        case .liveSmoke:
            return [.graph, .graphWithTier1, .verifierLoop, .adaptiveStatic, .adaptiveShadow]
        case .release:
            return [.graph, .graphWithTier1, .verifierLoop, .adaptiveStatic, .adaptiveShadow]
        }
    }

    public var requiredCorrectnessCases: Int {
        switch self {
        case .prDeterministic:
            return 0 // assertions only
        case .liveSmoke:
            return 5 // representative subset
        case .release:
            return 9 // full corpus
        }
    }

    public var validateCompilation: Bool {
        switch self {
        case .prDeterministic:
            return false
        case .liveSmoke:
            return true
        case .release:
            return true
        }
    }
}

/// Phase 0 baseline run configuration.
public struct Phase0BaselineConfiguration: Sendable {
    public let tier: Phase0RunTier
    public let corpusID: String = "conditional-latency-v1"
    public let randomizeStrategyOrder: Bool
    public let validateModelAvailability: Bool

    public init(
        tier: Phase0RunTier = .prDeterministic,
        randomizeStrategyOrder: Bool = false,
        validateModelAvailability: Bool = true
    ) {
        self.tier = tier
        self.randomizeStrategyOrder = randomizeStrategyOrder
        self.validateModelAvailability = validateModelAvailability
    }

    /// Validate configuration against runtime constraints.
    public func validate() throws {
        if tier.requiresLiveModel && validateModelAvailability {
            guard SystemLanguageModel.default.isAvailable else {
                throw ConfigurationError.modelUnavailable("Tier '\(tier.rawValue)' requires model, but model is unavailable")
            }
        }
    }
}

public enum ConfigurationError: LocalizedError {
    case modelUnavailable(String)
    case invalidTier(String)

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable(let msg):
            return msg
        case .invalidTier(let msg):
            return msg
        }
    }
}

/// Phase 0 exit gate thresholds (from Phase 0 spec).
public struct Phase0ExitGateThresholds: Sendable {
    /// Deterministic-complete condition overhead: p50 ≤ 150ms, p95 ≤ 500ms
    public let conditionP50MaxMs: Double = 150
    public let conditionP95MaxMs: Double = 500

    /// Condition overhead ratio: p95 ≤ 1.20× baseline
    public let conditionP95Ratio: Double = 1.20

    /// No-condition regression cap: ≤ 5% (rollback at 10%)
    public let noConditionRegressionCap: Double = 0.05
    public let noConditionRollbackThreshold: Double = 0.10

    /// Clarification rate increase cap: ≤ 3pp for residual cohorts
    public let clarificationRateIncreaseCap: Double = 0.03

    /// 100% semantic parity required
    public let requireExactSemanticParity: Bool = true
    public let requireExactCompilationParity: Bool = true
}
