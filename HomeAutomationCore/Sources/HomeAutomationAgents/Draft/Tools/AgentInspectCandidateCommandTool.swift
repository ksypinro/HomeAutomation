import Foundation
import FoundationModels
import HomeAutomationCore

public struct AgentInspectCandidateCommandTool: Tool, ToolRuntimeIdentifiable {
    public let name = "inspectCandidateCommand"
    public var toolID: String { name }
    public let toolSessionID = UUID().uuidString
    public let description = "Inspects a device capability, supported commands, modes, ranges, validation, and risk in one compact lookup."
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

        @Guide(description: "Optional capability to inspect. Omit to list every device capability.")
        public let capability: String?

        @Guide(description: "Optional command to validate for the capability.")
        public let command: String?
        @Guide(description: "Tracing only: caller agent ID. Pass the value provided in tool trace instructions.")
        public let agentID: String?
        @Guide(description: "Tracing only: caller agent session ID. Pass the value provided in tool trace instructions.")
        public let agentSessionID: String?
        @Guide(description: "Tracing only: caller agent run ID. Pass the value provided in tool trace instructions.")
        public let agentRunID: Int?

        public init(
            deviceID: String,
            capability: String? = nil,
            command: String? = nil,
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

        return await recordOutput(AgentToolFormatting.jsonLines(payload), callContext: callContext)
    }

    private func validationReason(capabilityValid: Bool, commandValid: Bool, commandProvided: Bool) -> String {
        guard capabilityValid else { return "capability unavailable" }
        guard commandProvided else { return "capability available" }
        return commandValid ? "supported" : "command unavailable"
    }

    private func recordOutput(_ output: String, callContext: ToolTelemetryCallContext) async -> String {
        await agentFinishToolTelemetry(
            output: output,
            outputSizeStore: outputSizeStore,
            callContext: callContext
        )
    }
}
