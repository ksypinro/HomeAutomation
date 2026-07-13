import Foundation
import HomeAutomationCore
import Testing

@Suite("Foundation Model frontier scheduler")
struct FoundationModelFrontierSchedulerTests {

    @Test("Critical frontier work outranks lower-urgency work")
    func criticalFrontierWorkOutranksLowerUrgencyWork() {
        let scheduler = FoundationModelFrontierScheduler()
        let slowLowUrgency = request(
            modelCallID: "slow",
            sequence: 1,
            remaining: 100,
            service: 100
        )
        let critical = request(
            modelCallID: "critical",
            sequence: 2,
            remaining: 500,
            service: 50
        )

        let ranked = scheduler.rank([slowLowUrgency, critical], nowNanoseconds: 2_000_000)
        #expect(ranked.map(\.modelCallID) == ["critical", "slow"])
    }

    @Test("FIFO is stable when frontier metadata is missing")
    func fifoWhenMetadataIsMissing() {
        let scheduler = FoundationModelFrontierScheduler()
        let first = FMAdmissionRequest(
            modelCallID: "first",
            priority: .pipeline,
            schedulerMode: .active,
            enqueuedAtNanoseconds: 1,
            sequence: 1
        )
        let second = FMAdmissionRequest(
            modelCallID: "second",
            priority: .pipeline,
            schedulerMode: .active,
            enqueuedAtNanoseconds: 1,
            sequence: 2
        )

        let ranked = scheduler.rank([second, first], nowNanoseconds: 2_000_000)
        #expect(ranked.map(\.modelCallID) == ["first", "second"])
    }

    @Test("Active gate uses frontier ordering when metadata is complete")
    func activeGateUsesFrontierOrdering() async {
        let gate = FoundationModelGate(maxConcurrent: 1, schedulerMode: .active)
        let initial = request(modelCallID: "initial", sequence: 0, remaining: 10, service: 10)
        guard case .admitted(let initialLease, _, _, _) = await gate.admit(initial) else {
            Issue.record("Expected initial admission")
            return
        }

        let order = FrontierOrderRecorder()
        let low = Task {
            _ = await gate.admit(request(modelCallID: "low", sequence: 1, remaining: 100, service: 100))
            await order.record("low")
            await gate.release()
        }
        while await gate.queuedCount == 0 {
            await Task.yield()
        }
        let high = Task {
            _ = await gate.admit(request(modelCallID: "high", sequence: 2, remaining: 500, service: 50))
            await order.record("high")
            await gate.release()
        }
        while await gate.queuedCount < 2 {
            await Task.yield()
        }

        await gate.release(leaseID: initialLease.leaseID)
        _ = await high.value
        _ = await low.value

        #expect(await order.entries == ["high", "low"])
    }

    private func request(
        modelCallID: String,
        sequence: UInt64,
        remaining: Double,
        service: Double
    ) -> FMAdmissionRequest {
        FMAdmissionRequest(
            modelCallID: modelCallID,
            priority: .pipeline,
            schedulerMode: .active,
            enqueuedAtNanoseconds: 1,
            sequence: sequence,
            runID: "run-\(modelCallID)",
            graphID: "graph",
            nodeID: modelCallID,
            agentID: "agent",
            jobKind: .automationResolution,
            criticalPathRemainingMs: remaining,
            estimatedServiceMs: service,
            deadlineClass: .pipeline,
            cancellationClass: .normal,
            prefixAffinityKey: "agent",
            workflowScopeID: "graph"
        )
    }
}

private actor FrontierOrderRecorder {
    private(set) var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }
}
