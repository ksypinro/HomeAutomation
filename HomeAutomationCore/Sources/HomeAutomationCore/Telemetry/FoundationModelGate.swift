import Foundation

/// Global admission gate for Foundation Model calls.
///
/// The on-device Foundation Model serializes inference internally, so
/// unbounded concurrent requests only hide queue wait inside apparent model
/// latency. This gate makes queueing explicit: callers wait for a slot before
/// starting a model call, and the measured wait is surfaced as telemetry
/// (`fmQueueWaitMs` on `model.call.started`).
///
/// Invariants:
/// - Every `admit()` must be paired with exactly one `release()`
///   (`FoundationModelCallRecorder.record` does this in a `defer`).
/// - Gated operations must not recursively start another gated operation,
///   otherwise slots can be exhausted by parents waiting on children.
/// - Waiting is FIFO. If a waiting task is cancelled, it is admitted
///   immediately (over-admitting by one) so the caller's paired `release()`
///   stays balanced; the cancelled operation is expected to fail fast.
///
/// Note: NLU-class soft timeouts (`withNLUModelSoftTimeout`) wrap the gated
/// call, so their budget includes queue wait. Under heavy contention NLU
/// workers therefore degrade quickly to their deterministic fallbacks instead
/// of stacking behind slower calls — this is intentional.
public actor FoundationModelGate {
    public static let shared = FoundationModelGate(maxConcurrent: 2)

    private let maxConcurrent: Int
    private var activeCount = 0
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var waitOrder: [UUID] = []

    public init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    /// Waits for an admission slot and returns the time spent queued.
    public func admit() async -> TimeInterval {
        if activeCount < maxConcurrent {
            activeCount += 1
            return 0
        }

        let id = UUID()
        let enqueuedAt = Date()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                enqueue(id: id, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancelWait(id: id) }
        }
        return Date().timeIntervalSince(enqueuedAt)
    }

    public func release() {
        removeStaleWaitOrderEntries()
        if let id = waitOrder.first, let continuation = waiters.removeValue(forKey: id) {
            waitOrder.removeFirst()
            // The slot transfers to the waiter; activeCount is unchanged.
            continuation.resume()
        } else {
            activeCount = max(0, activeCount - 1)
        }
    }

    /// Current number of admitted operations. Exposed for tests.
    public var admittedCount: Int {
        activeCount
    }

    /// Current number of queued waiters. Exposed for tests.
    public var queuedCount: Int {
        waiters.count
    }

    private func enqueue(id: UUID, continuation: CheckedContinuation<Void, Never>) {
        // A slot may have opened between the fast path check and enqueue.
        if activeCount < maxConcurrent {
            activeCount += 1
            continuation.resume()
            return
        }
        waiters[id] = continuation
        waitOrder.append(id)
    }

    private func cancelWait(id: UUID) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        waitOrder.removeAll { $0 == id }
        // Admit the cancelled waiter so its paired release() stays balanced;
        // the operation itself is expected to observe cancellation and fail fast.
        activeCount += 1
        continuation.resume()
    }

    private func removeStaleWaitOrderEntries() {
        while let id = waitOrder.first, waiters[id] == nil {
            waitOrder.removeFirst()
        }
    }
}
