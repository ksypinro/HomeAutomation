import Foundation
import HomeAutomationCore
import Testing

/// Tests for the `FoundationModelGate` admission actor (task A5 in
/// `Docs/LoopOrchestrationImplementationPlan.md`).
@Suite("Foundation Model Gate Tests")
struct FoundationModelGateTests {

    @Test("Admissions under capacity are immediate")
    func admissionsUnderCapacityAreImmediate() async {
        let gate = FoundationModelGate(maxConcurrent: 2)

        let firstWait = await gate.admit()
        let secondWait = await gate.admit()

        #expect(firstWait == 0)
        #expect(secondWait == 0)
        #expect(await gate.admittedCount == 2)

        await gate.release()
        await gate.release()
        #expect(await gate.admittedCount == 0)
    }

    @Test("Admissions beyond capacity queue until release and report the wait")
    func admissionsBeyondCapacityQueue() async {
        let gate = FoundationModelGate(maxConcurrent: 1)
        _ = await gate.admit()

        let waiter = Task {
            await gate.admit()
        }
        while await gate.queuedCount == 0 {
            await Task.yield()
        }

        try? await Task.sleep(nanoseconds: 60_000_000)
        await gate.release()
        let wait = await waiter.value

        #expect(wait >= 0.03)
        #expect(await gate.admittedCount == 1)

        await gate.release()
        #expect(await gate.admittedCount == 0)
    }

    @Test("Injected monotonic clock reports exact queue milliseconds")
    func injectedClockReportsExactQueueMilliseconds() async {
        let clock = GateManualClock(initialNanoseconds: 1_000_000_000)
        let gate = FoundationModelGate(maxConcurrent: 1, clock: clock)
        _ = await gate.admitRequest()

        let waiter = Task { await gate.admitRequest() }
        while await gate.queuedCount == 0 { await Task.yield() }
        clock.advance(milliseconds: 9)
        await gate.release()

        let result = await waiter.value
        #expect(result == .admitted(queueWaitMs: 9))
        await gate.release()
        #expect(await gate.admittedCount == 0)
    }

    @Test("Releases resume waiters in FIFO order")
    func releasesResumeWaitersInOrder() async {
        let gate = FoundationModelGate(maxConcurrent: 1)
        _ = await gate.admit()

        let order = OrderRecorder()
        let first = Task {
            _ = await gate.admit()
            await order.record("first")
        }
        while await gate.queuedCount < 1 {
            await Task.yield()
        }
        let second = Task {
            _ = await gate.admit()
            await order.record("second")
        }
        while await gate.queuedCount < 2 {
            await Task.yield()
        }

        await gate.release()
        _ = await first.value
        await gate.release()
        _ = await second.value

        #expect(await order.entries == ["first", "second"])
    }

    @Test("A cancelled waiter does not acquire a permit or block subsequent admissions")
    func cancelledWaiterDoesNotBlock() async {
        let gate = FoundationModelGate(maxConcurrent: 1)
        _ = await gate.admit()

        let waiter = Task {
            await gate.admitRequest()
        }
        while await gate.queuedCount == 0 {
            await Task.yield()
        }

        waiter.cancel()
        let result = await waiter.value
        #expect(!result.wasAdmitted)
        #expect(await gate.admittedCount == 1)
        await gate.release()

        let wait = await gate.admit()
        #expect(wait == 0)
        await gate.release()
        #expect(await gate.admittedCount == 0)
    }
}

private actor OrderRecorder {
    private(set) var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }
}

private final class GateManualClock: FoundationModelMonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var nanoseconds: UInt64

    init(initialNanoseconds: UInt64) {
        nanoseconds = initialNanoseconds
    }

    func nowNanoseconds() -> UInt64 {
        lock.withLock { nanoseconds }
    }

    func advance(milliseconds: UInt64) {
        lock.withLock {
            nanoseconds += milliseconds * 1_000_000
        }
    }
}
