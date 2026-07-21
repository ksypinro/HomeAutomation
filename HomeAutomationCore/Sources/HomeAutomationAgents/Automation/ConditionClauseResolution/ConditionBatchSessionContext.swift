import Foundation
import HomeAutomationCore

/// Session context for batched condition resolution.
/// Manages prompt budgeting, device union, and session reuse tracking.
public struct ConditionBatchSessionContext: Sendable {
    /// Maximum characters allowed in condition batch prompt (hard budget).
    public static let maxPromptCharacters = 8000

    /// Device union: all unique devices mentioned across residual conditions.
    public let relevantDevices: [HomeCandidateRecord]
    /// Sum of per-clause device counts.
    public let totalDeviceReferences: Int
    /// Instruction text size.
    public let instructionCharacters: Int
    /// Estimated prompt (devices + instructions + clauses).
    public let estimatedPromptCharacters: Int
    /// Whether prompt fits within hard budget.
    public let fitsWithinBudget: Bool
    /// Session reuse strategy: lazy (acquire if available), idempotent (reuse without warmup).
    public let sessionReuseStrategy: SessionReuseStrategy

    public enum SessionReuseStrategy: String, Sendable {
        case lazy
        case idempotent
        case alwaysNew
    }

    public init(
        relevantDevices: [HomeCandidateRecord],
        instructionCharacters: Int,
        estimatedPromptCharacters: Int
    ) {
        self.relevantDevices = relevantDevices
        self.totalDeviceReferences = relevantDevices.count
        self.instructionCharacters = instructionCharacters
        self.estimatedPromptCharacters = estimatedPromptCharacters
        self.fitsWithinBudget = estimatedPromptCharacters <= Self.maxPromptCharacters

        // Lazy reuse for most cases; idempotent only if very small
        if estimatedPromptCharacters < 2000 {
            self.sessionReuseStrategy = .idempotent
        } else {
            self.sessionReuseStrategy = .lazy
        }
    }
}

/// Distinct job kind for condition batch resolution (separate from single-condition).
public enum ConditionBatchJobKind: String, Sendable {
    case residualBatch = "automationConditionClauseResolution.residualBatch"
}

/// Session reuse tracking for telemetry.
public struct SessionReuseEvent: Sendable {
    public let sessionKind: String
    public let reuseStrategy: ConditionBatchSessionContext.SessionReuseStrategy
    public let wasReused: Bool
    public let warmupRequired: Bool
    public let durationMs: Double

    public init(
        sessionKind: String,
        reuseStrategy: ConditionBatchSessionContext.SessionReuseStrategy,
        wasReused: Bool,
        warmupRequired: Bool,
        durationMs: Double
    ) {
        self.sessionKind = sessionKind
        self.reuseStrategy = reuseStrategy
        self.wasReused = wasReused
        self.warmupRequired = warmupRequired
        self.durationMs = durationMs
    }
}
