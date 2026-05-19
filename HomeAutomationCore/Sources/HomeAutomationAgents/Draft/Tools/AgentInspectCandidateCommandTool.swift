import Foundation
import FoundationModels
import HomeAutomationCore

public struct AgentInspectCandidateCommandTool: Tool {
    public let name = "inspectCandidateCommand"
    public let description = "Inspects a device capability, supported commands, modes, ranges, validation, and risk in one compact lookup."
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

        @Guide(description: "Optional capability to inspect. Omit to list every device capability.")
        public let capability: String?

        @Guide(description: "Optional command to validate for the capability.")
        public let command: String?

        public init(deviceID: String, capability: String? = nil, command: String? = nil) {
            self.deviceID = deviceID
            self.capability = capability
            self.command = command
        }
    }

    public func call(arguments: Arguments) async throws -> String {
        let startedAt = await agentStartToolTelemetry(toolName: name, arguments: arguments)
        guard let device = await agentToolDevice(arguments.deviceID, in: registry) else {
            return await recordOutput(#"{"valid":false,"reason":"device unavailable"}"#, startedAt: startedAt)
        }

        let inspectedCapabilities = arguments.capability.map { [$0] } ?? device.capabilities
        let payload: [[String: String]] = inspectedCapabilities.map { capability in
            let definition = HomeCapabilityRegistry.definitions[capability]
            let supportedCommands = device.supportedCommands[capability, default: []]
            let command = arguments.command ?? ""
            let capabilityValid = device.capabilities.contains(capability)
            let commandValid = command.isEmpty || command == "getStatus" || supportedCommands.contains(command)
            let modes = (definition?.enumValues ?? device.supportedModes).prefix(20).joined(separator: ",")
            let numericRange = definition?.numericRange.map { "\($0.lowerBound)...\($0.upperBound)" } ?? ""
            let risk = definition.map { String(describing: $0.riskLevel) } ?? String(describing: device.riskLevel)

            return [
                "deviceID": device.id,
                "capability": capability,
                "supported": String(capabilityValid && commandValid),
                "reason": validationReason(capabilityValid: capabilityValid, commandValid: commandValid, commandProvided: !command.isEmpty),
                "commands": supportedCommands.joined(separator: ","),
                "attributes": definition?.attributeNames.joined(separator: ",") ?? "",
                "modes": modes,
                "numericRange": numericRange,
                "risk": risk
            ]
        }

        return await recordOutput(AgentToolFormatting.jsonLines(payload), startedAt: startedAt)
    }

    private func validationReason(capabilityValid: Bool, commandValid: Bool, commandProvided: Bool) -> String {
        guard capabilityValid else { return "capability unavailable" }
        guard commandProvided else { return "capability available" }
        return commandValid ? "supported" : "command unavailable"
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
