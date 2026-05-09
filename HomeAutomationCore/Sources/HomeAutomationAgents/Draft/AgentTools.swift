import Foundation
import FoundationModels
import HomeAutomationCore

public final class AgentToolOutputSizeStore: @unchecked Sendable {
    public static let shared = AgentToolOutputSizeStore()

    private let lock = NSLock()
    private var maxCharacterCountsByTool: [String: Int] = [:]

    public init() {}

    public func record(toolName: String, characterCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        maxCharacterCountsByTool[toolName] = max(maxCharacterCountsByTool[toolName] ?? 0, characterCount)
    }

    public func estimate(toolName: String, fallback: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return max(maxCharacterCountsByTool[toolName] ?? 0, fallback)
    }
}

public struct AgentFindDevicesTool: Tool {
    public let name = "findDeviceCandidates"
    public let description = "Finds smart-home device candidates by query, room, or device type."
    private let registry: MockHomeDeviceRegistry
    private let outputSizeStore: AgentToolOutputSizeStore

    public init(
        registry: MockHomeDeviceRegistry,
        outputSizeStore: AgentToolOutputSizeStore = AgentToolOutputSizeStore()
    ) {
        self.registry = registry
        self.outputSizeStore = outputSizeStore
    }

    @Generable
    public struct Arguments {
        @Guide(description: "Search terms from the user command.")
        public let query: String
        @Guide(description: "Room or location name when known.")
        public let room: String?
        @Guide(description: "Internal device type when known.")
        public let deviceType: String?
        @Guide(description: "Maximum records to return, from 1 to 25.", .range(1...25))
        public let limit: Int?

        public init(query: String, room: String? = nil, deviceType: String? = nil, limit: Int? = nil) {
            self.query = query
            self.room = room
            self.deviceType = deviceType
            self.limit = limit
        }
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

        return recordOutput(AgentToolFormatting.records(Array(matches)))
    }

    private func recordOutput(_ output: String) -> String {
        outputSizeStore.record(toolName: name, characterCount: output.count)
        return output
    }
}

public struct AgentGetCapabilitiesTool: Tool {
    public let name = "getDeviceCapabilities"
    public let description = "Lists capabilities and commands for a device ID."
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
    }

    public func call(arguments: Arguments) async throws -> String {
        guard let device = await device(arguments.deviceID, in: registry) else {
            return recordOutput(#"{"error":"device unavailable"}"#)
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
        return recordOutput(AgentToolFormatting.jsonLines(payload))
    }

    private func recordOutput(_ output: String) -> String {
        outputSizeStore.record(toolName: name, characterCount: output.count)
        return output
    }
}

public struct AgentGetDeviceStateTool: Tool {
    public let name = "getCurrentDeviceState"
    public let description = "Reads current state values for a device ID."
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
    }

    public func call(arguments: Arguments) async throws -> String {
        guard let device = await device(arguments.deviceID, in: registry) else {
            return recordOutput(#"{"error":"device unavailable"}"#)
        }
        return recordOutput(AgentToolFormatting.dictionary(device.currentState))
    }

    private func recordOutput(_ output: String) -> String {
        outputSizeStore.record(toolName: name, characterCount: output.count)
        return output
    }
}

public struct AgentGetSupportedModesTool: Tool {
    public let name = "getSupportedModes"
    public let description = "Gets supported enum or mode values for a device capability."
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
        @Guide(description: "Capability name from canonical registry context.")
        public let capability: String
    }

    public func call(arguments: Arguments) async throws -> String {
        guard let device = await device(arguments.deviceID, in: registry),
              device.capabilities.contains(arguments.capability) else {
            return recordOutput(#"{"error":"capability unavailable"}"#)
        }

        let modes = HomeCapabilityRegistry.definitions[arguments.capability]?.enumValues ?? device.supportedModes
        return recordOutput(AgentToolFormatting.array(modes))
    }

    private func recordOutput(_ output: String) -> String {
        outputSizeStore.record(toolName: name, characterCount: output.count)
        return output
    }
}

public struct AgentValidateCommandTool: Tool {
    public let name = "validateCommand"
    public let description = "Pre-validates whether a device supports a capability command."
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
        @Guide(description: "Capability name from canonical registry context.")
        public let capability: String
        @Guide(description: "Command name to validate for the capability.")
        public let command: String
    }

    public func call(arguments: Arguments) async throws -> String {
        guard let device = await device(arguments.deviceID, in: registry) else {
            return recordOutput(#"{"valid":false,"reason":"device unavailable"}"#)
        }
        guard device.capabilities.contains(arguments.capability) else {
            return recordOutput(#"{"valid":false,"reason":"capability unavailable","supportedCapabilities":"\#(device.capabilities.joined(separator: ","))"}"#)
        }
        let supportedCommands = device.supportedCommands[arguments.capability, default: []]
        guard arguments.command == "getStatus" || supportedCommands.contains(arguments.command) else {
            return recordOutput(#"{"valid":false,"reason":"command unavailable","supportedCommands":"\#(supportedCommands.joined(separator: ","))"}"#)
        }
        let risk = HomeCapabilityRegistry.riskLevel(for: arguments.capability)
        return recordOutput(#"{"valid":true,"reason":"supported","risk":"\#(risk)"}"#)
    }

    private func recordOutput(_ output: String) -> String {
        outputSizeStore.record(toolName: name, characterCount: output.count)
        return output
    }
}

public struct AgentHydrateCandidatesTool: Tool {
    public let name = "hydrateCandidateRecords"
    public let description = "Returns full device records for candidate IDs."
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
        @Guide(description: "Candidate IDs selected from provided candidates only.", .maximumCount(25))
        public let candidateIDs: [String]
    }

    public func call(arguments: Arguments) async throws -> String {
        let devices = await registry.allDevices()
        let idSet = Set(arguments.candidateIDs)
        return recordOutput(AgentToolFormatting.records(devices.filter { idSet.contains($0.id) }))
    }

    private func recordOutput(_ output: String) -> String {
        outputSizeStore.record(toolName: name, characterCount: output.count)
        return output
    }
}

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
        guard let device = await device(arguments.deviceID, in: registry) else {
            return recordOutput(#"{"valid":false,"reason":"device unavailable"}"#)
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

        return recordOutput(AgentToolFormatting.jsonLines(payload))
    }

    private func validationReason(capabilityValid: Bool, commandValid: Bool, commandProvided: Bool) -> String {
        guard capabilityValid else { return "capability unavailable" }
        guard commandProvided else { return "capability available" }
        return commandValid ? "supported" : "command unavailable"
    }

    private func recordOutput(_ output: String) -> String {
        outputSizeStore.record(toolName: name, characterCount: output.count)
        return output
    }
}

public struct AgentToolProvider: Sendable {
    private let registry: MockHomeDeviceRegistry
    private let outputSizeStore: AgentToolOutputSizeStore

    public init(
        registry: MockHomeDeviceRegistry,
        outputSizeStore: AgentToolOutputSizeStore = .shared
    ) {
        self.registry = registry
        self.outputSizeStore = outputSizeStore
    }

    public func tools(for input: HomeFinalResolutionInput) -> [any Tool] {
        var tools: [any Tool] = [
            AgentFindDevicesTool(registry: registry, outputSizeStore: outputSizeStore),
            AgentInspectCandidateCommandTool(registry: registry, outputSizeStore: outputSizeStore),
            AgentHydrateCandidatesTool(registry: registry, outputSizeStore: outputSizeStore)
        ]

        if input.resolutionState.intent.topFamilies.contains(.temperature) ||
            input.resolutionState.intent.topFamilies.contains(.statusQuery) ||
            input.resolutionState.intent.topFamilies.contains(.brightness) {
            tools.append(AgentGetDeviceStateTool(registry: registry, outputSizeStore: outputSizeStore))
        }

        return tools
    }

    public func estimatedOutputCharacters(for tools: [any Tool], candidateCount: Int) -> Int {
        tools.reduce(0) { total, tool in
            total + outputSizeStore.estimate(
                toolName: tool.name,
                fallback: fallbackOutputEstimate(toolName: tool.name, candidateCount: candidateCount)
            )
        }
    }

    private func fallbackOutputEstimate(toolName: String, candidateCount: Int) -> Int {
        switch toolName {
        case "findDeviceCandidates":
            return min(candidateCount, 10) * 120
        case "hydrateCandidateRecords":
            return min(candidateCount, 5) * 160
        case "inspectCandidateCommand":
            return 600
        case "getCurrentDeviceState":
            return 300
        default:
            return 512
        }
    }
}

private func device(_ id: String, in registry: MockHomeDeviceRegistry) async -> HomeCandidateRecord? {
    let devices = await registry.allDevices()
    return devices.first { $0.id == id }
}

enum AgentToolFormatting {
    static let maxOutputCharacters = 4_000

    static func records(_ records: [HomeCandidateRecord]) -> String {
        jsonLines(records.prefix(25).map { record in
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
        capped(#"{"values":["# + values.prefix(20).map { #""\#($0)""# }.joined(separator: ",") + "]}")
    }

    static func jsonLines(_ values: [[String: String]]) -> String {
        capped(values.map { dictionary in
            let body = dictionary.keys.sorted().map { key in
                #""\#(escaped(key))":"\#(escaped(dictionary[key] ?? ""))""#
            }
            .joined(separator: ",")
            return "{\(body)}"
        }
        .joined(separator: "\n"))
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\"#, with: #"\\"#)
            .replacingOccurrences(of: #"""#, with: #"\""#)
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func capped(_ value: String) -> String {
        guard value.count > maxOutputCharacters else { return value }
        return String(value.prefix(maxOutputCharacters))
    }
}
