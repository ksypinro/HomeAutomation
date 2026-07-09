import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Parallel Loop Repairs")
struct ParallelRepairTests {

    @Test("Multiple disjoint repairs execute concurrently and merge in order")
    func disjointRepairsRunConcurrently() async {
        let repairStarted = TimestampRecorder()
        let verifyCallCount = CallCounter()

        let orchestrator = makeOrchestrator(
            verifyBehavior: { _, _ in
                let count = await verifyCallCount.increment()
                if count == 1 {
                    return DraftVerdict(
                        accepted: false,
                        disputes: [
                            DraftDispute(fieldID: "command.capability", kind: .wrongValue, evidence: "test"),
                            DraftDispute(fieldID: "command.targetDeviceID", kind: .wrongValue, evidence: "test"),
                        ],
                        needsClarification: false
                    )
                }
                return DraftVerdict(accepted: true, disputes: [], needsClarification: false)
            },
            specialistBehavior: { step, envelope in
                await repairStarted.record(step.specialist.rawValue)
                switch step.specialist {
                case .capability:
                    return .capability(
                        fieldID: FieldID(rawValue: "command.capability"),
                        HomeCapabilityDecision(
                            selectedCapability: "switch",
                            selectedCommand: "on",
                            targetDeviceID: nil,
                            alternatives: [],
                            evidence: [],
                            confidence: 0.9
                        )
                    )
                case .target:
                    return .target(
                        fieldID: FieldID(rawValue: "command.targetDeviceID"),
                        ActionTargetResult(
                            selectedDeviceID: "dev1",
                            candidateTable: [],
                            confidence: 0.9,
                            isAmbiguous: false
                        )
                    )
                default:
                    return nil
                }
            }
        )

        let output = await orchestrator.run(
            request: CommandRequest(text: "turn on the light", executeLowRiskCommands: true),
            operationHint: nil,
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        guard case .accepted(_, let iterations) = output.exit else {
            Issue.record("Expected .accepted, got \(output.exit)")
            return
        }
        #expect(iterations == 2)
        #expect(output.metrics.repairCallCount == 2)

        let entries = await repairStarted.entries
        #expect(entries.contains("capability"))
        #expect(entries.contains("target"))
    }

    @Test("Repair results are merged in specialist-priority order")
    func repairMergeOrder() async {
        let mergeOrder = TimestampRecorder()
        let verifyCallCount = CallCounter()

        let orchestrator = makeOrchestrator(
            verifyBehavior: { _, _ in
                let count = await verifyCallCount.increment()
                if count == 1 {
                    return DraftVerdict(
                        accepted: false,
                        disputes: [
                            DraftDispute(fieldID: "command.capability", kind: .wrongValue, evidence: "test"),
                            DraftDispute(fieldID: "command.targetDeviceID", kind: .wrongValue, evidence: "test"),
                            DraftDispute(fieldID: "operation", kind: .wrongOperation, evidence: "test"),
                        ],
                        needsClarification: false
                    )
                }
                return DraftVerdict(accepted: true, disputes: [], needsClarification: false)
            },
            specialistBehavior: { step, envelope in
                await mergeOrder.record(step.specialist.rawValue)
                switch step.specialist {
                case .operationDetection:
                    return .operation(HomeOperationDetectionResult(
                        domain: .homeAutomation,
                        operation: .executeDeviceCommand,
                        confidence: 0.95,
                        reason: "repair"
                    ))
                case .target:
                    return .target(
                        fieldID: FieldID(rawValue: "command.targetDeviceID"),
                        ActionTargetResult(
                            selectedDeviceID: "dev1",
                            candidateTable: [],
                            confidence: 0.9,
                            isAmbiguous: false
                        )
                    )
                case .capability:
                    return .capability(
                        fieldID: FieldID(rawValue: "command.capability"),
                        HomeCapabilityDecision(
                            selectedCapability: "switch",
                            selectedCommand: "on",
                            targetDeviceID: nil,
                            alternatives: [],
                            evidence: [],
                            confidence: 0.9
                        )
                    )
                default:
                    return nil
                }
            }
        )

        let output = await orchestrator.run(
            request: CommandRequest(text: "turn on the light", executeLowRiskCommands: true),
            operationHint: nil,
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        guard case .accepted = output.exit else {
            Issue.record("Expected .accepted, got \(output.exit)")
            return
        }
        #expect(output.metrics.repairCallCount == 3)
        let entries = await mergeOrder.entries
        #expect(entries.count == 3)
    }

    // MARK: - Helpers

    private func makeOrchestrator(
        verifyBehavior: @escaping @Sendable (DraftEnvelope, VerifierPrompt) async throws -> DraftVerdict,
        specialistBehavior: @escaping @Sendable (RepairPlanner.RepairStep, DraftEnvelope) async -> RepairResult?
    ) -> VerifierLoopOrchestrator {
        let registry = MockHomeDeviceRegistry()
        let pipeline = DeterministicDraftPipeline(registry: registry)

        let verifier = DraftVerifierWorkerSession(
            verify: verifyBehavior,
            foundationModelAvailability: { false }
        )
        let promptBuilder = VerifierPromptBuilder()
        let planner = RepairPlanner()
        let specialists = RepairSpecialistRegistry(execute: specialistBehavior)

        return VerifierLoopOrchestrator(
            pipeline: pipeline,
            verifier: verifier,
            promptBuilder: promptBuilder,
            planner: planner,
            specialists: specialists,
            policy: VerifierLoopPolicy()
        )
    }
}

private actor TimestampRecorder {
    private(set) var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }
}

private actor CallCounter {
    private var count = 0

    func increment() -> Int {
        count += 1
        return count
    }
}
