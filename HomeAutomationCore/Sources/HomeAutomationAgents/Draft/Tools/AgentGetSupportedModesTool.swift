import Foundation
import FoundationModels
import HomeAutomationCore

public struct AgentGetSupportedModesTool: Tool, ToolRuntimeIdentifiable {
    public let name = "getSupportedModes"
    public var toolID: String { name }
    public let toolSessionID = UUID().uuidString
    public let description = "Gets supported enum or mode values for a device capability."
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

        @Guide(description: "Tracing only: caller agent ID. Pass the value provided in tool trace instructions.")
        public let agentID: String?
        @Guide(description: "Tracing only: caller agent session ID. Pass the value provided in tool trace instructions.")
        public let agentSessionID: String?
        @Guide(description: "Tracing only: caller agent run ID. Pass the value provided in tool trace instructions.")
        public let agentRunID: Int?

        public init(
            deviceID: String,
            capability: String,
            agentID: String? = nil,
            agentSessionID: String? = nil,
            agentRunID: Int? = nil
        ) {
            self.deviceID = deviceID
            self.capability = capability
            self.agentID = agentID
            self.agentSessionID = agentSessionID
            self.agentRunID = agentRunID
        }
    }

    public func call(arguments: Arguments) async throws -> String {
        let callContext = await agentStartToolTelemetry(toolID: toolID, toolSessionID: toolSessionID, arguments: arguments)
        guard let device = await agentToolDevice(arguments.deviceID, in: registry),
              device.capabilities.contains(arguments.capability) else {
            return await recordOutput(#"{"error":"capability unavailable"}"#, callContext: callContext)
        }

        let modes = HomeCapabilityRegistry.definitions[arguments.capability]?.enumValues ?? device.supportedModes
        return await recordOutput(AgentToolFormatting.array(modes), callContext: callContext)
    }

    private func recordOutput(_ output: String, callContext: ToolTelemetryCallContext) async -> String {
        await agentFinishToolTelemetry(
            output: output,
            outputSizeStore: outputSizeStore,
            callContext: callContext
        )
    }
}
