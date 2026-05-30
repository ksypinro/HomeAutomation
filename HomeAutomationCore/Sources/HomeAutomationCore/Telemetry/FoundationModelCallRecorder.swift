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
        operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        let startedAt = Date()
        let parent = HomeAutomationTelemetryScope.current
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
                "policyMode": .string(policyMode),
                "modelAvailability": .string(modelAvailability),
                "promptCharacterCount": .int(promptCharacterCount),
                "selectedToolNames": .string(selectedToolNames.joined(separator: ",")),
                "estimatedToolOutputCharacterCount": .int(estimatedToolOutputCharacterCount)
            ], privacy: [
                "modelCallID": .internalID
            ])
        )

        do {
            let value = try await HomeAutomationTelemetryScope.$current.withValue(context) {
                try await operation()
            }
            let completedAt = Date()
            await HomeAutomationTelemetry.shared.log(
                "model.call.completed",
                context: context,
                status: .completed,
                spanKind: .modelCall,
                startedAt: startedAt,
                completedAt: completedAt,
                durationMs: completedAt.timeIntervalSince(startedAt) * 1_000,
                payload: TelemetryPayload(values: [
                    "modelCallID": .string(modelCallID),
                    "outputCharacterCount": .int(outputCharacterCount(value))
                ], privacy: [
                    "modelCallID": .internalID
                ])
            )
            return value
        } catch {
            let completedAt = Date()
            await HomeAutomationTelemetry.shared.log(
                "model.call.failed",
                context: context,
                status: .failed,
                spanKind: .modelCall,
                startedAt: startedAt,
                completedAt: completedAt,
                durationMs: completedAt.timeIntervalSince(startedAt) * 1_000,
                payload: TelemetryPayload(values: [
                    "modelCallID": .string(modelCallID),
                    "failureKind": .string(FoundationModelDiagnostics.failureKind(for: error).rawValue),
                    "error": .string(error.localizedDescription)
                ], privacy: [
                    "modelCallID": .internalID,
                    "error": .modelOutput
                ])
            )
            throw error
        }
    }
}

