import Foundation
import FoundationModels
import HomeAutomationCore

public struct AgentFindDevicesTool: Tool {
    public let name = "findDeviceCandidates"
    public let description = "Finds smart-home device candidates by query, room, or device type."
    private let registry: MockHomeDeviceRegistry

    public init(registry: MockHomeDeviceRegistry) {
        self.registry = registry
    }

    @Generable
    public struct Arguments {
        public let query: String
        public let room: String?
        public let deviceType: String?
        public let limit: Int?
    }

    public func call(arguments: Arguments) async throws -> String {
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
            let typeMatches = deviceType.map { device.deviceType.agentNormalizedHomeTokenString == $0 } ?? true
            return queryMatches && roomMatches && typeMatches
        }
        .prefix(limit)

        return AgentToolFormatting.records(Array(matches))
    }
}

public struct AgentGetCapabilitiesTool: Tool {
    public let name = "getDeviceCapabilities"
    public let description = "Lists capabilities and commands for a device ID."
    private let registry: MockHomeDeviceRegistry

    public init(registry: MockHomeDeviceRegistry) {
        self.registry = registry
    }

    @Generable
    public struct Arguments {
        public let deviceID: String
    }

    public func call(arguments: Arguments) async throws -> String {
        guard let device = await device(arguments.deviceID, in: registry) else {
            return #"{"error":"device unavailable"}"#
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
        return AgentToolFormatting.jsonLines(payload)
    }
}

public struct AgentGetDeviceStateTool: Tool {
    public let name = "getCurrentDeviceState"
    public let description = "Reads current state values for a device ID."
    private let registry: MockHomeDeviceRegistry

    public init(registry: MockHomeDeviceRegistry) {
        self.registry = registry
    }

    @Generable
    public struct Arguments {
        public let deviceID: String
    }

    public func call(arguments: Arguments) async throws -> String {
        guard let device = await device(arguments.deviceID, in: registry) else {
            return #"{"error":"device unavailable"}"#
        }
        return AgentToolFormatting.dictionary(device.currentState)
    }
}

public struct AgentGetSupportedModesTool: Tool {
    public let name = "getSupportedModes"
    public let description = "Gets supported enum or mode values for a device capability."
    private let registry: MockHomeDeviceRegistry

    public init(registry: MockHomeDeviceRegistry) {
        self.registry = registry
    }

    @Generable
    public struct Arguments {
        public let deviceID: String
        public let capability: String
    }

    public func call(arguments: Arguments) async throws -> String {
        guard let device = await device(arguments.deviceID, in: registry),
              device.capabilities.contains(arguments.capability) else {
            return #"{"error":"capability unavailable"}"#
        }

        let modes = HomeCapabilityRegistry.definitions[arguments.capability]?.enumValues ?? device.supportedModes
        return AgentToolFormatting.array(modes)
    }
}

public struct AgentValidateCommandTool: Tool {
    public let name = "validateCommand"
    public let description = "Pre-validates whether a device supports a capability command."
    private let registry: MockHomeDeviceRegistry

    public init(registry: MockHomeDeviceRegistry) {
        self.registry = registry
    }

    @Generable
    public struct Arguments {
        public let deviceID: String
        public let capability: String
        public let command: String
    }

    public func call(arguments: Arguments) async throws -> String {
        guard let device = await device(arguments.deviceID, in: registry) else {
            return #"{"valid":false,"reason":"device unavailable"}"#
        }
        guard device.capabilities.contains(arguments.capability) else {
            return #"{"valid":false,"reason":"capability unavailable","supportedCapabilities":"\#(device.capabilities.joined(separator: ","))"}"#
        }
        let supportedCommands = device.supportedCommands[arguments.capability, default: []]
        guard arguments.command == "getStatus" || supportedCommands.contains(arguments.command) else {
            return #"{"valid":false,"reason":"command unavailable","supportedCommands":"\#(supportedCommands.joined(separator: ","))"}"#
        }
        let risk = HomeCapabilityRegistry.riskLevel(for: arguments.capability)
        return #"{"valid":true,"reason":"supported","risk":"\#(risk)"}"#
    }
}

public struct AgentHydrateCandidatesTool: Tool {
    public let name = "hydrateCandidateRecords"
    public let description = "Returns full device records for candidate IDs."
    private let registry: MockHomeDeviceRegistry

    public init(registry: MockHomeDeviceRegistry) {
        self.registry = registry
    }

    @Generable
    public struct Arguments {
        public let candidateIDs: [String]
    }

    public func call(arguments: Arguments) async throws -> String {
        let devices = await registry.allDevices()
        let idSet = Set(arguments.candidateIDs)
        return AgentToolFormatting.records(devices.filter { idSet.contains($0.id) })
    }
}

public struct AgentToolProvider: Sendable {
    private let registry: MockHomeDeviceRegistry

    public init(registry: MockHomeDeviceRegistry) {
        self.registry = registry
    }

    public func tools(for input: HomeFinalResolutionInput) -> [any Tool] {
        var tools: [any Tool] = [
            AgentFindDevicesTool(registry: registry),
            AgentGetCapabilitiesTool(registry: registry),
            AgentValidateCommandTool(registry: registry),
            AgentHydrateCandidatesTool(registry: registry)
        ]

        if input.resolutionState.intent.topFamilies.contains(.temperature) ||
            input.resolutionState.intent.topFamilies.contains(.statusQuery) ||
            input.resolutionState.intent.topFamilies.contains(.brightness) {
            tools.append(AgentGetDeviceStateTool(registry: registry))
        }

        if input.resolutionState.intent.topFamilies.contains(.temperature) ||
            input.resolutionState.intent.topFamilies.contains(.applianceCycle) ||
            input.resolutionState.intent.topFamilies.contains(.media) {
            tools.append(AgentGetSupportedModesTool(registry: registry))
        }

        return tools
    }
}

private func device(_ id: String, in registry: MockHomeDeviceRegistry) async -> HomeCandidateRecord? {
    let devices = await registry.allDevices()
    return devices.first { $0.id == id }
}

enum AgentToolFormatting {
    static func records(_ records: [HomeCandidateRecord]) -> String {
        jsonLines(records.map { record in
            [
                "id": record.id,
                "name": record.displayName,
                "type": record.deviceType,
                "room": record.room ?? "",
                "capabilities": record.capabilities.joined(separator: ","),
                "risk": String(describing: record.riskLevel),
                "state": record.currentState.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",")
            ]
        })
    }

    static func dictionary(_ values: [String: String]) -> String {
        jsonLines([values])
    }

    static func array(_ values: [String]) -> String {
        #"{"values":["# + values.map { #""\#($0)""# }.joined(separator: ",") + "]}"
    }

    static func jsonLines(_ values: [[String: String]]) -> String {
        values.map { dictionary in
            let body = dictionary.keys.sorted().map { key in
                #""\#(escaped(key))":"\#(escaped(dictionary[key] ?? ""))""#
            }
            .joined(separator: ",")
            return "{\(body)}"
        }
        .joined(separator: "\n")
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\"#, with: #"\\"#)
            .replacingOccurrences(of: #"""#, with: #"\""#)
            .replacingOccurrences(of: "\n", with: " ")
    }
}
