import Foundation
import HomeAutomationAgents
import HomeAutomationCore

// MARK: - VerifierLoopPolicy

public struct VerifierLoopPolicy: Sendable {
    public let maxIterations: Int
    public let maxRepairCallsPerIteration: Int
    public let requireStrictProgress: Bool
    public let escalation: EscalationStrategy

    public init(
        maxIterations: Int = 3,
        maxRepairCallsPerIteration: Int = 3,
        requireStrictProgress: Bool = true,
        escalation: EscalationStrategy = .legacyGraph
    ) {
        self.maxIterations = maxIterations
        self.maxRepairCallsPerIteration = maxRepairCallsPerIteration
        self.requireStrictProgress = requireStrictProgress
        self.escalation = escalation
    }

    public enum EscalationStrategy: String, Sendable {
        case clarify
        case legacyGraph
    }
}

// MARK: - LoopExit

public enum LoopExit: Sendable {
    case accepted(envelope: DraftEnvelope, iterations: Int)
    case clarification(envelope: DraftEnvelope, question: String, iterations: Int)
    case escalated(envelope: DraftEnvelope, reason: EscalationReason)
}

// MARK: - EscalationReason

public enum EscalationReason: String, Sendable, Hashable {
    case iterationCap
    case noProgress
    case repairLatch
    case verifierUnavailable
}

// MARK: - LoopRunMetrics

public struct LoopRunMetrics: Sendable, Codable {
    public let iterations: Int
    public let acceptedOnIteration: Int?
    public let verifierCallCount: Int
    public let repairCallCount: Int
    public let disputedFieldIDsPerIteration: [[String]]
    public let escalationReason: String?
    public let preVerifyRepairCount: Int

    public init(
        iterations: Int,
        acceptedOnIteration: Int? = nil,
        verifierCallCount: Int,
        repairCallCount: Int,
        disputedFieldIDsPerIteration: [[String]] = [],
        escalationReason: String? = nil,
        preVerifyRepairCount: Int = 0
    ) {
        self.iterations = iterations
        self.acceptedOnIteration = acceptedOnIteration
        self.verifierCallCount = verifierCallCount
        self.repairCallCount = repairCallCount
        self.disputedFieldIDsPerIteration = disputedFieldIDsPerIteration
        self.escalationReason = escalationReason
        self.preVerifyRepairCount = preVerifyRepairCount
    }
}
