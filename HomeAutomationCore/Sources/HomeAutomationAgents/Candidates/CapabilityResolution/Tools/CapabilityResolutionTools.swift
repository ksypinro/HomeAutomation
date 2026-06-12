import Foundation
import FoundationModels
import HomeAutomationCore

public struct CapabilityCandidateDeviceDetailsTool: Tool, ToolRuntimeIdentifiable {
    public let name = "getCapabilityCandidateDeviceDetails"
    public var toolID: String { name }
    public let toolSessionID = UUID().uuidString
    public let description = """
    Returns detailed candidate device records for capability resolution, including \
    ID, name, room, type, capabilities, supported commands, state, aliases, and risk.
    """

    private let candidates: [HomeCandidateRecord]
    private let outputSizeStore: AgentToolOutputSizeStore

    public init(
        candidates: [HomeCandidateRecord],
        outputSizeStore: AgentToolOutputSizeStore = .shared
    ) {
        self.candidates = candidates
        self.outputSizeStore = outputSizeStore
    }

    @Generable
    public struct Arguments: AgentToolTraceArguments {
        @Guide(description: "Candidate device IDs to inspect. Pass an empty list to return all provided candidates.", .maximumCount(25))
        public let candidateIDs: [String]

        @Guide(description: "Tracing only: caller agent ID. Pass the value provided in tool trace instructions.")
        public let agentID: String?
        @Guide(description: "Tracing only: caller agent session ID. Pass the value provided in tool trace instructions.")
        public let agentSessionID: String?
        @Guide(description: "Tracing only: caller agent run ID. Pass the value provided in tool trace instructions.")
        public let agentRunID: Int?

        public init(
            candidateIDs: [String] = [],
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
        let callContext = await agentStartToolTelemetry(
            toolID: toolID,
            toolSessionID: toolSessionID,
            arguments: arguments
        )
        let idSet = Set(arguments.candidateIDs)
        let records = idSet.isEmpty ? candidates : candidates.filter { idSet.contains($0.id) }
        let output = AgentToolFormatting.jsonLines(records.prefix(25).map(Self.payload(for:)))
        return await agentFinishToolTelemetry(
            output: output,
            outputSizeStore: outputSizeStore,
            callContext: callContext
        )
    }

    private static func payload(for record: HomeCandidateRecord) -> [String: String] {
        [
            "id": record.id,
            "name": record.displayName,
            "type": record.deviceType,
            "room": record.room ?? "",
            "capabilities": record.capabilities.joined(separator: ","),
            "supportedCommands": record.supportedCommands
                .keys
                .sorted()
                .map { "\($0)=\(record.supportedCommands[$0, default: []].joined(separator: "|"))" }
                .joined(separator: ";"),
            "supportedModes": record.supportedModes.prefix(30).joined(separator: ","),
            "state": record.currentState.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ","),
            "aliases": record.metadata["aliases"] ?? record.metadata["nickname"] ?? "",
            "risk": String(describing: record.riskLevel)
        ]
    }
}

public struct CapabilityDeviceCapabilitiesTool: Tool, ToolRuntimeIdentifiable {
    public let name = "getCapabilityDeviceCapabilities"
    public var toolID: String { name }
    public let toolSessionID = UUID().uuidString
    public let description = """
    Returns available capabilities for one candidate device, including canonical \
    capability names, supported commands, readable attributes, modes, ranges, and risk.
    """

    private let candidates: [HomeCandidateRecord]
    private let outputSizeStore: AgentToolOutputSizeStore

    public init(
        candidates: [HomeCandidateRecord],
        outputSizeStore: AgentToolOutputSizeStore = .shared
    ) {
        self.candidates = candidates
        self.outputSizeStore = outputSizeStore
    }

    @Generable
    public struct Arguments: AgentToolTraceArguments {
        @Guide(description: "Candidate device ID to inspect.")
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
        let callContext = await agentStartToolTelemetry(
            toolID: toolID,
            toolSessionID: toolSessionID,
            arguments: arguments
        )
        guard let device = candidates.first(where: { $0.id == arguments.deviceID }) else {
            return await agentFinishToolTelemetry(
                output: #"{\"error\":\"device unavailable\"}"#,
                outputSizeStore: outputSizeStore,
                callContext: callContext
            )
        }

        let output = AgentToolFormatting.jsonLines(device.capabilities.map { capability in
            let definition = HomeCapabilityRegistry.definitions[capability]
            let commands = device.supportedCommands[
                capability,
                default: HomeCapabilityRegistry.supportedCommands(for: capability)
            ]
            let numericRange: String
            if let range = definition?.numericRange {
                numericRange = "\(range.lowerBound)...\(range.upperBound)"
            } else {
                numericRange = ""
            }
            return [
                "deviceID": device.id,
                "capability": capability,
                "displayName": definition?.displayName ?? capability,
                "commands": commands.joined(separator: ","),
                "attributes": definition?.attributeNames.joined(separator: ",") ?? "",
                "enumValues": definition?.enumValues.prefix(30).joined(separator: ",") ?? "",
                "deviceModes": device.supportedModes.prefix(30).joined(separator: ","),
                "numericRange": numericRange,
                "risk": String(describing: definition?.riskLevel ?? device.riskLevel)
            ]
        })
        return await agentFinishToolTelemetry(
            output: output,
            outputSizeStore: outputSizeStore,
            callContext: callContext
        )
    }
}

public struct CapabilityAllCapabilitiesTool: Tool, ToolRuntimeIdentifiable {
    public let name = "getAllCapabilities"
    public var toolID: String { name }
    public let toolSessionID = UUID().uuidString
    public let description = """
    Returns capability rows for multiple candidate devices. Use this after \
    inspecting candidate device details to rank the top five likely capabilities \
    before choosing a final device/capability/command triplet.
    """

    private let candidates: [HomeCandidateRecord]
    private let outputSizeStore: AgentToolOutputSizeStore

    public init(
        candidates: [HomeCandidateRecord],
        outputSizeStore: AgentToolOutputSizeStore = .shared
    ) {
        self.candidates = candidates
        self.outputSizeStore = outputSizeStore
    }

    @Generable
    public struct Arguments: AgentToolTraceArguments {
        @Guide(description: "Candidate device IDs to inspect. Pass an empty list to return all provided candidates.", .maximumCount(25))
        public let candidateDeviceIDs: [String]

        @Guide(description: "Tracing only: caller agent ID. Pass the value provided in tool trace instructions.")
        public let agentID: String?
        @Guide(description: "Tracing only: caller agent session ID. Pass the value provided in tool trace instructions.")
        public let agentSessionID: String?
        @Guide(description: "Tracing only: caller agent run ID. Pass the value provided in tool trace instructions.")
        public let agentRunID: Int?

        public init(
            candidateDeviceIDs: [String] = [],
            agentID: String? = nil,
            agentSessionID: String? = nil,
            agentRunID: Int? = nil
        ) {
            self.candidateDeviceIDs = candidateDeviceIDs
            self.agentID = agentID
            self.agentSessionID = agentSessionID
            self.agentRunID = agentRunID
        }
    }

    public func call(arguments: Arguments) async throws -> String {
        let callContext = await agentStartToolTelemetry(
            toolID: toolID,
            toolSessionID: toolSessionID,
            arguments: arguments
        )
        let idSet = Set(arguments.candidateDeviceIDs)
        let records = idSet.isEmpty ? candidates : candidates.filter { idSet.contains($0.id) }
        let rows = records.prefix(25).flatMap(Self.payloadRows(for:))
        let output = AgentToolFormatting.jsonLines(rows)
        return await agentFinishToolTelemetry(
            output: output,
            outputSizeStore: outputSizeStore,
            callContext: callContext
        )
    }

    private static func payloadRows(for device: HomeCandidateRecord) -> [[String: String]] {
        device.capabilities.map { capability in
            let definition = HomeCapabilityRegistry.definitions[capability]
            let commands = device.supportedCommands[
                capability,
                default: HomeCapabilityRegistry.supportedCommands(for: capability)
            ]
            let numericRange: String
            if let range = definition?.numericRange {
                numericRange = "\(range.lowerBound)...\(range.upperBound)"
            } else {
                numericRange = ""
            }
            return [
                "deviceID": device.id,
                "deviceName": device.displayName,
                "deviceType": device.deviceType,
                "room": device.room ?? "",
                "capability": capability,
                "displayName": definition?.displayName ?? capability,
                "commands": commands.joined(separator: ","),
                "attributes": definition?.attributeNames.joined(separator: ",") ?? "",
                "enumValues": definition?.enumValues.prefix(30).joined(separator: ",") ?? "",
                "deviceModes": device.supportedModes.prefix(30).joined(separator: ","),
                "numericRange": numericRange,
                "state": relevantState(for: device, definition: definition),
                "risk": String(describing: definition?.riskLevel ?? device.riskLevel)
            ]
        }
    }

    private static func relevantState(
        for device: HomeCandidateRecord,
        definition: HomeCapabilityDefinition?
    ) -> String {
        let attributes = definition?.attributeNames ?? []
        guard !attributes.isEmpty else { return "" }
        return attributes
            .compactMap { attribute -> String? in
                guard let value = device.currentState[attribute] else { return nil }
                return "\(attribute)=\(value)"
            }
            .joined(separator: ",")
    }
}
