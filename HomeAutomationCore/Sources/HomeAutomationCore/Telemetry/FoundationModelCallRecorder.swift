import Foundation

public struct FoundationModelCallRecorder: Sendable {
    public init() {}

    public static func record<Value: Sendable>(
        agentID: String,
        modelCallID: String = UUID().uuidString,
        policyMode: String = "unknown",
        modelAvailability: String = "unknown",
        promptCharacterCount: Int,
        outputCharacterCount: @Sendable @escaping (Value) -> Int = { String(describing: $0).count },
        selectedToolNames: [String] = [],
        estimatedToolOutputCharacterCount: Int = 0,
        priority: FMPriority = .interactive,
        arm: FoundationModelCallArm? = nil,
        jobID: String? = nil,
        jobKind: FoundationModelJobKind? = nil,
        sessionReuse: FoundationModelSessionReuse = .unknown,
        escalationChain: [FoundationModelEscalationStep]? = nil,
        admissionController: any FoundationModelAdmissionControlling = FoundationModelGate.shared,
        clock: any FoundationModelMonotonicClock = SystemFoundationModelMonotonicClock(),
        operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        let parent = HomeAutomationTelemetryScope.current
        let ledger = FoundationModelUsageLedgerScope.current
        let enqueuedAtNanoseconds = clock.nowNanoseconds()
        let effectiveArm = arm ?? parent?.foundationModelArm ?? .unknown
        let effectiveJobID = jobID ?? parent?.foundationModelJobID ?? modelCallID
        let effectiveJobKind = jobKind ?? parent?.foundationModelJobKind ?? defaultJobKind(agentID: agentID)
        let effectiveEscalationChain = escalationChain ?? parent?.foundationModelEscalationChain ?? []
        let admissionContext = (FMAdmissionContextScope.current ?? FMAdmissionContext())
            .merging(
                runID: parent?.runID,
                graphID: parent?.graphID,
                nodeID: parent?.graphNodeID,
                agentID: agentID,
                jobKind: effectiveJobKind,
                deadlineClass: priority == .interactive ? .interactive : .pipeline,
                cancellationClass: .normal
            )
        let request = FoundationModelCallRequest(
            modelCallID: modelCallID,
            arm: effectiveArm,
            jobID: effectiveJobID,
            jobKind: effectiveJobKind,
            graphID: parent?.graphID,
            nodeID: parent?.graphNodeID,
            agentID: agentID,
            attempt: parent?.attempt,
            escalationChain: effectiveEscalationChain,
            priority: priority,
            promptCharacterCount: promptCharacterCount,
            selectedToolNames: selectedToolNames,
            sessionReuse: sessionReuse,
            modelAvailability: FoundationModelAvailabilityState(label: modelAvailability)
        )
        if let ledger {
            await measureLedgerOverhead(ledger: ledger, clock: clock) {
                _ = try? await ledger.enqueue(request, atNanoseconds: enqueuedAtNanoseconds)
            }
        }

        let admissionRequest = FMAdmissionRequest(
            modelCallID: modelCallID,
            priority: priority,
            schedulerMode: admissionContext.schedulerMode ?? .legacy,
            enqueuedAtNanoseconds: enqueuedAtNanoseconds,
            runID: admissionContext.runID,
            graphID: admissionContext.graphID,
            nodeID: admissionContext.nodeID,
            agentID: admissionContext.agentID,
            jobKind: admissionContext.jobKind,
            criticalPathRemainingMs: admissionContext.criticalPathRemainingMs,
            estimatedServiceMs: admissionContext.estimatedServiceMs,
            deadlineClass: admissionContext.deadlineClass,
            cancellationClass: admissionContext.cancellationClass,
            prefixAffinityKey: admissionContext.prefixAffinityKey,
            workflowScopeID: admissionContext.workflowScopeID
        )
        let admission = await admissionController.admit(admissionRequest)
        switch admission {
        case .cancelled(let queueWaitMs):
            let cancelledAt = clock.nowNanoseconds()
            if let ledger {
                await measureLedgerOverhead(ledger: ledger, clock: clock) {
                    try? await ledger.cancel(
                        modelCallID: modelCallID,
                        atNanoseconds: cancelledAt,
                        reason: .taskCancelledBeforeAdmission,
                        queueWaitMs: queueWaitMs
                    )
                }
            }
            await logCancellation(
                modelCallID: modelCallID,
                agentID: agentID,
                parent: parent,
                queueWaitMs: queueWaitMs,
                reason: .taskCancelledBeforeAdmission
            )
            throw CancellationError()

        case .admitted(let lease, let queueWaitMs, let fallbackReason, let shadowRank):
            if Task.isCancelled {
                await admissionController.release(leaseID: lease.leaseID)
                let cancelledAt = clock.nowNanoseconds()
                if let ledger {
                    await measureLedgerOverhead(ledger: ledger, clock: clock) {
                        try? await ledger.cancel(
                            modelCallID: modelCallID,
                            atNanoseconds: cancelledAt,
                            reason: .taskCancelledBeforeAdmission,
                            queueWaitMs: queueWaitMs
                        )
                    }
                }
                await logCancellation(
                    modelCallID: modelCallID,
                    agentID: agentID,
                    parent: parent,
                    queueWaitMs: queueWaitMs,
                    reason: .taskCancelledBeforeAdmission
                )
                throw CancellationError()
            }

            let startedAt = Date()
            let context = (parent ?? HomeAutomationTelemetryContext())
                .merging(
                    spanID: TelemetryTraceContext.makeSpanID(),
                    parentSpanID: parent?.spanID,
                    spanKind: .modelCall,
                    agentID: agentID
                )
            await HomeAutomationTelemetry.shared.log(
                "model.call.started",
                context: context,
                status: .running,
                spanKind: .modelCall,
                startedAt: startedAt,
                completedAt: nil,
                payload: TelemetryPayload(values: [
                    "modelCallID": .string(modelCallID),
                    "jobID": .string(effectiveJobID),
                    "jobKind": .string(effectiveJobKind.rawValue),
                    "arm": .string(effectiveArm.rawValue),
                    "escalationChain": .string(effectiveEscalationChain.map(\.rawValue).joined(separator: ",")),
                    "policyMode": .string(policyMode),
                    "modelAvailability": .string(modelAvailability),
                    "promptCharacterCount": .int(promptCharacterCount),
                    "selectedToolNames": .string(selectedToolNames.joined(separator: ",")),
                    "estimatedToolOutputCharacterCount": .int(estimatedToolOutputCharacterCount),
                    "fmQueueWaitMs": .double(queueWaitMs),
                    "fmPriority": .string(priority.rawValue),
                    "fmAdmissionLeaseID": .string(lease.leaseID.uuidString),
                    "fmSchedulerMode": .string(lease.schedulerMode.rawValue),
                    "fmAdmissionFallbackReason": .string(fallbackReason.rawValue),
                    "fmFrontierShadowRank": .string(shadowRank.joined(separator: ",")),
                    "sessionReuse": .string(sessionReuse.rawValue)
                ], privacy: [
                    "modelCallID": .internalID,
                    "jobID": .internalID
                ])
            )

            let admittedAtNanoseconds = clock.nowNanoseconds()
            if let ledger {
                await measureLedgerOverhead(ledger: ledger, clock: clock) {
                    try? await ledger.start(
                        modelCallID: modelCallID,
                        atNanoseconds: admittedAtNanoseconds,
                        queueWaitMs: queueWaitMs
                    )
                }
            }
            let serviceStartedAtNanoseconds = clock.nowNanoseconds()

            do {
                let value = try await HomeAutomationTelemetryScope.$current.withValue(context) {
                    try await operation()
                }
                let serviceCompletedAtNanoseconds = clock.nowNanoseconds()
                await admissionController.release(leaseID: lease.leaseID)
                let outputCount = outputCharacterCount(value)
                await recordServiceEstimate(
                    agentID: agentID,
                    jobKind: effectiveJobKind,
                    priority: priority,
                    startedAt: serviceStartedAtNanoseconds,
                    completedAt: serviceCompletedAtNanoseconds
                )
                if let ledger {
                    await measureLedgerOverhead(ledger: ledger, clock: clock) {
                        try? await ledger.complete(
                            modelCallID: modelCallID,
                            atNanoseconds: serviceCompletedAtNanoseconds,
                            outputCharacterCount: outputCount,
                            serviceStartedAtNanoseconds: serviceStartedAtNanoseconds
                        )
                    }
                }
                let completedAt = Date()
                await HomeAutomationTelemetry.shared.log(
                    "model.call.completed",
                    context: context,
                    status: .completed,
                    spanKind: .modelCall,
                    startedAt: startedAt,
                    completedAt: completedAt,
                    durationMs: milliseconds(from: serviceStartedAtNanoseconds, to: serviceCompletedAtNanoseconds),
                    payload: TelemetryPayload(values: [
                        "modelCallID": .string(modelCallID),
                        "outputCharacterCount": .int(outputCount)
                    ], privacy: [
                        "modelCallID": .internalID
                    ])
                )
                return value
            } catch {
                let serviceCompletedAtNanoseconds = clock.nowNanoseconds()
                await admissionController.release(leaseID: lease.leaseID)
                await recordServiceEstimate(
                    agentID: agentID,
                    jobKind: effectiveJobKind,
                    priority: priority,
                    startedAt: serviceStartedAtNanoseconds,
                    completedAt: serviceCompletedAtNanoseconds
                )
                let completedAt = Date()
                if error is CancellationError || Task.isCancelled {
                    if let ledger {
                        await measureLedgerOverhead(ledger: ledger, clock: clock) {
                            try? await ledger.cancel(
                                modelCallID: modelCallID,
                                atNanoseconds: serviceCompletedAtNanoseconds,
                                reason: .taskCancelledAfterAdmission,
                                serviceStartedAtNanoseconds: serviceStartedAtNanoseconds
                            )
                        }
                    }
                    await HomeAutomationTelemetry.shared.log(
                        "model.call.cancelled",
                        context: context,
                        status: .cancelled,
                        spanKind: .modelCall,
                        startedAt: startedAt,
                        completedAt: completedAt,
                        durationMs: milliseconds(from: serviceStartedAtNanoseconds, to: serviceCompletedAtNanoseconds),
                        payload: TelemetryPayload(values: [
                            "modelCallID": .string(modelCallID),
                            "cancellationReason": .string(FoundationModelCallCancellationReason.taskCancelledAfterAdmission.rawValue)
                        ], privacy: [
                            "modelCallID": .internalID
                        ])
                    )
                } else {
                    let failureKind = FoundationModelDiagnostics.failureKind(for: error)
                    if let ledger {
                        await measureLedgerOverhead(ledger: ledger, clock: clock) {
                            try? await ledger.fail(
                                modelCallID: modelCallID,
                                atNanoseconds: serviceCompletedAtNanoseconds,
                                failureKind: failureKind,
                                serviceStartedAtNanoseconds: serviceStartedAtNanoseconds
                            )
                        }
                    }
                    await HomeAutomationTelemetry.shared.log(
                        "model.call.failed",
                        context: context,
                        status: .failed,
                        spanKind: .modelCall,
                        startedAt: startedAt,
                        completedAt: completedAt,
                        durationMs: milliseconds(from: serviceStartedAtNanoseconds, to: serviceCompletedAtNanoseconds),
                        payload: TelemetryPayload(values: [
                            "modelCallID": .string(modelCallID),
                            "failureKind": .string(failureKind.rawValue),
                            "error": .string(error.localizedDescription)
                        ], privacy: [
                            "modelCallID": .internalID,
                            "error": .modelOutput
                        ])
                    )
                }
                throw error
            }
        }
    }

    private static func defaultJobKind(agentID: String) -> FoundationModelJobKind {
        switch agentID {
        case "operationDetection":
            .operationDetection
        case "semanticNLU":
            .semanticNLU
        case "slotExtraction":
            .slotExtraction
        case "riskClassification":
            .riskClassification
        case "capabilityResolution", "candidateRanking", "candidateShard":
            .candidateResolution
        case "automationDraft", "draftGeneration":
            .draftGeneration
        case "automationTriggerResolution",
             "automationConditionClauseResolution",
             "automationComponentSegmentation":
            .automationResolution
        case "draftVerifier":
            .verifier
        case "fragmentNLU":
            .repair
        case "conditionOperandResolver", "automationConditionOperandResolution":
            .automationResolution
        case "commandParaphraseProvider", "evaluationCommandParaphrase":
            .evaluation
        default:
            .unknown
        }
    }

    private static func logCancellation(
        modelCallID: String,
        agentID: String,
        parent: HomeAutomationTelemetryContext?,
        queueWaitMs: Double,
        reason: FoundationModelCallCancellationReason
    ) async {
        let context = (parent ?? HomeAutomationTelemetryContext()).merging(agentID: agentID)
        await HomeAutomationTelemetry.shared.log(
            "model.call.cancelled",
            context: context,
            status: .cancelled,
            spanKind: .modelCall,
            payload: TelemetryPayload(values: [
                "modelCallID": .string(modelCallID),
                "fmQueueWaitMs": .double(queueWaitMs),
                "cancellationReason": .string(reason.rawValue)
            ], privacy: [
                "modelCallID": .internalID
            ])
        )
    }

    private static func measureLedgerOverhead(
        ledger: FoundationModelUsageLedger,
        clock: any FoundationModelMonotonicClock,
        operation: () async -> Void
    ) async {
        let started = clock.nowNanoseconds()
        await operation()
        let completed = clock.nowNanoseconds()
        await ledger.recordTelemetryOverhead(milliseconds: milliseconds(from: started, to: completed))
    }

    private static func recordServiceEstimate(
        agentID: String,
        jobKind: FoundationModelJobKind,
        priority: FMPriority,
        startedAt: UInt64,
        completedAt: UInt64
    ) async {
        let duration = milliseconds(from: startedAt, to: completedAt)
        await FMServiceTimeEstimator.shared.recordServiceTime(
            milliseconds: duration,
            key: FMServiceTimeEstimatorKey(agentID: agentID, jobKind: jobKind, priority: priority)
        )
    }

    private static func milliseconds(from start: UInt64, to end: UInt64) -> Double {
        guard end >= start else { return 0 }
        return Double(end - start) / 1_000_000
    }
}
