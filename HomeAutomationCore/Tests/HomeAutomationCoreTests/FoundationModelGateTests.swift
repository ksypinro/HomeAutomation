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

    @Test("A cancelled waiter does not block subsequent admissions")
    func cancelledWaiterDoesNotBlock() async {
        let gate = FoundationModelGate(maxConcurrent: 1)
        _ = await gate.admit()

        let waiter = Task {
            await gate.admit()
        }
        while await gate.queuedCount == 0 {
            await Task.yield()
        }

        waiter.cancel()
        _ = await waiter.value
        // The cancelled waiter is admitted for release-pairing; release both.
        await gate.release()
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
