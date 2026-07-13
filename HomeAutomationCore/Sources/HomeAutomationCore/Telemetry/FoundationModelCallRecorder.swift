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

        let admission = await admissionController.admitRequest(priority: priority)
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

        case .admitted(let queueWaitMs):
            if Task.isCancelled {
                await admissionController.release()
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
                await admissionController.release()
                let outputCount = outputCharacterCount(value)
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
                await admissionController.release()
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

    private static func milliseconds(from start: UInt64, to end: UInt64) -> Double {
        guard end >= start else { return 0 }
        return Double(end - start) / 1_000_000
    }
}
