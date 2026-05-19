import Foundation
import FoundationModels
import HomeAutomationCore

public struct AgentGetDeviceStateTool: Tool {
    public let name = "getCurrentDeviceState"
    public let description = "Reads current state values for a device ID."
    private let registry: MockHomeDeviceRegistry
    private let outputSizeStore: AgentToolOutputSizeStore

    public init(
        registry: MockHomeDeviceRegistry,
        outputSizeStore: AgentToolOutputSizeStore = .shared
    ) {
        self.registry = registry
        self.outputSizeStore = outputSizeStore
    }

    @Generable
    public struct Arguments {
        @Guide(description: "Device ID from hydrated candidates or tool output.")
        public let deviceID: String
    }

    public func call(arguments: Arguments) async throws -> String {
        let startedAt = await agentStartToolTelemetry(toolName: name, arguments: arguments)
        guard let device = await agentToolDevice(arguments.deviceID, in: registry) else {
            return await recordOutput(#"{"error":"device unavailable"}"#, startedAt: startedAt)
        }
        return await recordOutput(AgentToolFormatting.dictionary(device.currentState), startedAt: startedAt)
    }

    private func recordOutput(_ output: String, startedAt: Date) async -> String {
        await agentFinishToolTelemetry(
            toolName: name,
            output: output,
            outputSizeStore: outputSizeStore,
            startedAt: startedAt
        )
    }
}
