import Foundation
import FoundationModels
import HomeAutomationAgents
import HomeAutomationCore
import os

public struct VerifierLoopOrchestrator: Sendable {
    private let pipeline: DeterministicDraftPipeline
    private let verifier: DraftVerifierWorkerSession
    private let promptBuilder: VerifierPromptBuilder
    private let planner: RepairPlanner
    private let specialists: RepairSpecialistRegistry
    private let policy: VerifierLoopPolicy
    private let logger = Logger(subsystem: "HomeAutomation", category: "Loop.Orchestrator")

    public init(
        pipeline: DeterministicDraftPipeline,
        verifier: DraftVerifierWorkerSession,
        promptBuilder: VerifierPromptBuilder,
        planner: RepairPlanner,
        specialists: RepairSpecialistRegistry,
        policy: VerifierLoopPolicy = VerifierLoopPolicy()
    ) {
        self.pipeline = pipeline
        self.verifier = verifier
        self.promptBuilder = promptBuilder
        self.planner = planner
        self.specialists = specialists
        self.policy = policy
    }

    public struct LoopOutput: Sendable {
        public let exit: LoopExit
        public let metrics: LoopRunMetrics
    }

    public func run(
        request: CommandRequest,
        operationHint: HomeOperationDetectionResult?,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> LoopOutput {
        var verifierCallCount = 0
        var repairCallCount = 0
        var disputedFieldIDsPerIteration: [[String]] = []
        var preVerifyRepairCount = 0

        let envelope: DraftEnvelope
        if let hint = operationHint, hint.operation == .automationCreation {
            envelope = await pipeline.makeAutomationEnvelope(text: request.text)
        } else {
            envelope = await pipeline.makeCommandEnvelope(text: request.text)
        }

        await publishEvent(eventBus, runID: runID, stage: "verifierLoop/envelope", detail: "Stage 0 envelope built")

        var currentEnvelope = envelope
        var latchedFieldIDs: Set<FieldID> = []

        let zeroConfFields = currentEnvelope.fieldConfidence.filter { $0.value == 0.0 }.map(\.key)
        if !zeroConfFields.isEmpty {
            let syntheticDisputes = zeroConfFields.map { fieldID in
                DraftDispute(fieldID: fieldID.rawValue, kind: .missing, evidence: "confidence is 0")
            }
            let preRepairPlan = planner.plan(
                disputes: syntheticDisputes,
                envelope: currentEnvelope,
                latchedFieldIDs: [],
                maxRepairCalls: policy.maxRepairCallsPerIteration
            )

            for step in preRepairPlan.steps {
                if let result = await specialists.execute(step, currentEnvelope) {
                    currentEnvelope = EnvelopeMerger.apply(result, to: currentEnvelope, iteration: 0)
                    preVerifyRepairCount += 1
                    repairCallCount += 1
                }
            }

            await publishEvent(eventBus, runID: runID, stage: "verifierLoop/preRepair", detail: "Pre-verify repair: \(preVerifyRepairCount) fields patched")
        }

        let verifierSession = verifier.makeSession()

        for iteration in 1...policy.maxIterations {
            let prompt: VerifierPrompt
            if iteration == 1 {
                prompt = promptBuilder.makeInitialPrompt(envelope: currentEnvelope)
            } else {
                let previousDisputes = disputedFieldIDsPerIteration.last.map { ids in
                    ids.compactMap { id in
                        DraftDispute(fieldID: id, kind: .wrongValue, evidence: "prior iteration dispute")
                    }
                } ?? []
                prompt = promptBuilder.makeDeltaPrompt(
                    envelope: currentEnvelope,
                    previousDisputes: previousDisputes,
                    repairedFields: Array(latchedFieldIDs)
                )
            }

            await publishEvent(eventBus, runID: runID, stage: "verifierLoop/verify/\(iteration)", detail: "Verifying iteration \(iteration)")

            let verdict: DraftVerdict
            do {
                verdict = try await verifier.verify(envelope: currentEnvelope, prompt: prompt, session: verifierSession)
                verifierCallCount += 1
            } catch is VerifierUnavailable {
                logger.info("Verifier unavailable, escalating with deterministic envelope.")
                return LoopOutput(
                    exit: .escalated(envelope: currentEnvelope, reason: .verifierUnavailable),
                    metrics: makeMetrics(
                        iterations: iteration,
                        verifierCallCount: verifierCallCount,
                        repairCallCount: repairCallCount,
                        disputedFieldIDsPerIteration: disputedFieldIDsPerIteration,
                        escalationReason: .verifierUnavailable,
                        preVerifyRepairCount: preVerifyRepairCount
                    )
                )
            } catch {
                logger.error("Verifier error: \(error.localizedDescription, privacy: .public)")
                return LoopOutput(
                    exit: .escalated(envelope: currentEnvelope, reason: .verifierUnavailable),
                    metrics: makeMetrics(
                        iterations: iteration,
                        verifierCallCount: verifierCallCount,
                        repairCallCount: repairCallCount,
                        disputedFieldIDsPerIteration: disputedFieldIDsPerIteration,
                        escalationReason: .verifierUnavailable,
                        preVerifyRepairCount: preVerifyRepairCount
                    )
                )
            }

            await publishEvent(eventBus, runID: runID, stage: "verifierLoop/verdict/\(iteration)", detail: verdict.accepted ? "Accepted" : "Disputed: \(verdict.disputes.count) fields")

            if verdict.accepted {
                return LoopOutput(
                    exit: .accepted(envelope: currentEnvelope, iterations: iteration),
                    metrics: makeMetrics(
                        iterations: iteration,
                        acceptedOnIteration: iteration,
                        verifierCallCount: verifierCallCount,
                        repairCallCount: repairCallCount,
                        disputedFieldIDsPerIteration: disputedFieldIDsPerIteration,
                        preVerifyRepairCount: preVerifyRepairCount
                    )
                )
            }

            if verdict.needsClarification && verdict.disputes.isEmpty {
                let question = currentEnvelope.clarification?.question ?? "Could you clarify?"
                return LoopOutput(
                    exit: .clarification(envelope: currentEnvelope, question: question, iterations: iteration),
                    metrics: makeMetrics(
                        iterations: iteration,
                        verifierCallCount: verifierCallCount,
                        repairCallCount: repairCallCount,
                        disputedFieldIDsPerIteration: disputedFieldIDsPerIteration,
                        preVerifyRepairCount: preVerifyRepairCount
                    )
                )
            }

            let currentDisputeIDs = verdict.disputes.map(\.fieldID)
            disputedFieldIDsPerIteration.append(currentDisputeIDs)

            if policy.requireStrictProgress, iteration > 1 {
                let previousDisputeIDs = Set(disputedFieldIDsPerIteration[iteration - 2])
                let currentSet = Set(currentDisputeIDs)
                if currentSet == previousDisputeIDs || currentSet.count >= previousDisputeIDs.count {
                    logger.info("No progress detected at iteration \(iteration).")
                    return LoopOutput(
                        exit: .escalated(envelope: currentEnvelope, reason: .noProgress),
                        metrics: makeMetrics(
                            iterations: iteration,
                            verifierCallCount: verifierCallCount,
                            repairCallCount: repairCallCount,
                            disputedFieldIDsPerIteration: disputedFieldIDsPerIteration,
                            escalationReason: .noProgress,
                            preVerifyRepairCount: preVerifyRepairCount
                        )
                    )
                }
            }

            let repairPlan = planner.plan(
                disputes: verdict.disputes,
                envelope: currentEnvelope,
                latchedFieldIDs: latchedFieldIDs,
                maxRepairCalls: policy.maxRepairCallsPerIteration
            )

            if repairPlan.steps.isEmpty {
                if !repairPlan.deferred.isEmpty {
                    return LoopOutput(
                        exit: .escalated(envelope: currentEnvelope, reason: .repairLatch),
                        metrics: makeMetrics(
                            iterations: iteration,
                            verifierCallCount: verifierCallCount,
                            repairCallCount: repairCallCount,
                            disputedFieldIDsPerIteration: disputedFieldIDsPerIteration,
                            escalationReason: .repairLatch,
                            preVerifyRepairCount: preVerifyRepairCount
                        )
                    )
                }
                return LoopOutput(
                    exit: .escalated(envelope: currentEnvelope, reason: .noProgress),
                    metrics: makeMetrics(
                        iterations: iteration,
                        verifierCallCount: verifierCallCount,
                        repairCallCount: repairCallCount,
                        disputedFieldIDsPerIteration: disputedFieldIDsPerIteration,
                        escalationReason: .noProgress,
                        preVerifyRepairCount: preVerifyRepairCount
                    )
                )
            }

            await publishEvent(eventBus, runID: runID, stage: "verifierLoop/repair/\(iteration)", detail: "Repairing \(repairPlan.steps.count) steps")

            for step in repairPlan.steps {
                if let result = await specialists.execute(step, currentEnvelope) {
                    currentEnvelope = EnvelopeMerger.apply(result, to: currentEnvelope, iteration: iteration)
                    repairCallCount += 1
                }
            }

            for step in repairPlan.steps {
                for fieldID in step.fieldIDs {
                    latchedFieldIDs.insert(fieldID)
                }
            }
        }

        return LoopOutput(
            exit: .escalated(envelope: currentEnvelope, reason: .iterationCap),
            metrics: makeMetrics(
                iterations: policy.maxIterations,
                verifierCallCount: verifierCallCount,
                repairCallCount: repairCallCount,
                disputedFieldIDsPerIteration: disputedFieldIDsPerIteration,
                escalationReason: .iterationCap,
                preVerifyRepairCount: preVerifyRepairCount
            )
        )
    }

    // MARK: - Helpers

    private func makeMetrics(
        iterations: Int,
        acceptedOnIteration: Int? = nil,
        verifierCallCount: Int,
        repairCallCount: Int,
        disputedFieldIDsPerIteration: [[String]],
        escalationReason: EscalationReason? = nil,
        preVerifyRepairCount: Int
    ) -> LoopRunMetrics {
        LoopRunMetrics(
            iterations: iterations,
            acceptedOnIteration: acceptedOnIteration,
            verifierCallCount: verifierCallCount,
            repairCallCount: repairCallCount,
            disputedFieldIDsPerIteration: disputedFieldIDsPerIteration,
            escalationReason: escalationReason?.rawValue,
            preVerifyRepairCount: preVerifyRepairCount
        )
    }

    private func publishEvent(
        _ eventBus: AgentEventBus,
        runID: UUID,
        stage: String,
        detail: String
    ) async {
        let event = OrchestratorPipelineEvent(
            runID: runID,
            stage: stage,
            status: .completed,
            detail: detail
        )
        await eventBus.publish(event)
    }
}
