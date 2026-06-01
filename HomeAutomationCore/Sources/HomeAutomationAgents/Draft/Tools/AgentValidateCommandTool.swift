import Foundation
import FoundationModels
import HomeAutomationCore

public struct AgentValidateCommandTool: Tool, ToolRuntimeIdentifiable {
    public let name = "validateCommand"
    public var toolID: String { name }
    public let toolSessionID = UUID().uuidString
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
    public struct Arguments: AgentToolTraceArguments {
        @Guide(description: "Device ID from hydrated candidates or tool output.")
        public let deviceID: String
        @Guide(description: "Capability name from canonical registry context.")
        public let capability: String
        @Guide(description: "Command name to validate for the capability.")
        public let command: String
        @Guide(description: "Tracing only: caller agent ID. Pass the value provided in tool trace instructions.")
        public let agentID: String?
        @Guide(description: "Tracing only: caller agent session ID. Pass the value provided in tool trace instructions.")
        public let agentSessionID: String?
        @Guide(description: "Tracing only: caller agent run ID. Pass the value provided in tool trace instructions.")
        public let agentRunID: Int?

        public init(
            deviceID: String,
            capability: String,
            command: String,
            agentID: String? = nil,
            agentSessionID: String? = nil,
            agentRunID: Int? = nil
        ) {
            self.deviceID = deviceID
            self.capability = capability
            self.command = command
            self.agentID = agentID
            self.agentSessionID = agentSessionID
            self.agentRunID = agentRunID
        }
    }

    public func call(arguments: Arguments) async throws -> String {
        let callContext = await agentStartToolTelemetry(toolID: toolID, toolSessionID: toolSessionID, arguments: arguments)
        guard let device = await agentToolDevice(arguments.deviceID, in: registry) else {
            return await recordOutput(#"{"valid":false,"reason":"device unavailable"}"#, callContext: callContext)
        }
        guard device.capabilities.contains(arguments.capability) else {
            return await recordOutput(#"{"valid":false,"reason":"capability unavailable","supportedCapabilities":"\#(device.capabilities.joined(separator: ","))"}"#, callContext: callContext)
        }
        let supportedCommands = device.supportedCommands[arguments.capability, default: []]
        guard arguments.command == "getStatus" || supportedCommands.contains(arguments.command) else {
            return await recordOutput(#"{"valid":false,"reason":"command unavailable","supportedCommands":"\#(supportedCommands.joined(separator: ","))"}"#, callContext: callContext)
        }
        let risk = HomeCapabilityRegistry.riskLevel(for: arguments.capability)
        return await recordOutput(#"{"valid":true,"reason":"supported","risk":"\#(risk)"}"#, callContext: callContext)
    }

    private func recordOutput(_ output: String, callContext: ToolTelemetryCallContext) async -> String {
        await agentFinishToolTelemetry(
            output: output,
            outputSizeStore: outputSizeStore,
            callContext: callContext
        )
    }
}
