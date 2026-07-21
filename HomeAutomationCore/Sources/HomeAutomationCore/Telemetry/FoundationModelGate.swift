import Foundation

/// Scheduling priority for FM gate admission.
///
/// `interactive` jobs (single-shot condition/trigger/verify calls) are short
/// and latency-sensitive. `pipeline` jobs (multi-call action subgraphs) are
/// long-running. Legacy scheduling drains interactive first, minimizing mean
/// completion time without meaningfully delaying pipelines.
public enum FMPriority: String, Sendable, Codable, Hashable {
    case interactive
    case pipeline
}

public enum FMAdmissionResult: Sendable, Equatable {
    case admitted(queueWaitMs: Double)
    case cancelled(queueWaitMs: Double)

    public var queueWaitMs: Double {
        switch self {
        case .admitted(let value), .cancelled(let value): value
        }
    }

    public var wasAdmitted: Bool {
        if case .admitted = self { return true }
        return false
    }
}

public protocol FoundationModelAdmissionControlling: Sendable {
    func admit(_ request: FMAdmissionRequest) async -> FMAdmissionDecision
    func release(leaseID: UUID) async

    func admitRequest(priority: FMPriority) async -> FMAdmissionResult
    func release() async
}

/// Global admission gate for Foundation Model calls.
///
/// Phase 7 keeps the legacy priority-lane scheduler as the default admission
/// path, but admits through explicit leases so cancellation and release are
/// correlated to one model-call boundary. `shadow` mode computes a frontier
/// proposal while executing legacy order; `active` mode uses frontier scoring
/// when request metadata is complete and falls back to legacy FIFO otherwise.
public actor FoundationModelGate: FoundationModelAdmissionControlling {
    public static let shared = FoundationModelGate(maxConcurrent: 2)

    private struct Waiter: Sendable {
        let request: FMAdmissionRequest
        let continuation: CheckedContinuation<FMAdmissionDecision, Never>
    }

    private struct ActiveLease: Sendable {
        let lease: FMAdmissionLease
        let runID: String?
        let prefixAffinityKey: String?
    }

    private let maxConcurrent: Int
    private let clock: any FoundationModelMonotonicClock
    private let defaultSchedulerMode: FoundationModelSchedulerMode
    private let frontierScheduler = FoundationModelFrontierScheduler()
    private var activeLeases: [UUID: ActiveLease] = [:]
    private var legacyReleaseOrder: [UUID] = []

    private var interactiveWaiters: [UUID: Waiter] = [:]
    private var interactiveOrder: [UUID] = []
    private var pipelineWaiters: [UUID: Waiter] = [:]
    private var pipelineOrder: [UUID] = []

    private var sequence: UInt64 = 0
    private var lastAdmittedRunID: String?
    private var consecutiveRunAdmissions = 0
    private var lastPrefixAffinityKey: String?

    public init(
        maxConcurrent: Int,
        schedulerMode: FoundationModelSchedulerMode = .legacy,
        clock: any FoundationModelMonotonicClock = SystemFoundationModelMonotonicClock()
    ) {
        self.maxConcurrent = max(1, maxConcurrent)
        self.defaultSchedulerMode = schedulerMode
        self.clock = clock
    }

    /// Waits for an admission slot and returns the time spent queued.
    /// Defaults to `.interactive` for backward compatibility.
    public func admit(priority: FMPriority = .interactive) async -> TimeInterval {
        let result = await admitRequest(priority: priority)
        return result.queueWaitMs / 1_000
    }

    public func admitRequest(priority: FMPriority = .interactive) async -> FMAdmissionResult {
        let request = makeRequest(
            modelCallID: UUID().uuidString,
            priority: priority,
            schedulerMode: .legacy,
            context: nil,
            enqueuedAtNanoseconds: clock.nowNanoseconds()
        )
        let decision = await admit(request)
        switch decision {
        case .admitted(_, let queueWaitMs, _, _):
            return .admitted(queueWaitMs: queueWaitMs)
        case .cancelled(let queueWaitMs):
            return .cancelled(queueWaitMs: queueWaitMs)
        }
    }

    public func admit(_ request: FMAdmissionRequest) async -> FMAdmissionDecision {
        let normalized = normalize(request)
        if canAdmit(normalized) {
            return admitNow(
                normalized,
                fallbackReason: fallbackReason(for: normalized),
                shadowRank: shadowRank(for: normalized),
                queueWaitMs: 0
            )
        }

        let id = normalized.requestID
        let decision = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<FMAdmissionDecision, Never>) in
                enqueue(id: id, request: normalized, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancelWait(id: id, priority: normalized.priority) }
        }
        return decision
    }

    public func release() {
        guard let leaseID = legacyReleaseOrder.first else { return }
        release(leaseID: leaseID)
    }

    public func release(leaseID: UUID) {
        guard let active = activeLeases.removeValue(forKey: leaseID) else {
            return
        }
        legacyReleaseOrder.removeAll { $0 == leaseID }
        lastPrefixAffinityKey = active.prefixAffinityKey ?? lastPrefixAffinityKey
        drainQueues()
    }

    /// Current number of admitted operations. Exposed for tests.
    public var admittedCount: Int {
        activeLeases.count
    }

    /// Current number of queued waiters across both lanes.
    public var queuedCount: Int {
        interactiveWaiters.count + pipelineWaiters.count
    }

    /// Queued count for a specific priority lane.
    public func queuedCount(for priority: FMPriority) -> Int {
        switch priority {
        case .interactive: return interactiveWaiters.count
        case .pipeline: return pipelineWaiters.count
        }
    }

    // MARK: - Request construction

    public nonisolated func makeRequest(
        modelCallID: String,
        priority: FMPriority,
        schedulerMode: FoundationModelSchedulerMode? = nil,
        context: FMAdmissionContext?,
        enqueuedAtNanoseconds: UInt64
    ) -> FMAdmissionRequest {
        FMAdmissionRequest(
            modelCallID: modelCallID,
            priority: priority,
            schedulerMode: schedulerMode ?? context?.schedulerMode ?? defaultSchedulerMode,
            enqueuedAtNanoseconds: enqueuedAtNanoseconds,
            runID: context?.runID,
            graphID: context?.graphID,
            nodeID: context?.nodeID,
            agentID: context?.agentID,
            jobKind: context?.jobKind,
            criticalPathRemainingMs: context?.criticalPathRemainingMs,
            estimatedServiceMs: context?.estimatedServiceMs,
            deadlineClass: context?.deadlineClass ?? (priority == .interactive ? .interactive : .pipeline),
            cancellationClass: context?.cancellationClass ?? .normal,
            prefixAffinityKey: context?.prefixAffinityKey,
            workflowScopeID: context?.workflowScopeID
        )
    }

    // MARK: - Private

    private func normalize(_ request: FMAdmissionRequest) -> FMAdmissionRequest {
        sequence += 1
        return FMAdmissionRequest(
            requestID: request.requestID,
            modelCallID: request.modelCallID,
            priority: request.priority,
            schedulerMode: request.schedulerMode,
            enqueuedAtNanoseconds: request.enqueuedAtNanoseconds,
            sequence: sequence,
            runID: request.runID,
            graphID: request.graphID,
            nodeID: request.nodeID,
            agentID: request.agentID,
            jobKind: request.jobKind,
            criticalPathRemainingMs: request.criticalPathRemainingMs,
            estimatedServiceMs: request.estimatedServiceMs,
            deadlineClass: request.deadlineClass,
            cancellationClass: request.cancellationClass,
            prefixAffinityKey: request.prefixAffinityKey,
            workflowScopeID: request.workflowScopeID
        )
    }

    private func canAdmit(_ request: FMAdmissionRequest) -> Bool {
        guard activeLeases.count < maxConcurrent else { return false }
        if request.schedulerMode == .active, request.hasFrontierMetadata {
            return true
        }
        if request.priority == .pipeline && shouldReserveSlotForInteractive() {
            return false
        }
        return true
    }

    private func shouldReserveSlotForInteractive() -> Bool {
        maxConcurrent >= 2
            && activeLeases.count >= maxConcurrent - 1
            && !interactiveWaiters.isEmpty
    }

    private func enqueue(
        id: UUID,
        request: FMAdmissionRequest,
        continuation: CheckedContinuation<FMAdmissionDecision, Never>
    ) {
        if canAdmit(request) {
            continuation.resume(returning: admitNow(
                request,
                fallbackReason: fallbackReason(for: request),
                shadowRank: shadowRank(for: request),
                queueWaitMs: 0
            ))
            return
        }
        let waiter = Waiter(request: request, continuation: continuation)
        switch request.priority {
        case .interactive:
            interactiveWaiters[id] = waiter
            interactiveOrder.append(id)
        case .pipeline:
            pipelineWaiters[id] = waiter
            pipelineOrder.append(id)
        }
    }

    private func cancelWait(id: UUID, priority: FMPriority) {
        let waiter: Waiter?
        switch priority {
        case .interactive:
            waiter = interactiveWaiters.removeValue(forKey: id)
            interactiveOrder.removeAll { $0 == id }
        case .pipeline:
            waiter = pipelineWaiters.removeValue(forKey: id)
            pipelineOrder.removeAll { $0 == id }
        }
        guard let waiter else { return }
        waiter.continuation.resume(returning: .cancelled(
            queueWaitMs: Self.milliseconds(from: waiter.request.enqueuedAtNanoseconds, to: clock.nowNanoseconds())
        ))
    }

    private func drainQueues() {
        removeStaleEntries(waiters: &interactiveWaiters, order: &interactiveOrder)
        removeStaleEntries(waiters: &pipelineWaiters, order: &pipelineOrder)

        while activeLeases.count < maxConcurrent,
              let waiter = nextWaiter() {
            removeWaiter(waiter.request.requestID, priority: waiter.request.priority)
            let fallbackReason = fallbackReason(for: waiter.request)
            waiter.continuation.resume(returning: admitNow(
                waiter.request,
                fallbackReason: fallbackReason,
                shadowRank: shadowRank(for: waiter.request),
                queueWaitMs: nil
            ))
            removeStaleEntries(waiters: &interactiveWaiters, order: &interactiveOrder)
            removeStaleEntries(waiters: &pipelineWaiters, order: &pipelineOrder)
        }
    }

    private func nextWaiter() -> Waiter? {
        let waiters = allWaiters()
        if waiters.contains(where: { $0.request.schedulerMode == .active && $0.request.hasFrontierMetadata }) {
            let suppressedRunID = consecutiveRunAdmissions >= 2 ? lastAdmittedRunID : nil
            let ranked = frontierScheduler.rank(
                waiters.map(\.request),
                nowNanoseconds: clock.nowNanoseconds(),
                lastPrefixAffinityKey: lastPrefixAffinityKey,
                suppressedRunID: suppressedRunID
            )
            if let request = ranked.first,
               request.hasFrontierMetadata,
               let waiter = waiters.first(where: { $0.request.requestID == request.requestID }) {
                return waiter
            }
        }

        if let id = interactiveOrder.first,
           let waiter = interactiveWaiters[id] {
            return waiter
        }
        if let id = pipelineOrder.first,
           let waiter = pipelineWaiters[id],
           !shouldReserveSlotForInteractive() {
            return waiter
        }
        return nil
    }

    private func removeWaiter(_ id: UUID, priority: FMPriority) {
        switch priority {
        case .interactive:
            interactiveWaiters.removeValue(forKey: id)
            interactiveOrder.removeAll { $0 == id }
        case .pipeline:
            pipelineWaiters.removeValue(forKey: id)
            pipelineOrder.removeAll { $0 == id }
        }
    }

    private func allWaiters() -> [Waiter] {
        let interactive = interactiveOrder.compactMap { interactiveWaiters[$0] }
        let pipeline = pipelineOrder.compactMap { pipelineWaiters[$0] }
        return interactive + pipeline
    }

    private func admitNow(
        _ request: FMAdmissionRequest,
        fallbackReason: FMAdmissionFallbackReason,
        shadowRank: [String],
        queueWaitMs: Double?
    ) -> FMAdmissionDecision {
        let lease = FMAdmissionLease(
            requestID: request.requestID,
            modelCallID: request.modelCallID,
            priority: request.priority,
            schedulerMode: request.schedulerMode,
            admittedAtNanoseconds: clock.nowNanoseconds(),
            sequence: request.sequence
        )
        activeLeases[lease.leaseID] = ActiveLease(
            lease: lease,
            runID: request.runID,
            prefixAffinityKey: request.prefixAffinityKey
        )
        legacyReleaseOrder.append(lease.leaseID)
        if request.runID == lastAdmittedRunID {
            consecutiveRunAdmissions += 1
        } else {
            lastAdmittedRunID = request.runID
            consecutiveRunAdmissions = 1
        }
        return .admitted(
            lease: lease,
            queueWaitMs: queueWaitMs ?? Self.milliseconds(from: request.enqueuedAtNanoseconds, to: lease.admittedAtNanoseconds),
            fallbackReason: fallbackReason,
            shadowRank: shadowRank
        )
    }

    private func fallbackReason(for request: FMAdmissionRequest) -> FMAdmissionFallbackReason {
        switch request.schedulerMode {
        case .legacy:
            return .legacyMode
        case .shadow:
            return .shadowMode
        case .active:
            return request.hasFrontierMetadata ? .none : .missingFrontierMetadata
        }
    }

    private func shadowRank(for request: FMAdmissionRequest) -> [String] {
        guard request.schedulerMode == .shadow else { return [] }
        let requests = allWaiters().map(\.request) + [request]
        return frontierScheduler
            .rank(requests, nowNanoseconds: clock.nowNanoseconds(), lastPrefixAffinityKey: lastPrefixAffinityKey)
            .map(\.modelCallID)
    }

    private func removeStaleEntries(
        waiters: inout [UUID: Waiter],
        order: inout [UUID]
    ) {
        while let id = order.first, waiters[id] == nil {
            order.removeFirst()
        }
    }

    private static func milliseconds(from start: UInt64, to end: UInt64) -> Double {
        guard end >= start else { return 0 }
        return Double(end - start) / 1_000_000
    }
}
