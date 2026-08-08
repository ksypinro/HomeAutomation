import Foundation
import HomeAutomationCore
import Testing

@Suite("Foundation Model Usage Ledger")
struct FoundationModelUsageLedgerTests {
    @Test("Ledger records exact queue, service, totals, and characters")
    func recordsExactTimingAndSummary() async throws {
        let ledger = FoundationModelUsageLedger(runID: "run-1")
        let request = FoundationModelCallRequest(
            modelCallID: "call-1",
            arm: .graph,
            jobKind: .semanticNLU,
            graphID: "graph-1",
            nodeID: "semanticNLU",
            agentID: "semanticNLU",
            attempt: 1,
            priority: .interactive,
            promptCharacterCount: 42,
            selectedToolNames: ["candidateLookup"],
            sessionReuse: .fresh,
            modelAvailability: .available
        )

        let ordinal = try await ledger.enqueue(request, atNanoseconds: 1_000_000_000)
        try await ledger.start(modelCallID: "call-1", atNanoseconds: 1_005_000_000)
        try await ledger.complete(
            modelCallID: "call-1",
            atNanoseconds: 1_025_000_000,
            outputCharacterCount: 17
        )

        let snapshot = await ledger.snapshot()
        let entry = try #require(snapshot.entries.first)
        #expect(ordinal == 1)
        #expect(snapshot.runID == "run-1")
        #expect(entry.ordinal == 1)
        #expect(entry.state == .completed)
        #expect(entry.queueWaitMs == 5)
        #expect(entry.serviceMs == 20)
        #expect(entry.totalMs == 25)
        #expect(entry.crossedInferenceBoundary)
        #expect(snapshot.summary.entryCount == 1)
        #expect(snapshot.summary.actualCallCount == 1)
        #expect(snapshot.summary.completedCallCount == 1)
        #expect(snapshot.summary.promptCharacterCount == 42)
        #expect(snapshot.summary.outputCharacterCount == 17)
    }

    @Test("Cancelled queued calls are terminal but are not actual inference")
    func cancelledBeforeInferenceIsNotActualCall() async throws {
        let ledger = FoundationModelUsageLedger(runID: "run-cancel")
        try await ledger.enqueue(
            FoundationModelCallRequest(
                modelCallID: "call-cancel",
                agentID: "verifier",
                promptCharacterCount: 10
            ),
            atNanoseconds: 2_000_000_000
        )
        try await ledger.cancel(
            modelCallID: "call-cancel",
            atNanoseconds: 2_007_000_000,
            reason: .taskCancelledBeforeAdmission
        )

        let snapshot = await ledger.snapshot()
        let entry = try #require(snapshot.entries.first)
        #expect(entry.state == .cancelled)
        #expect(entry.queueWaitMs == 7)
        #expect(!entry.crossedInferenceBoundary)
        #expect(snapshot.summary.actualCallCount == 0)
        #expect(snapshot.summary.cancelledCallCount == 1)
        #expect(snapshot.summary.cancelledBeforeInferenceCount == 1)
    }

    @Test("Duplicate IDs and illegal terminal transitions are rejected")
    func rejectsInvalidTransitions() async throws {
        let ledger = FoundationModelUsageLedger(runID: "run-errors")
        let request = FoundationModelCallRequest(
            modelCallID: "duplicate",
            agentID: "draftGeneration",
            promptCharacterCount: 1
        )
        try await ledger.enqueue(request, atNanoseconds: 0)

        await #expect(throws: FoundationModelUsageLedgerError.duplicateModelCallID("duplicate")) {
            try await ledger.enqueue(request, atNanoseconds: 1)
        }
        await #expect(throws: FoundationModelUsageLedgerError.invalidTransition(
            modelCallID: "duplicate",
            from: .enqueued,
            to: .completed
        )) {
            try await ledger.complete(
                modelCallID: "duplicate",
                atNanoseconds: 2,
                outputCharacterCount: 0
            )
        }
    }

    @Test("Concurrent ledgers remain isolated")
    func concurrentRunIsolation() async throws {
        let first = FoundationModelUsageLedger(runID: "run-a")
        let second = FoundationModelUsageLedger(runID: "run-b")

        async let firstWork: Void = recordCompletedCall(id: "a", ledger: first)
        async let secondWork: Void = recordCompletedCall(id: "b", ledger: second)
        _ = try await (firstWork, secondWork)

        let firstSnapshot = await first.snapshot()
        let secondSnapshot = await second.snapshot()
        #expect(firstSnapshot.entries.map(\.request.modelCallID) == ["a"])
        #expect(secondSnapshot.entries.map(\.request.modelCallID) == ["b"])
        #expect(firstSnapshot.entries.allSatisfy { $0.runID == "run-a" })
        #expect(secondSnapshot.entries.allSatisfy { $0.runID == "run-b" })
    }

    @Test("Recorder supports exact injected timing")
    func recorderUsesInjectedClockAndLedger() async throws {
        let clock = ManualFoundationModelClock(initialNanoseconds: 5_000_000_000)
        let gate = FoundationModelGate(maxConcurrent: 1, clock: clock)
        let ledger = FoundationModelUsageLedger(runID: "run-recorder")

        let value = try await FoundationModelUsageLedgerScope.$current.withValue(ledger) {
            try await FoundationModelCallRecorder.record(
                agentID: "semanticNLU",
                modelCallID: "recorded-call",
                modelAvailability: "available",
                promptCharacterCount: 12,
                outputCharacterCount: { $0.count },
                arm: .graph,
                jobKind: .semanticNLU,
                admissionController: gate,
                clock: clock
            ) {
                clock.advance(milliseconds: 20)
                return "ok"
            }
        }

        let snapshot = await ledger.snapshot()
        let entry = try #require(snapshot.entries.first)
        #expect(value == "ok")
        #expect(entry.queueWaitMs == 0)
        #expect(entry.serviceMs == 20)
        #expect(entry.outputCharacterCount == 2)
        #expect(snapshot.summary.actualCallCount == 1)
        #expect(await gate.admittedCount == 0)
    }

    @Test("Recorder inherits bounded arm, job, and escalation attribution from telemetry context")
    func recorderInheritsTelemetryAttribution() async throws {
        let clock = ManualFoundationModelClock(initialNanoseconds: 6_000_000_000)
        let gate = FoundationModelGate(maxConcurrent: 1, clock: clock)
        let ledger = FoundationModelUsageLedger(runID: "run-attribution")
        let context = HomeAutomationTelemetryContext(
            runID: "run-attribution",
            graphID: "graph-a",
            graphNodeID: "node-a",
            attempt: 2,
            foundationModelArm: .verifierLoop,
            foundationModelJobID: "verify-job",
            foundationModelJobKind: .verifier,
            foundationModelEscalationChain: [.verifierLoop, .finalization]
        )

        _ = try await FoundationModelUsageLedgerScope.$current.withValue(ledger) {
            try await HomeAutomationTelemetryScope.$current.withValue(context) {
                try await FoundationModelCallRecorder.record(
                    agentID: "draftVerifier",
                    modelCallID: "inherited-call",
                    promptCharacterCount: 19,
                    admissionController: gate,
                    clock: clock
                ) {
                    clock.advance(milliseconds: 5)
                    return "accepted"
                }
            }
        }

        let entry = try #require(await ledger.snapshot().entries.first)
        #expect(entry.request.arm == .verifierLoop)
        #expect(entry.request.jobID == "verify-job")
        #expect(entry.request.jobKind == .verifier)
        #expect(entry.request.graphID == "graph-a")
        #expect(entry.request.nodeID == "node-a")
        #expect(entry.request.attempt == 2)
        #expect(entry.request.escalationChain == [.verifierLoop, .finalization])
    }

    @Test("Recorder cancellation while queued never invokes inference")
    func recorderQueuedCancellationDoesNotInfer() async throws {
        let clock = ManualFoundationModelClock(initialNanoseconds: 9_000_000_000)
        let gate = FoundationModelGate(maxConcurrent: 1, clock: clock)
        let ledger = FoundationModelUsageLedger(runID: "run-queued-cancel")
        let calls = InvocationCounter()
        _ = await gate.admitRequest(priority: .interactive)

        let task = Task {
            await FoundationModelUsageLedgerScope.$current.withValue(ledger) {
                do {
                    _ = try await FoundationModelCallRecorder.record(
                        agentID: "verifier",
                        modelCallID: "queued-call",
                        promptCharacterCount: 5,
                        admissionController: gate,
                        clock: clock
                    ) {
                        await calls.increment()
                        return "unexpected"
                    }
                    return false
                } catch is CancellationError {
                    return true
                } catch {
                    return false
                }
            }
        }
        while await gate.queuedCount == 0 { await Task.yield() }
        clock.advance(milliseconds: 7)
        task.cancel()

        #expect(await task.value)
        #expect(await calls.value == 0)
        #expect(await gate.admittedCount == 1)
        await gate.release()
        #expect(await gate.admittedCount == 0)

        let snapshot = await ledger.snapshot()
        #expect(snapshot.summary.actualCallCount == 0)
        #expect(snapshot.summary.cancelledBeforeInferenceCount == 1)
        #expect(snapshot.entries.first?.queueWaitMs == 7)
    }

    @Test("Recorder admission deadline cancels queued call before inference")
    func recorderAdmissionDeadlineDoesNotInfer() async throws {
        let clock = ManualFoundationModelClock(initialNanoseconds: 9_500_000_000)
        let gate = FoundationModelGate(maxConcurrent: 1, clock: clock)
        let ledger = FoundationModelUsageLedger(runID: "run-admission-timeout")
        let calls = InvocationCounter()
        _ = await gate.admitRequest(priority: .interactive)

        await #expect(throws: FoundationModelAdmissionTimeoutError.self) {
            try await FoundationModelUsageLedgerScope.$current.withValue(ledger) {
                try await FoundationModelCallRecorder.record(
                    agentID: "verifier",
                    modelCallID: "admission-timeout-call",
                    promptCharacterCount: 5,
                    admissionDeadlineNanoseconds: 5_000_000,
                    admissionController: gate,
                    clock: clock
                ) {
                    await calls.increment()
                    return "unexpected"
                }
            }
        }

        #expect(await calls.value == 0)
        #expect(await gate.queuedCount == 0)
        #expect(await gate.admittedCount == 1)
        await gate.release()
        #expect(await gate.admittedCount == 0)

        let snapshot = await ledger.snapshot()
        #expect(snapshot.summary.actualCallCount == 0)
        #expect(snapshot.summary.cancelledBeforeInferenceCount == 1)
        #expect(snapshot.entries.first?.cancellationReason == .admissionDeadlineExceeded)
    }

    @Test("Recorder failure releases its permit and records a failed actual call")
    func recorderFailureReleasesPermit() async throws {
        let clock = ManualFoundationModelClock(initialNanoseconds: 10_000_000_000)
        let gate = FoundationModelGate(maxConcurrent: 1, clock: clock)
        let ledger = FoundationModelUsageLedger(runID: "run-failure")

        await #expect(throws: RecorderTestError.expected) {
            try await FoundationModelUsageLedgerScope.$current.withValue(ledger) {
                try await FoundationModelCallRecorder.record(
                    agentID: "draftGeneration",
                    modelCallID: "failed-call",
                    promptCharacterCount: 3,
                    admissionController: gate,
                    clock: clock
                ) {
                    clock.advance(milliseconds: 11)
                    throw RecorderTestError.expected
                }
            }
        }

        let snapshot = await ledger.snapshot()
        #expect(await gate.admittedCount == 0)
        #expect(snapshot.summary.actualCallCount == 1)
        #expect(snapshot.summary.failedCallCount == 1)
        #expect(snapshot.entries.first?.serviceMs == 11)
        #expect(snapshot.entries.first?.failureKind != nil)
    }

    @Test("Cancellation after admission is an actual attempt and releases once")
    func recorderCancellationAfterAdmission() async throws {
        let clock = ManualFoundationModelClock(initialNanoseconds: 11_000_000_000)
        let gate = FoundationModelGate(maxConcurrent: 1, clock: clock)
        let ledger = FoundationModelUsageLedger(runID: "run-active-cancel")

        await #expect(throws: CancellationError.self) {
            try await FoundationModelUsageLedgerScope.$current.withValue(ledger) {
                try await FoundationModelCallRecorder.record(
                    agentID: "verifier",
                    modelCallID: "active-cancel",
                    promptCharacterCount: 8,
                    admissionController: gate,
                    clock: clock
                ) {
                    clock.advance(milliseconds: 13)
                    throw CancellationError()
                }
            }
        }

        let snapshot = await ledger.snapshot()
        #expect(await gate.admittedCount == 0)
        #expect(snapshot.summary.actualCallCount == 1)
        #expect(snapshot.summary.cancelledCallCount == 1)
        #expect(snapshot.summary.cancelledBeforeInferenceCount == 0)
        #expect(snapshot.entries.first?.serviceMs == 13)
        #expect(snapshot.entries.first?.cancellationReason == .taskCancelledAfterAdmission)
    }

    @Test("TaskLocal ledger scope is inherited by structured child tasks")
    func taskLocalScopeInheritance() async {
        let ledger = FoundationModelUsageLedger(runID: "run-scope")
        let inheritedRunID = await FoundationModelUsageLedgerScope.$current.withValue(ledger) {
            await Task {
                FoundationModelUsageLedgerScope.current?.runID
            }.value
        }
        #expect(inheritedRunID == "run-scope")
        #expect(FoundationModelUsageLedgerScope.current == nil)
    }

    private func recordCompletedCall(
        id: String,
        ledger: FoundationModelUsageLedger
    ) async throws {
        try await ledger.enqueue(
            FoundationModelCallRequest(modelCallID: id, agentID: id, promptCharacterCount: 1),
            atNanoseconds: 0
        )
        try await ledger.start(modelCallID: id, atNanoseconds: 1_000_000)
        try await ledger.complete(modelCallID: id, atNanoseconds: 2_000_000, outputCharacterCount: 1)
    }
}

private enum RecorderTestError: Error {
    case expected
}

private final class ManualFoundationModelClock: FoundationModelMonotonicClock, @unchecked Sendable {
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

private actor InvocationCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
