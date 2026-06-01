import Foundation
import HomeAutomationCore

func agentStartToolTelemetry<T>(
    toolID: String,
    toolSessionID: String,
    arguments: T
) async -> ToolTelemetryCallContext {
    await HomeAutomationTelemetry.shared.startToolCall(
        toolID: toolID,
        toolSessionID: toolSessionID,
        arguments: String(describing: arguments),
        agentTrace: arguments as? any AgentToolTraceArguments
    )
}

func agentFinishToolTelemetry(
    output: String,
    outputSizeStore: AgentToolOutputSizeStore,
    callContext: ToolTelemetryCallContext
) async -> String {
    outputSizeStore.record(toolName: callContext.telemetryContext.toolID ?? "", characterCount: output.count)
    await HomeAutomationTelemetry.shared.finishToolCall(
        callContext,
        output: output,
        durationMs: Date().timeIntervalSince(callContext.startedAt) * 1_000
    )
    return output
}
