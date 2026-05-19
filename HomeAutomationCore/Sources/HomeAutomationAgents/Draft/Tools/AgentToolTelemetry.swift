import Foundation
import HomeAutomationCore

func agentStartToolTelemetry<T>(toolName: String, arguments: T) async -> Date {
    let startedAt = Date()
    await HomeAutomationTelemetry.shared.logToolInput(
        toolName: toolName,
        arguments: String(describing: arguments)
    )
    return startedAt
}

func agentFinishToolTelemetry(
    toolName: String,
    output: String,
    outputSizeStore: AgentToolOutputSizeStore,
    startedAt: Date
) async -> String {
    outputSizeStore.record(toolName: toolName, characterCount: output.count)
    await HomeAutomationTelemetry.shared.logToolOutput(
        toolName: toolName,
        output: output,
        durationMs: Date().timeIntervalSince(startedAt) * 1_000
    )
    return output
}
