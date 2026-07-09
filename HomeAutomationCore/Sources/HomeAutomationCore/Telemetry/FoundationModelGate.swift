import Foundation

/// Scheduling priority for FM gate admission.
///
/// `interactive` jobs (single-shot condition/trigger/verify calls) are short
/// and latency-sensitive. `pipeline` jobs (multi-call action subgraphs) are
/// long-running. SJF scheduling drains interactive first, minimizing mean
/// completion time without meaningfully delaying pipelines.
public enum FMPriority: String, Sendable, Hashable {
    case interactive
    case pipeline
}

/// Global admission gate for Foundation Model calls.
///
/// The on-device Foundation Model serializes inference internally, so
/// unbounded concurrent requests only hide queue wait inside apparent model
/// latency. This gate makes queueing explicit: callers wait for a slot before
/// starting a model call, and the measured wait is surfaced as telemetry
/// (`fmQueueWaitMs` on `model.call.started`).
///
/// ## Priority lanes (SJF)
///
/// Two FIFO queues — `interactive` drains before `pipeline`. When both queues
/// are non-empty and `maxConcurrent ≥ 2`, one slot is reserved for
/// `interactive` so a 1-call condition can't sit behind 12 queued action calls.
///
/// Invariants:
/// - Every `admit()` must be paired with exactly one `release()`
///   (`FoundationModelCallRecorder.record` does this in a `defer`).
/// - Gated operations must not recursively start another gated operation,
///   otherwise slots can be exhausted by parents waiting on children.
/// - Within each priority band, waiting is FIFO. If a waiting task is
///   cancelled, it is admitted immediately (over-admitting by one) so the
///   caller's paired `release()` stays balanced.
///
/// Note: NLU-class soft timeouts (`withNLUModelSoftTimeout`) wrap the gated
/// call, so their budget includes queue wait. Under heavy contention NLU
/// workers therefore degrade quickly to their deterministic fallbacks instead
/// of stacking behind slower calls — this is intentional.
public actor FoundationModelGate {
    public static let shared = FoundationModelGate(maxConcurrent: 2)

    private let maxConcurrent: Int
    private var activeCount = 0

    private var interactiveWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var interactiveOrder: [UUID] = []
    private var pipelineWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var pipelineOrder: [UUID] = []

    private var activeInteractiveCount = 0

    public init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    /// Waits for an admission slot and returns the time spent queued.
    /// Defaults to `.interactive` for backward compatibility.
    public func admit(priority: FMPriority = .interactive) async -> TimeInterval {
        if canAdmit(priority: priority) {
            activeCount += 1
            if priority == .interactive { activeInteractiveCount += 1 }
            return 0
        }

        let id = UUID()
        let enqueuedAt = Date()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                enqueue(id: id, priority: priority, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancelWait(id: id, priority: priority) }
        }
        return Date().timeIntervalSince(enqueuedAt)
    }

    public func release() {
        removeStaleEntries(waiters: &interactiveWaiters, order: &interactiveOrder)
        removeStaleEntries(waiters: &pipelineWaiters, order: &pipelineOrder)

        if let id = interactiveOrder.first,
           let continuation = interactiveWaiters.removeValue(forKey: id) {
            interactiveOrder.removeFirst()
            activeInteractiveCount += 1
            continuation.resume()
            return
        }

        if let id = pipelineOrder.first,
           let continuation = pipelineWaiters.removeValue(forKey: id) {
            if shouldReserveSlotForInteractive() {
                pipelineWaiters[id] = continuation
            } else {
                pipelineOrder.removeFirst()
                continuation.resume()
                return
            }
        }

        activeCount = max(0, activeCount - 1)
        if activeInteractiveCount > activeCount {
            activeInteractiveCount = activeCount
        }
    }

    /// Current number of admitted operations. Exposed for tests.
    public var admittedCount: Int {
        activeCount
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

    // MARK: - Private

    private func canAdmit(priority: FMPriority) -> Bool {
        guard activeCount < maxConcurrent else { return false }
        if priority == .pipeline && shouldReserveSlotForInteractive() {
            return false
        }
        return true
    }

    /// Reserve the last slot for interactive when pipeline waiters would take
    /// it and interactive waiters are queued.
    private func shouldReserveSlotForInteractive() -> Bool {
        maxConcurrent >= 2
            && activeCount >= maxConcurrent - 1
            && !interactiveWaiters.isEmpty
    }

    private func enqueue(
        id: UUID,
        priority: FMPriority,
        continuation: CheckedContinuation<Void, Never>
    ) {
        if canAdmit(priority: priority) {
            activeCount += 1
            if priority == .interactive { activeInteractiveCount += 1 }
            continuation.resume()
            return
        }
        switch priority {
        case .interactive:
            interactiveWaiters[id] = continuation
            interactiveOrder.append(id)
        case .pipeline:
            pipelineWaiters[id] = continuation
            pipelineOrder.append(id)
        }
    }

    private func cancelWait(id: UUID, priority: FMPriority) {
        let continuation: CheckedContinuation<Void, Never>?
        switch priority {
        case .interactive:
            continuation = interactiveWaiters.removeValue(forKey: id)
            interactiveOrder.removeAll { $0 == id }
        case .pipeline:
            continuation = pipelineWaiters.removeValue(forKey: id)
            pipelineOrder.removeAll { $0 == id }
        }
        guard let continuation else { return }
        activeCount += 1
        if priority == .interactive { activeInteractiveCount += 1 }
        continuation.resume()
    }

    private func removeStaleEntries(
        waiters: inout [UUID: CheckedContinuation<Void, Never>],
        order: inout [UUID]
    ) {
        while let id = order.first, waiters[id] == nil {
            order.removeFirst()
        }
    }
}
