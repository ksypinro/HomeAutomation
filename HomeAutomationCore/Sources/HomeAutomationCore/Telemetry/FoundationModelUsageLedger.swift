import Foundation

public protocol FoundationModelMonotonicClock: Sendable {
    func nowNanoseconds() -> UInt64
}

public struct SystemFoundationModelMonotonicClock: FoundationModelMonotonicClock {
    public init() {}

    public func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

public enum FoundationModelCallArm: String, Sendable, Codable, Hashable {
    case graph
    case graphWithTier1
    case verifierLoop
    case exactTemplate
    case evaluation
    case unknown
}

public enum FoundationModelJobKind: String, Sendable, Codable, Hashable {
    case rootRouting
    case operationDetection
    case semanticNLU
    case slotExtraction
    case riskClassification
    case candidateResolution
    case draftGeneration
    case automationResolution
    case verifier
    case repair
    case finalization
    case evaluation
    case unknown
}

public enum FoundationModelSessionReuse: String, Sendable, Codable, Hashable {
    case fresh
    case withinRun
    case prewarmed
    case unknown
}

public enum FoundationModelAvailabilityState: String, Sendable, Codable, Hashable {
    case available
    case unavailable
    case unknown

    public init(label: String) {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "available" {
            self = .available
        } else if normalized.hasPrefix("unavailable") {
            self = .unavailable
        } else {
            self = .unknown
        }
    }
}

public enum FoundationModelEscalationStep: String, Sendable, Codable, Hashable {
    case verifierLoop
    case graph
    case finalization
}

public enum FoundationModelCallCancellationReason: String, Sendable, Codable, Hashable {
    case taskCancelledBeforeAdmission
    case taskCancelledAfterAdmission
    case admissionDeadlineExceeded
    case parentRunCancelled
    case unknown
}

public enum FoundationModelCallState: String, Sendable, Codable, Hashable {
    case enqueued
    case started
    case completed
    case failed
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: true
        case .enqueued, .started: false
        }
    }
}

public struct FoundationModelCallRequest: Sendable, Codable, Hashable {
    public let modelCallID: String
    public let arm: FoundationModelCallArm
    public let jobID: String
    public let jobKind: FoundationModelJobKind
    public let graphID: String?
    public let nodeID: String?
    public let agentID: String
    public let attempt: Int?
    public let escalationChain: [FoundationModelEscalationStep]
    public let priority: FMPriority
    public let promptCharacterCount: Int
    public let selectedToolNames: [String]
    public let sessionReuse: FoundationModelSessionReuse
    public let modelAvailability: FoundationModelAvailabilityState

    public init(
        modelCallID: String,
        arm: FoundationModelCallArm = .unknown,
        jobID: String? = nil,
        jobKind: FoundationModelJobKind = .unknown,
        graphID: String? = nil,
        nodeID: String? = nil,
        agentID: String,
        attempt: Int? = nil,
        escalationChain: [FoundationModelEscalationStep] = [],
        priority: FMPriority = .interactive,
        promptCharacterCount: Int,
        selectedToolNames: [String] = [],
        sessionReuse: FoundationModelSessionReuse = .unknown,
        modelAvailability: FoundationModelAvailabilityState = .unknown
    ) {
        self.modelCallID = modelCallID
        self.arm = arm
        self.jobID = jobID ?? modelCallID
        self.jobKind = jobKind
        self.graphID = graphID
        self.nodeID = nodeID
        self.agentID = agentID
        self.attempt = attempt
        self.escalationChain = escalationChain
        self.priority = priority
        self.promptCharacterCount = max(0, promptCharacterCount)
        self.selectedToolNames = selectedToolNames
        self.sessionReuse = sessionReuse
        self.modelAvailability = modelAvailability
    }
}

public struct FoundationModelCallLedgerEntry: Sendable, Codable, Hashable {
    public let runID: String
    public let ordinal: Int
    public let request: FoundationModelCallRequest
    public let state: FoundationModelCallState
    public let enqueuedAtNanoseconds: UInt64
    public let startedAtNanoseconds: UInt64?
    public let completedAtNanoseconds: UInt64?
    public let queueWaitMs: Double?
    public let serviceMs: Double?
    public let totalMs: Double?
    public let outputCharacterCount: Int?
    public let failureKind: FoundationModelFailureKind?
    public let cancellationReason: FoundationModelCallCancellationReason?

    public var crossedInferenceBoundary: Bool { startedAtNanoseconds != nil }
}

public struct FoundationModelUsageSummary: Sendable, Codable, Hashable {
    public let entryCount: Int
    public let actualCallCount: Int
    public let completedCallCount: Int
    public let failedCallCount: Int
    public let cancelledCallCount: Int
    public let cancelledBeforeInferenceCount: Int
    public let queueWaitTotalMs: Double
    public let serviceTotalMs: Double
    public let queueWaitP50Ms: Double
    public let queueWaitP95Ms: Double
    public let serviceP50Ms: Double
    public let serviceP95Ms: Double
    public let promptCharacterCount: Int
    public let outputCharacterCount: Int
    public let telemetryOverheadMs: Double
}

public struct FoundationModelUsageSnapshot: Sendable, Codable, Hashable {
    public let runID: String
    public let entries: [FoundationModelCallLedgerEntry]
    public let summary: FoundationModelUsageSummary
}

public enum FoundationModelUsageLedgerError: Error, Sendable, Equatable {
    case duplicateModelCallID(String)
    case unknownModelCallID(String)
    case invalidTransition(modelCallID: String, from: FoundationModelCallState, to: FoundationModelCallState)
    case invalidTimestamp(modelCallID: String)
}

public actor FoundationModelUsageLedger {
    public nonisolated let runID: String

    private struct MutableEntry: Sendable {
        let ordinal: Int
        let request: FoundationModelCallRequest
        let enqueuedAtNanoseconds: UInt64
        var state: FoundationModelCallState
        var startedAtNanoseconds: UInt64?
        var completedAtNanoseconds: UInt64?
        var queueWaitMs: Double?
        var serviceMs: Double?
        var totalMs: Double?
        var outputCharacterCount: Int?
        var failureKind: FoundationModelFailureKind?
        var cancellationReason: FoundationModelCallCancellationReason?
    }

    private var entriesByID: [String: MutableEntry] = [:]
    private var nextOrdinal = 1
    private var telemetryOverheadMs: Double = 0

    public init(runID: String) {
        self.runID = runID
    }

    @discardableResult
    public func enqueue(
        _ request: FoundationModelCallRequest,
        atNanoseconds: UInt64
    ) throws -> Int {
        guard entriesByID[request.modelCallID] == nil else {
            throw FoundationModelUsageLedgerError.duplicateModelCallID(request.modelCallID)
        }
        let ordinal = nextOrdinal
        nextOrdinal += 1
        entriesByID[request.modelCallID] = MutableEntry(
            ordinal: ordinal,
            request: request,
            enqueuedAtNanoseconds: atNanoseconds,
            state: .enqueued
        )
        return ordinal
    }

    public func start(
        modelCallID: String,
        atNanoseconds: UInt64,
        queueWaitMs: Double? = nil
    ) throws {
        var entry = try entry(for: modelCallID)
        try requireTransition(entry, to: .started)
        guard atNanoseconds >= entry.enqueuedAtNanoseconds else {
            throw FoundationModelUsageLedgerError.invalidTimestamp(modelCallID: modelCallID)
        }
        entry.state = .started
        entry.startedAtNanoseconds = atNanoseconds
        entry.queueWaitMs = queueWaitMs.map { max(0, $0) }
            ?? Self.milliseconds(from: entry.enqueuedAtNanoseconds, to: atNanoseconds)
        entriesByID[modelCallID] = entry
    }

    public func complete(
        modelCallID: String,
        atNanoseconds: UInt64,
        outputCharacterCount: Int,
        serviceStartedAtNanoseconds: UInt64? = nil
    ) throws {
        var entry = try entry(for: modelCallID)
        try requireTransition(entry, to: .completed)
        try finishTiming(
            &entry,
            modelCallID: modelCallID,
            atNanoseconds: atNanoseconds,
            serviceStartedAtNanoseconds: serviceStartedAtNanoseconds
        )
        entry.state = .completed
        entry.outputCharacterCount = max(0, outputCharacterCount)
        entriesByID[modelCallID] = entry
    }

    public func fail(
        modelCallID: String,
        atNanoseconds: UInt64,
        failureKind: FoundationModelFailureKind,
        serviceStartedAtNanoseconds: UInt64? = nil
    ) throws {
        var entry = try entry(for: modelCallID)
        try requireTransition(entry, to: .failed)
        try finishTiming(
            &entry,
            modelCallID: modelCallID,
            atNanoseconds: atNanoseconds,
            serviceStartedAtNanoseconds: serviceStartedAtNanoseconds
        )
        entry.state = .failed
        entry.failureKind = failureKind
        entriesByID[modelCallID] = entry
    }

    public func cancel(
        modelCallID: String,
        atNanoseconds: UInt64,
        reason: FoundationModelCallCancellationReason,
        serviceStartedAtNanoseconds: UInt64? = nil,
        queueWaitMs: Double? = nil
    ) throws {
        var entry = try entry(for: modelCallID)
        try requireTransition(entry, to: .cancelled)
        guard atNanoseconds >= entry.enqueuedAtNanoseconds else {
            throw FoundationModelUsageLedgerError.invalidTimestamp(modelCallID: modelCallID)
        }
        entry.state = .cancelled
        entry.completedAtNanoseconds = atNanoseconds
        entry.cancellationReason = reason
        entry.totalMs = Self.milliseconds(from: entry.enqueuedAtNanoseconds, to: atNanoseconds)
        if let actualStart = serviceStartedAtNanoseconds {
            entry.startedAtNanoseconds = actualStart
        }
        if let started = entry.startedAtNanoseconds {
            guard atNanoseconds >= started else {
                throw FoundationModelUsageLedgerError.invalidTimestamp(modelCallID: modelCallID)
            }
            entry.serviceMs = Self.milliseconds(from: started, to: atNanoseconds)
        } else {
            entry.queueWaitMs = queueWaitMs.map { max(0, $0) } ?? entry.totalMs
        }
        entriesByID[modelCallID] = entry
    }

    public func recordTelemetryOverhead(milliseconds: Double) {
        telemetryOverheadMs += max(0, milliseconds)
    }

    public func snapshot() -> FoundationModelUsageSnapshot {
        let entries = entriesByID.values
            .sorted { $0.ordinal < $1.ordinal }
            .map { entry in
                FoundationModelCallLedgerEntry(
                    runID: runID,
                    ordinal: entry.ordinal,
                    request: entry.request,
                    state: entry.state,
                    enqueuedAtNanoseconds: entry.enqueuedAtNanoseconds,
                    startedAtNanoseconds: entry.startedAtNanoseconds,
                    completedAtNanoseconds: entry.completedAtNanoseconds,
                    queueWaitMs: entry.queueWaitMs,
                    serviceMs: entry.serviceMs,
                    totalMs: entry.totalMs,
                    outputCharacterCount: entry.outputCharacterCount,
                    failureKind: entry.failureKind,
                    cancellationReason: entry.cancellationReason
                )
            }
        return FoundationModelUsageSnapshot(
            runID: runID,
            entries: entries,
            summary: Self.makeSummary(entries: entries, telemetryOverheadMs: telemetryOverheadMs)
        )
    }

    private func entry(for modelCallID: String) throws -> MutableEntry {
        guard let entry = entriesByID[modelCallID] else {
            throw FoundationModelUsageLedgerError.unknownModelCallID(modelCallID)
        }
        return entry
    }

    private func requireTransition(
        _ entry: MutableEntry,
        to target: FoundationModelCallState
    ) throws {
        let allowed = switch (entry.state, target) {
        case (.enqueued, .started), (.enqueued, .cancelled),
             (.started, .completed), (.started, .failed), (.started, .cancelled): true
        default: false
        }
        guard allowed else {
            throw FoundationModelUsageLedgerError.invalidTransition(
                modelCallID: entry.request.modelCallID,
                from: entry.state,
                to: target
            )
        }
    }

    private func finishTiming(
        _ entry: inout MutableEntry,
        modelCallID: String,
        atNanoseconds: UInt64,
        serviceStartedAtNanoseconds: UInt64?
    ) throws {
        let started = serviceStartedAtNanoseconds ?? entry.startedAtNanoseconds
        guard let started,
              atNanoseconds >= started,
              atNanoseconds >= entry.enqueuedAtNanoseconds else {
            throw FoundationModelUsageLedgerError.invalidTimestamp(modelCallID: modelCallID)
        }
        entry.startedAtNanoseconds = started
        entry.completedAtNanoseconds = atNanoseconds
        entry.serviceMs = Self.milliseconds(from: started, to: atNanoseconds)
        entry.totalMs = Self.milliseconds(from: entry.enqueuedAtNanoseconds, to: atNanoseconds)
    }

    private static func milliseconds(from start: UInt64, to end: UInt64) -> Double {
        Double(end - start) / 1_000_000
    }

    private static func makeSummary(
        entries: [FoundationModelCallLedgerEntry],
        telemetryOverheadMs: Double
    ) -> FoundationModelUsageSummary {
        let actual = entries.filter(\.crossedInferenceBoundary)
        let queue = entries.compactMap(\.queueWaitMs).sorted()
        let service = actual.compactMap(\.serviceMs).sorted()
        return FoundationModelUsageSummary(
            entryCount: entries.count,
            actualCallCount: actual.count,
            completedCallCount: entries.filter { $0.state == .completed }.count,
            failedCallCount: entries.filter { $0.state == .failed }.count,
            cancelledCallCount: entries.filter { $0.state == .cancelled }.count,
            cancelledBeforeInferenceCount: entries.filter { $0.state == .cancelled && !$0.crossedInferenceBoundary }.count,
            queueWaitTotalMs: queue.reduce(0, +),
            serviceTotalMs: service.reduce(0, +),
            queueWaitP50Ms: percentile(queue, p: 0.50),
            queueWaitP95Ms: percentile(queue, p: 0.95),
            serviceP50Ms: percentile(service, p: 0.50),
            serviceP95Ms: percentile(service, p: 0.95),
            promptCharacterCount: entries.map(\.request.promptCharacterCount).reduce(0, +),
            outputCharacterCount: entries.compactMap(\.outputCharacterCount).reduce(0, +),
            telemetryOverheadMs: telemetryOverheadMs
        )
    }

    private static func percentile(_ sorted: [Double], p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        guard lower != upper else { return sorted[lower] }
        let fraction = position - Double(lower)
        return sorted[lower] + ((sorted[upper] - sorted[lower]) * fraction)
    }
}

public enum FoundationModelUsageLedgerScope {
    @TaskLocal public static var current: FoundationModelUsageLedger?
}
