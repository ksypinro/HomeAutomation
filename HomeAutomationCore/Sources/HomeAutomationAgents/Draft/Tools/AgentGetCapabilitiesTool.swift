import Foundation
import FoundationModels
import HomeAutomationCore

public struct AgentGetCapabilitiesTool: Tool, ToolRuntimeIdentifiable {
    public let name = "getDeviceCapabilities"
    public var toolID: String { name }
    public let toolSessionID = UUID().uuidString
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
    public struct Arguments: AgentToolTraceArguments {
        @Guide(description: "Device ID from hydrated candidates or tool output.")
        public let deviceID: String

        @Guide(description: "Tracing only: caller agent ID. Pass the value provided in tool trace instructions.")
        public let agentID: String?
        @Guide(description: "Tracing only: caller agent session ID. Pass the value provided in tool trace instructions.")
        public let agentSessionID: String?
        @Guide(description: "Tracing only: caller agent run ID. Pass the value provided in tool trace instructions.")
        public let agentRunID: Int?

        public init(
            deviceID: String,
            agentID: String? = nil,
            agentSessionID: String? = nil,
            agentRunID: Int? = nil
        ) {
            self.deviceID = deviceID
            self.agentID = agentID
            self.agentSessionID = agentSessionID
            self.agentRunID = agentRunID
        }
    }

    public func call(arguments: Arguments) async throws -> String {
        let callContext = await agentStartToolTelemetry(toolID: toolID, toolSessionID: toolSessionID, arguments: arguments)
        guard let device = await agentToolDevice(arguments.deviceID, in: registry) else {
            return await recordOutput(#"{"error":"device unavailable"}"#, callContext: callContext)
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
        return await recordOutput(AgentToolFormatting.jsonLines(payload), callContext: callContext)
    }

    private func recordOutput(_ output: String, callContext: ToolTelemetryCallContext) async -> String {
        await agentFinishToolTelemetry(
            output: output,
            outputSizeStore: outputSizeStore,
            callContext: callContext
        )
    }
}
