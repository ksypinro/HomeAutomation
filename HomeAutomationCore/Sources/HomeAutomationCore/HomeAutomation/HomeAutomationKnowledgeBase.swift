import Foundation

public struct HomeAutomationKnowledgeBase: Sendable, Codable {
    public let schemaVersion: String
    public let generatedAt: String
    public let sourceNotes: [HomeCatalogSourceNote]
    public let normalizationNotes: [String]
    public let capabilities: [HomeCatalogCapability]
    public let deviceTypes: [HomeCatalogDeviceType]
    public let rooms: [String]

    public static let shared: HomeAutomationKnowledgeBase = loadCatalog()

    public static var instructionSummary: String {
        let catalog = shared
        let deviceTypeSummary = catalog.deviceTypes
            .map { deviceType in
                let aliases = deviceType.aliases.isEmpty ? "" : " aliases=\(deviceType.aliases.joined(separator: "/"))"
                return "\(deviceType.id)(\(deviceType.displayName)\(aliases))"
            }
            .joined(separator: ", ")

        let capabilitySummary = catalog.capabilities
            .map { capability in
                let commands = capability.commands.isEmpty ? "read-only" : capability.commands.joined(separator: "/")
                return "\(capability.id):\(commands)"
            }
            .joined(separator: "; ")

        return """
        Cross-client smart-home catalog is available.
        Normalize device types to these identifiers: \(deviceTypeSummary)
        Normalize capabilities and commands to these identifiers: \(capabilitySummary)
        Use getStatus for read-only state questions.
        Use increaseValue/decreaseValue for relative numeric changes when an exact setter command is not specified.
        """
    }

    public static var supportedDeviceTypeIdentifiers: [String] {
        shared.deviceTypes.map(\.id)
    }

    public static var supportedCapabilityIdentifiers: [String] {
        shared.capabilities.map(\.id)
    }

    public var commandsByCapability: [String: [String]] {
        Dictionary(uniqueKeysWithValues: capabilities.map { ($0.id, $0.commands) })
    }

    public var modesByCapability: [String: [String]] {
        Dictionary(uniqueKeysWithValues: capabilities.map { ($0.id, $0.enumValues) })
    }

    public func capabilityDefinitions() -> [String: HomeCapabilityDefinition] {
        Dictionary(uniqueKeysWithValues: capabilities.map { capability in
            (
                capability.id,
                HomeCapabilityDefinition(
                    id: capability.id,
                    displayName: capability.displayName,
                    commands: capability.commands,
                    attributeNames: capability.attributes,
                    numericRange: capability.numericClosedRange,
                    enumValues: capability.enumValues,
                    riskLevel: capability.risk
                )
            )
        })
    }

    public func makeCatalogDeviceRecords() -> [HomeCandidateRecord] {
        let commandsByCapability = commandsByCapability
        let modesByCapability = modesByCapability

        return deviceTypes.enumerated().map { index, deviceType in
            let room = rooms[index % max(rooms.count, 1)]
            let capabilities = deviceType.allCapabilityIDs
            let supportedCommands = Dictionary(uniqueKeysWithValues: capabilities.map {
                ($0, commandsByCapability[$0] ?? [])
            })
            let supportedModes = Array(Set(capabilities.flatMap { modesByCapability[$0] ?? [] })).sorted()
            let metadata = [
                "catalogDisplayName": deviceType.displayName,
                "aliases": deviceType.aliases.joined(separator: ","),
                "category": deviceType.category,
                "googleDeviceTypes": deviceType.platformMappings.googleDeviceTypes.joined(separator: ","),
                "alexaDisplayCategories": deviceType.platformMappings.alexaDisplayCategories.joined(separator: ",")
            ]

            return HomeCandidateRecord(
                id: "catalog_\(deviceType.id.normalizedHomeIdentifier)",
                type: deviceType.id == "scene" ? .routine : .device,
                displayName: "\(room.capitalized) \(deviceType.displayName)",
                deviceType: deviceType.id,
                room: room,
                capabilities: capabilities,
                supportedCommands: supportedCommands,
                supportedModes: supportedModes,
                currentState: currentState(for: capabilities),
                metadata: metadata,
                riskLevel: maxRisk(for: deviceType, capabilityIDs: capabilities)
            )
        }
    }

    public static func generatedDatasetCommandCount() -> Int {
        HomeGeneratedCommandDataset.shared.count
    }

    public static func generatedDatasetCommands() -> [HomeGeneratedCommandExample] {
        HomeGeneratedCommandDataset.shared.commands
    }

    private static func loadCatalog() -> HomeAutomationKnowledgeBase {
        guard let url = Bundle.module.url(
            forResource: "home_automation_capability_catalog",
            withExtension: "json"
        ),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(HomeAutomationKnowledgeBase.self, from: data)
        else {
            return HomeAutomationKnowledgeBase(
                schemaVersion: "fallback",
                generatedAt: "unknown",
                sourceNotes: [],
                normalizationNotes: [],
                capabilities: [],
                deviceTypes: [],
                rooms: []
            )
        }

        return catalog
    }
}

public struct HomeGeneratedCommandDataset: Sendable, Decodable {
    public let schemaVersion: String
    public let generatedAt: String
    public let count: Int
    public let sourceCatalog: String
    public let commands: [HomeGeneratedCommandExample]

    public static let shared: HomeGeneratedCommandDataset = load()

    private static func load() -> HomeGeneratedCommandDataset {
        guard let url = Bundle.module.url(
            forResource: "home_automation_nl_command_dataset",
            withExtension: "json"
        ),
              let data = try? Data(contentsOf: url),
              let dataset = try? JSONDecoder().decode(HomeGeneratedCommandDataset.self, from: data)
        else {
            return HomeGeneratedCommandDataset(
                schemaVersion: "fallback",
                generatedAt: "unknown",
                count: 0,
                sourceCatalog: "",
                commands: []
            )
        }

        return dataset
    }
}

public struct HomeGeneratedCommandExample: Sendable, Decodable, Identifiable, Hashable {
    public let id: String
    public let text: String
    public let language: String
    public let deviceType: String
    public let deviceName: String
    public let room: String
    public let capability: String
    public let command: String
    public let intent: String
    public let riskLevel: String
    public let parameters: [HomeGeneratedCommandParameter]
    public let expected: HomeGeneratedCommandExpectation

    public var automationIntent: HomeAutomationIntent {
        switch intent {
        case "turnOn": .turnOn
        case "turnOff": .turnOff
        case "increaseValue": .increaseValue
        case "decreaseValue": .decreaseValue
        case "getStatus": .getStatus
        case "start": .start
        case "stop": .stop
        case "pause": .pause
        case "resume": .resume
        case "open": .open
        case "close": .close
        case "lock": .lock
        case "unlock": .unlock
        case "runRoutine": .runRoutine
        default: .setValue
        }
    }

    public var risk: HomeAutomationRiskLevel {
        HomeAutomationRiskLevel.catalogValue(riskLevel)
    }

    public func commandDraft(targetDeviceID: String) -> HomeCommandDraft {
        HomeCommandDraft(
            intent: automationIntent,
            targetDeviceID: targetDeviceID,
            capability: capability,
            command: command,
            parameters: parameters.map(\.resolvedParameter),
            needsClarification: false,
            requiresConfirmation: expected.requiresConfirmation,
            confidence: 1
        )
    }
}

public struct HomeGeneratedCommandParameter: Sendable, Decodable, Hashable {
    public let name: String
    public let value: String?
    public let numericValue: Double?
    public let unit: String?
    public let confidence: Double

    public var resolvedParameter: HomeResolvedParameter {
        HomeResolvedParameter(
            name: name,
            value: value,
            numericValue: numericValue,
            unit: unit,
            confidence: confidence
        )
    }
}

public struct HomeGeneratedCommandExpectation: Sendable, Decodable, Hashable {
    public let domain: String
    public let deviceType: String
    public let targetDescription: String
    public let capability: String
    public let command: String
    public let requiresConfirmation: Bool
}

public struct HomeCatalogSourceNote: Sendable, Codable, Hashable {
    public let client: String
    public let urls: [String]
    public let notes: String
}

public struct HomeCatalogCapability: Sendable, Codable, Hashable {
    public let id: String
    public let displayName: String
    public let commands: [String]
    public let attributes: [String]
    public let valueType: String
    public let numericRange: [Double]?
    public let enumValues: [String]
    public let riskLevel: String
    public let utteranceVerbs: [String]
    public let valueExamples: [String]
    public let platformMappings: HomeCatalogCapabilityPlatformMappings

    public var numericClosedRange: ClosedRange<Double>? {
        guard let numericRange, numericRange.count == 2 else { return nil }
        return numericRange[0]...numericRange[1]
    }

    public var risk: HomeAutomationRiskLevel {
        HomeAutomationRiskLevel.catalogValue(riskLevel)
    }
}

public struct HomeCatalogCapabilityPlatformMappings: Sendable, Codable, Hashable {
    public let smartThingsCapabilities: [String]
    public let homeKitServices: [String]
    public let homeKitCharacteristics: [String]
    public let googleTraits: [String]
    public let alexaInterfaces: [String]
}

public struct HomeCatalogDeviceType: Sendable, Codable, Hashable {
    public let id: String
    public let displayName: String
    public let category: String
    public let aliases: [String]
    public let riskLevel: String
    public let requiredCapabilities: [String]
    public let recommendedCapabilities: [String]
    public let optionalCapabilities: [String]
    public let exampleNames: [String]
    public let platformMappings: HomeCatalogDevicePlatformMappings

    public var allCapabilityIDs: [String] {
        Array(
            OrderedSet(
                requiredCapabilities + recommendedCapabilities + optionalCapabilities
            )
        )
    }

    public var risk: HomeAutomationRiskLevel {
        HomeAutomationRiskLevel.catalogValue(riskLevel)
    }
}

public struct HomeCatalogDevicePlatformMappings: Sendable, Codable, Hashable {
    public let appleHomeKitCategories: [String]
    public let appleHomeKitServices: [String]
    public let smartThingsDeviceTypes: [String]
    public let smartThingsCapabilities: [String]
    public let googleDeviceTypes: [String]
    public let googleTraits: [String]
    public let alexaDisplayCategories: [String]
    public let alexaInterfaces: [String]
}

private func currentState(for capabilityIDs: [String]) -> [String: String] {
    var state: [String: String] = [:]
    for capabilityID in capabilityIDs {
        guard let capability = HomeAutomationKnowledgeBase.shared.capabilities.first(where: { $0.id == capabilityID }) else {
            continue
        }

        for attribute in capability.attributes {
            state[attribute] = defaultValue(for: capability)
        }
    }
    return state
}

private func defaultValue(for capability: HomeCatalogCapability) -> String {
    if capability.commands.contains("getStatus"), capability.commands.count == 1 {
        return capability.enumValues.first ?? "unknown"
    }
    if capability.enumValues.contains("off") {
        return "off"
    }
    if capability.enumValues.contains("closed") {
        return "closed"
    }
    if capability.enumValues.contains("locked") {
        return "locked"
    }
    if capability.enumValues.contains("ready") {
        return "ready"
    }
    if let range = capability.numericClosedRange {
        return String(Int((range.lowerBound + range.upperBound) / 2))
    }
    return capability.enumValues.first ?? "unknown"
}

private func maxRisk(for deviceType: HomeCatalogDeviceType, capabilityIDs: [String]) -> HomeAutomationRiskLevel {
    let risks = [deviceType.risk] + capabilityIDs.compactMap { capabilityID in
        HomeAutomationKnowledgeBase.shared.capabilities.first(where: { $0.id == capabilityID })?.risk
    }
    return risks.maxBySeverity()
}

private struct OrderedSet<Element: Hashable>: Sequence {
    private let values: [Element]

    init(_ rawValues: [Element]) {
        var seen = Set<Element>()
        values = rawValues.filter { seen.insert($0).inserted }
    }

    func makeIterator() -> Array<Element>.Iterator {
        values.makeIterator()
    }
}

private extension HomeAutomationRiskLevel {
    static func catalogValue(_ value: String) -> HomeAutomationRiskLevel {
        switch value {
        case "medium": .medium
        case "high": .high
        case "critical": .critical
        default: .low
        }
    }

    var severity: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .critical: 3
        }
    }
}

private extension [HomeAutomationRiskLevel] {
    func maxBySeverity() -> HomeAutomationRiskLevel {
        self.max { lhs, rhs in
            lhs.severity < rhs.severity
        } ?? .low
    }
}

private extension String {
    var normalizedHomeIdentifier: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }
}
