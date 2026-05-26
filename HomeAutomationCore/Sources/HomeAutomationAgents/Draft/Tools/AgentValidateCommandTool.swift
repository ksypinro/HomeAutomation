import Foundation
import FoundationModels
import HomeAutomationCore

public struct AgentValidateCommandTool: Tool {
    public let name = "validateCommand"
    public let description = "Pre-validates whether a device supports a capability command."
    private let registry: any DeviceRegistryProtocol
    private let outputSizeStore: AgentToolOutputSizeStore

    public init(
        registry: any DeviceRegistryProtocol,
        outputSizeStore: AgentToolOutputSizeStore = .shared
    ) {
        self.registry = registry
        self.outputSizeStore = outputSizeStore
    }

    @Generable
    public struct Arguments {
        @Guide(description: "Device ID from hydrated candidates or tool output.")
        public let deviceID: String
        @Guide(description: "Capability name from canonical registry context.")
        public let capability: String
        @Guide(description: "Command name to validate for the capability.")
        public let command: String
    }

    public func call(arguments: Arguments) async throws -> String {
        let startedAt = await agentStartToolTelemetry(toolName: name, arguments: arguments)
        guard let device = await agentToolDevice(arguments.deviceID, in: registry) else {
            return await recordOutput(#"{"valid":false,"reason":"device unavailable"}"#, startedAt: startedAt)
        }
        guard device.capabilities.contains(arguments.capability) else {
            return await recordOutput(#"{"valid":false,"reason":"capability unavailable","supportedCapabilities":"\#(device.capabilities.joined(separator: ","))"}"#, startedAt: startedAt)
        }
        let supportedCommands = device.supportedCommands[arguments.capability, default: []]
        guard arguments.command == "getStatus" || supportedCommands.contains(arguments.command) else {
            return await recordOutput(#"{"valid":false,"reason":"command unavailable","supportedCommands":"\#(supportedCommands.joined(separator: ","))"}"#, startedAt: startedAt)
        }
        let risk = HomeCapabilityRegistry.riskLevel(for: arguments.capability)
        return await recordOutput(#"{"valid":true,"reason":"supported","risk":"\#(risk)"}"#, startedAt: startedAt)
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
