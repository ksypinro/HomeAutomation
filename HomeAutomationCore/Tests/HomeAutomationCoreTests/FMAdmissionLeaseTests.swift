import Foundation
import HomeAutomationCore
import Testing

@Suite("Foundation Model admission leases")
struct FMAdmissionLeaseTests {

    @Test("Explicit lease release is idempotent")
    func explicitLeaseReleaseIsIdempotent() async {
        let gate = FoundationModelGate(maxConcurrent: 1)
        let request = FMAdmissionRequest(
            modelCallID: "lease-call",
            priority: .interactive,
            schedulerMode: .legacy,
            enqueuedAtNanoseconds: 1
        )

        let decision = await gate.admit(request)
        guard case .admitted(let lease, _, _, _) = decision else {
            Issue.record("Expected admission")
            return
        }

        #expect(await gate.admittedCount == 1)
        await gate.release(leaseID: lease.leaseID)
        await gate.release(leaseID: lease.leaseID)
        #expect(await gate.admittedCount == 0)
    }

    @Test("Legacy release still drains oldest active lease")
    func legacyReleaseStillDrainsOldestActiveLease() async {
        let gate = FoundationModelGate(maxConcurrent: 2)
        _ = await gate.admit(priority: .interactive)
        _ = await gate.admit(priority: .pipeline)

        #expect(await gate.admittedCount == 2)
        await gate.release()
        #expect(await gate.admittedCount == 1)
        await gate.release()
        #expect(await gate.admittedCount == 0)
    }

    @Test("Cancelled waiter never receives a lease")
    func cancelledWaiterNeverReceivesLease() async {
        let gate = FoundationModelGate(maxConcurrent: 1)
        _ = await gate.admit(priority: .interactive)

        let waiter = Task {
            await gate.admit(FMAdmissionRequest(
                modelCallID: "queued",
                priority: .interactive,
                schedulerMode: .legacy,
                enqueuedAtNanoseconds: 1
            ))
        }
        while await gate.queuedCount == 0 {
            await Task.yield()
        }

        waiter.cancel()
        let decision = await waiter.value
        guard case .cancelled = decision else {
            Issue.record("Expected cancellation before lease")
            return
        }
        #expect(await gate.admittedCount == 1)
        await gate.release()
    }
}
