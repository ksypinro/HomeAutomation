import Foundation
import FoundationModels
import HomeAutomationCore

public struct AgentGetSupportedModesTool: Tool {
    public let name = "getSupportedModes"
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
    public struct Arguments {
        @Guide(description: "Device ID from hydrated candidates or tool output.")
        public let deviceID: String
        @Guide(description: "Capability name from canonical registry context.")
        public let capability: String
    }

    public func call(arguments: Arguments) async throws -> String {
        let startedAt = await agentStartToolTelemetry(toolName: name, arguments: arguments)
        guard let device = await agentToolDevice(arguments.deviceID, in: registry),
              device.capabilities.contains(arguments.capability) else {
            return await recordOutput(#"{"error":"capability unavailable"}"#, startedAt: startedAt)
        }

        let modes = HomeCapabilityRegistry.definitions[arguments.capability]?.enumValues ?? device.supportedModes
        return await recordOutput(AgentToolFormatting.array(modes), startedAt: startedAt)
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
