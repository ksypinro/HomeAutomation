import Foundation
import FoundationModels
import HomeAutomationCore

public struct AgentHydrateCandidatesTool: Tool, ToolRuntimeIdentifiable {
    public let name = "hydrateCandidateRecords"
    public var toolID: String { name }
    public let toolSessionID = UUID().uuidString
    public let description = "Returns full device records for candidate IDs."
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
        @Guide(description: "Candidate IDs selected from provided candidates only.", .maximumCount(25))
        public let candidateIDs: [String]

        @Guide(description: "Tracing only: caller agent ID. Pass the value provided in tool trace instructions.")
        public let agentID: String?
        @Guide(description: "Tracing only: caller agent session ID. Pass the value provided in tool trace instructions.")
        public let agentSessionID: String?
        @Guide(description: "Tracing only: caller agent run ID. Pass the value provided in tool trace instructions.")
        public let agentRunID: Int?

        public init(
            candidateIDs: [String],
            agentID: String? = nil,
            agentSessionID: String? = nil,
            agentRunID: Int? = nil
        ) {
            self.candidateIDs = candidateIDs
            self.agentID = agentID
            self.agentSessionID = agentSessionID
            self.agentRunID = agentRunID
        }
    }

    public func call(arguments: Arguments) async throws -> String {
        let callContext = await agentStartToolTelemetry(toolID: toolID, toolSessionID: toolSessionID, arguments: arguments)
        let devices = await registry.allDevices()
        let idSet = Set(arguments.candidateIDs)
        return await recordOutput(AgentToolFormatting.records(devices.filter { idSet.contains($0.id) }), callContext: callContext)
    }

    private func recordOutput(_ output: String, callContext: ToolTelemetryCallContext) async -> String {
        await agentFinishToolTelemetry(
            output: output,
            outputSizeStore: outputSizeStore,
            callContext: callContext
        )
    }
}
