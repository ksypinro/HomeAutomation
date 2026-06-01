import Foundation
import FoundationModels
import HomeAutomationCore

public struct AgentFindDevicesTool: Tool, ToolRuntimeIdentifiable {
    public let name = "findDeviceCandidates"
    public var toolID: String { name }
    public let toolSessionID = UUID().uuidString
    public let description = "Finds smart-home device candidates by query, room, or device type."
    private let registry: any DeviceRegistryProtocol
    private let outputSizeStore: AgentToolOutputSizeStore

    public init(
        registry: any DeviceRegistryProtocol,
        outputSizeStore: AgentToolOutputSizeStore = AgentToolOutputSizeStore()
    ) {
        self.registry = registry
        self.outputSizeStore = outputSizeStore
    }

    @Generable
    public struct Arguments: AgentToolTraceArguments {
        @Guide(description: "Search terms from the user command.")
        public let query: String
        @Guide(description: "Room or location name when known.")
        public let room: String?
        @Guide(description: "Internal device type when known.")
        public let deviceType: String?
        @Guide(description: "Maximum records to return, from 1 to 25.", .range(1...25))
        public let limit: Int?
        @Guide(description: "Tracing only: caller agent ID. Pass the value provided in tool trace instructions.")
        public let agentID: String?
        @Guide(description: "Tracing only: caller agent session ID. Pass the value provided in tool trace instructions.")
        public let agentSessionID: String?
        @Guide(description: "Tracing only: caller agent run ID. Pass the value provided in tool trace instructions.")
        public let agentRunID: Int?

        public init(
            query: String,
            room: String? = nil,
            deviceType: String? = nil,
            limit: Int? = nil,
            agentID: String? = nil,
            agentSessionID: String? = nil,
            agentRunID: Int? = nil
        ) {
            self.query = query
            self.room = room
            self.deviceType = deviceType
            self.limit = limit
            self.agentID = agentID
            self.agentSessionID = agentSessionID
            self.agentRunID = agentRunID
        }
    }

    public func call(arguments: Arguments) async throws -> String {
        let callContext = await agentStartToolTelemetry(toolID: toolID, toolSessionID: toolSessionID, arguments: arguments)
        let devices = await registry.allDevices()
        let query = arguments.query.agentNormalizedHomeTokenString
        let room = arguments.room?.agentNormalizedHomeTokenString
        let deviceType = arguments.deviceType?.agentNormalizedHomeTokenString
        let limit = max(1, min(arguments.limit ?? 12, 25))

        let matches = devices.filter { device in
            let haystack = [
                device.id,
                device.displayName,
                device.deviceType,
                device.room ?? "",
                device.capabilities.joined(separator: " "),
                device.metadata.values.joined(separator: " ")
            ]
            .joined(separator: " ")
            .agentNormalizedHomeTokenString

            let queryMatches = query.isEmpty || query.split(separator: " ").allSatisfy { haystack.contains($0) }
            let roomMatches = room.map { device.room?.agentNormalizedHomeTokenString == $0 } ?? true
            let typeMatches = deviceType.map { HomeDeviceTypeRelations.areRelated(device.deviceType, $0) } ?? true
            return queryMatches && roomMatches && typeMatches
        }
        .prefix(limit)

        return await recordOutput(AgentToolFormatting.records(Array(matches)), callContext: callContext)
    }

    private func recordOutput(_ output: String, callContext: ToolTelemetryCallContext) async -> String {
        await agentFinishToolTelemetry(
            output: output,
            outputSizeStore: outputSizeStore,
            callContext: callContext
        )
    }
}
