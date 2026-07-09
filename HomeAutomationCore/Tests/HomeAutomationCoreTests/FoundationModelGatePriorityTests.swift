import Foundation
import HomeAutomationCore
import Testing

@Suite("Foundation Model Gate — SJF Priority Lanes")
struct FoundationModelGatePriorityTests {

    @Test("Interactive callers are admitted before pipeline callers")
    func interactiveBeforePipeline() async {
        let gate = FoundationModelGate(maxConcurrent: 1)
        _ = await gate.admit(priority: .interactive)

        let order = OrderRecorder()

        let pipelineTask = Task {
            _ = await gate.admit(priority: .pipeline)
            await order.record("pipeline")
            await gate.release()
        }
        while await gate.queuedCount(for: .pipeline) == 0 {
            await Task.yield()
        }

        let interactiveTask = Task {
            _ = await gate.admit(priority: .interactive)
            await order.record("interactive")
            await gate.release()
        }
        while await gate.queuedCount(for: .interactive) == 0 {
            await Task.yield()
        }

        await gate.release()
        _ = await interactiveTask.value
        _ = await pipelineTask.value

        #expect(await order.entries == ["interactive", "pipeline"])
    }

    @Test("Pipeline callers admitted when no interactive waiters exist")
    func pipelineAdmittedWhenNoInteractive() async {
        let gate = FoundationModelGate(maxConcurrent: 1)
        _ = await gate.admit(priority: .pipeline)

        let pipelineTask = Task {
            _ = await gate.admit(priority: .pipeline)
            await gate.release()
        }
        while await gate.queuedCount(for: .pipeline) == 0 {
            await Task.yield()
        }

        await gate.release()
        _ = await pipelineTask.value

        #expect(await gate.admittedCount == 0)
    }

    @Test("Interactive slot reservation: pipeline stays queued when interactive needs the last slot")
    func interactiveSlotReservation() async {
        let gate = FoundationModelGate(maxConcurrent: 2)
        // Fill both slots.
        _ = await gate.admit(priority: .pipeline)
        _ = await gate.admit(priority: .pipeline)
        #expect(await gate.admittedCount == 2)

        // Queue a pipeline waiter and an interactive waiter.
        let pipelineTask = Task { _ = await gate.admit(priority: .pipeline) }
        while await gate.queuedCount(for: .pipeline) == 0 { await Task.yield() }

        let interactiveTask = Task { _ = await gate.admit(priority: .interactive) }
        while await gate.queuedCount(for: .interactive) == 0 { await Task.yield() }

        // Release one slot. Interactive should be admitted (SJF), pipeline
        // should remain queued because the last open slot is reserved for
        // the interactive lane.
        await gate.release()
        _ = await interactiveTask.value

        #expect(await gate.admittedCount == 2)
        #expect(await gate.queuedCount(for: .pipeline) == 1)

        // Release another slot → pipeline can now be admitted (no interactive
        // waiters remaining, reservation no longer applies).
        await gate.release()
        _ = await pipelineTask.value

        #expect(await gate.queuedCount == 0)

        // Clean up.
        await gate.release()
        await gate.release()
        #expect(await gate.admittedCount == 0)
    }

    @Test("Per-priority queue count is accurate")
    func perPriorityQueueCount() async {
        let gate = FoundationModelGate(maxConcurrent: 1)
        _ = await gate.admit(priority: .interactive)

        let t1 = Task { _ = await gate.admit(priority: .interactive) }
        while await gate.queuedCount(for: .interactive) < 1 { await Task.yield() }

        let t2 = Task { _ = await gate.admit(priority: .pipeline) }
        while await gate.queuedCount(for: .pipeline) < 1 { await Task.yield() }

        #expect(await gate.queuedCount == 2)
        #expect(await gate.queuedCount(for: .interactive) == 1)
        #expect(await gate.queuedCount(for: .pipeline) == 1)

        await gate.release()
        _ = await t1.value
        await gate.release()
        _ = await t2.value
        await gate.release()
        await gate.release()
    }

    @Test("FMPriority rawValue matches telemetry label expectations")
    func priorityRawValues() {
        #expect(FMPriority.interactive.rawValue == "interactive")
        #expect(FMPriority.pipeline.rawValue == "pipeline")
    }

    @Test("Default admit uses interactive priority (backward compatible)")
    func defaultAdmitIsInteractive() async {
        let gate = FoundationModelGate(maxConcurrent: 2)
        _ = await gate.admit()
        #expect(await gate.admittedCount == 1)
        await gate.release()
    }
}

private actor OrderRecorder {
    private(set) var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }
}
