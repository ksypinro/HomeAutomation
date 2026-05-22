import Foundation
import FoundationModels
import HomeAutomationCore

public struct AgentGetCapabilitiesTool: Tool {
    public let name = "getDeviceCapabilities"
    public let description = "Lists capabilities and commands for a device ID."
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
    }

    public func call(arguments: Arguments) async throws -> String {
        let startedAt = await agentStartToolTelemetry(toolName: name, arguments: arguments)
        guard let device = await agentToolDevice(arguments.deviceID, in: registry) else {
            return await recordOutput(#"{"error":"device unavailable"}"#, startedAt: startedAt)
        }

        let payload: [[String: String]] = device.capabilities.map { capability in
            let definition = HomeCapabilityRegistry.definitions[capability]
            let attributes = definition?.attributeNames.joined(separator: ",") ?? ""
            let enumValues = definition?.enumValues.prefix(12).joined(separator: ",") ?? ""
            let numericRange: String
            if let range = definition?.numericRange {
                numericRange = "\(range.lowerBound)...\(range.upperBound)"
            } else {
                numericRange = ""
            }
            let risk = definition.map { String(describing: $0.riskLevel) } ?? ""

            return [
                "capability": capability,
                "commands": device.supportedCommands[capability, default: []].joined(separator: ","),
                "attributes": attributes,
                "enumValues": enumValues,
                "numericRange": numericRange,
                "risk": risk
            ]
        }
        return await recordOutput(AgentToolFormatting.jsonLines(payload), startedAt: startedAt)
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
