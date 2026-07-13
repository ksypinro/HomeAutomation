import Foundation

public enum FoundationModelSchedulerMode: String, Sendable, Codable, Hashable {
    case legacy
    case shadow
    case active
}

public enum FMAdmissionDeadlineClass: String, Sendable, Codable, Hashable {
    case interactive
    case pipeline
    case finalizer
    case unknown
}

public enum FMAdmissionCancellationClass: String, Sendable, Codable, Hashable {
    case normal
    case cancellationResistant
    case bestEffort
    case unknown
}

public enum FMAdmissionFallbackReason: String, Sendable, Codable, Hashable {
    case none
    case legacyMode
    case shadowMode
    case missingFrontierMetadata
    case invalidFrontierScore
}

public struct FMAdmissionContext: Sendable, Codable, Hashable {
    public let schedulerMode: FoundationModelSchedulerMode?
    public let runID: String?
    public let graphID: String?
    public let nodeID: String?
    public let agentID: String?
    public let jobKind: FoundationModelJobKind?
    public let criticalPathRemainingMs: Double?
    public let estimatedServiceMs: Double?
    public let deadlineClass: FMAdmissionDeadlineClass
    public let cancellationClass: FMAdmissionCancellationClass
    public let prefixAffinityKey: String?
    public let workflowScopeID: String?

    public init(
        schedulerMode: FoundationModelSchedulerMode? = nil,
        runID: String? = nil,
        graphID: String? = nil,
        nodeID: String? = nil,
        agentID: String? = nil,
        jobKind: FoundationModelJobKind? = nil,
        criticalPathRemainingMs: Double? = nil,
        estimatedServiceMs: Double? = nil,
        deadlineClass: FMAdmissionDeadlineClass = .unknown,
        cancellationClass: FMAdmissionCancellationClass = .unknown,
        prefixAffinityKey: String? = nil,
        workflowScopeID: String? = nil
    ) {
        self.schedulerMode = schedulerMode
        self.runID = runID
        self.graphID = graphID
        self.nodeID = nodeID
        self.agentID = agentID
        self.jobKind = jobKind
        self.criticalPathRemainingMs = criticalPathRemainingMs
        self.estimatedServiceMs = estimatedServiceMs
        self.deadlineClass = deadlineClass
        self.cancellationClass = cancellationClass
        self.prefixAffinityKey = prefixAffinityKey
        self.workflowScopeID = workflowScopeID
    }

    public func merging(
        schedulerMode: FoundationModelSchedulerMode? = nil,
        runID: String? = nil,
        graphID: String? = nil,
        nodeID: String? = nil,
        agentID: String? = nil,
        jobKind: FoundationModelJobKind? = nil,
        criticalPathRemainingMs: Double? = nil,
        estimatedServiceMs: Double? = nil,
        deadlineClass: FMAdmissionDeadlineClass? = nil,
        cancellationClass: FMAdmissionCancellationClass? = nil,
        prefixAffinityKey: String? = nil,
        workflowScopeID: String? = nil
    ) -> FMAdmissionContext {
        FMAdmissionContext(
            schedulerMode: schedulerMode ?? self.schedulerMode,
            runID: runID ?? self.runID,
            graphID: graphID ?? self.graphID,
            nodeID: nodeID ?? self.nodeID,
            agentID: agentID ?? self.agentID,
            jobKind: jobKind ?? self.jobKind,
            criticalPathRemainingMs: criticalPathRemainingMs ?? self.criticalPathRemainingMs,
            estimatedServiceMs: estimatedServiceMs ?? self.estimatedServiceMs,
            deadlineClass: deadlineClass ?? self.deadlineClass,
            cancellationClass: cancellationClass ?? self.cancellationClass,
            prefixAffinityKey: prefixAffinityKey ?? self.prefixAffinityKey,
            workflowScopeID: workflowScopeID ?? self.workflowScopeID
        )
    }
}

public enum FMAdmissionContextScope {
    @TaskLocal public static var current: FMAdmissionContext?
}

public struct FMAdmissionRequest: Sendable, Codable, Hashable {
    public let requestID: UUID
    public let modelCallID: String
    public let priority: FMPriority
    public let schedulerMode: FoundationModelSchedulerMode
    public let enqueuedAtNanoseconds: UInt64
    public let sequence: UInt64
    public let runID: String?
    public let graphID: String?
    public let nodeID: String?
    public let agentID: String?
    public let jobKind: FoundationModelJobKind?
    public let criticalPathRemainingMs: Double?
    public let estimatedServiceMs: Double?
    public let deadlineClass: FMAdmissionDeadlineClass
    public let cancellationClass: FMAdmissionCancellationClass
    public let prefixAffinityKey: String?
    public let workflowScopeID: String?

    public init(
        requestID: UUID = UUID(),
        modelCallID: String = UUID().uuidString,
        priority: FMPriority,
        schedulerMode: FoundationModelSchedulerMode = .legacy,
        enqueuedAtNanoseconds: UInt64,
        sequence: UInt64 = 0,
        runID: String? = nil,
        graphID: String? = nil,
        nodeID: String? = nil,
        agentID: String? = nil,
        jobKind: FoundationModelJobKind? = nil,
        criticalPathRemainingMs: Double? = nil,
        estimatedServiceMs: Double? = nil,
        deadlineClass: FMAdmissionDeadlineClass = .unknown,
        cancellationClass: FMAdmissionCancellationClass = .unknown,
        prefixAffinityKey: String? = nil,
        workflowScopeID: String? = nil
    ) {
        self.requestID = requestID
        self.modelCallID = modelCallID
        self.priority = priority
        self.schedulerMode = schedulerMode
        self.enqueuedAtNanoseconds = enqueuedAtNanoseconds
        self.sequence = sequence
        self.runID = runID
        self.graphID = graphID
        self.nodeID = nodeID
        self.agentID = agentID
        self.jobKind = jobKind
        self.criticalPathRemainingMs = criticalPathRemainingMs
        self.estimatedServiceMs = estimatedServiceMs
        self.deadlineClass = deadlineClass
        self.cancellationClass = cancellationClass
        self.prefixAffinityKey = prefixAffinityKey
        self.workflowScopeID = workflowScopeID
    }

    public var hasFrontierMetadata: Bool {
        guard schedulerMode != .legacy else { return false }
        guard let criticalPathRemainingMs, criticalPathRemainingMs.isFinite, criticalPathRemainingMs >= 0 else {
            return false
        }
        guard let estimatedServiceMs, estimatedServiceMs.isFinite, estimatedServiceMs > 0 else {
            return false
        }
        return runID != nil || graphID != nil || nodeID != nil
    }
}

public struct FMAdmissionLease: Sendable, Codable, Hashable {
    public let leaseID: UUID
    public let requestID: UUID
    public let modelCallID: String
    public let priority: FMPriority
    public let schedulerMode: FoundationModelSchedulerMode
    public let admittedAtNanoseconds: UInt64
    public let sequence: UInt64

    public init(
        leaseID: UUID = UUID(),
        requestID: UUID,
        modelCallID: String,
        priority: FMPriority,
        schedulerMode: FoundationModelSchedulerMode,
        admittedAtNanoseconds: UInt64,
        sequence: UInt64
    ) {
        self.leaseID = leaseID
        self.requestID = requestID
        self.modelCallID = modelCallID
        self.priority = priority
        self.schedulerMode = schedulerMode
        self.admittedAtNanoseconds = admittedAtNanoseconds
        self.sequence = sequence
    }
}

public enum FMAdmissionDecision: Sendable, Equatable {
    case admitted(
        lease: FMAdmissionLease,
        queueWaitMs: Double,
        fallbackReason: FMAdmissionFallbackReason,
        shadowRank: [String]
    )
    case cancelled(queueWaitMs: Double)

    public var queueWaitMs: Double {
        switch self {
        case .admitted(_, let queueWaitMs, _, _), .cancelled(let queueWaitMs):
            queueWaitMs
        }
    }
}
