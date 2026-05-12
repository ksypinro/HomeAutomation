import Foundation
import HomeAutomationCore

public struct DocumentChunker: Sendable {
    public init() {}

    public func capabilityChunks(
        definitions: [String: HomeCapabilityDefinition] = HomeCapabilityRegistry.definitions
    ) -> [DocumentChunk] {
        definitions
            .keys
            .sorted()
            .compactMap { capabilityID in
                guard let definition = definitions[capabilityID] else { return nil }
                let content = [
                    "Capability \(definition.id)",
                    "Display name \(definition.displayName)",
                    "Commands \(definition.commands.joined(separator: " "))",
                    "Attributes \(definition.attributeNames.joined(separator: " "))",
                    "Enum values \(definition.enumValues.joined(separator: " "))",
                    "Risk \(definition.riskLevel)"
                ].joined(separator: ". ")
                let semanticContent = [
                    definition.id,
                    definition.displayName,
                    definition.commands.joined(separator: " "),
                    definition.attributeNames.joined(separator: " "),
                    definition.enumValues.joined(separator: " ")
                ].joined(separator: " ")
                let relatedDeviceTypes = Self.relatedDeviceTypes(for: definition.id)

                return DocumentChunk(
                    id: "capability:\(definition.id)",
                    content: content,
                    semanticContent: semanticContent,
                    source: .capability,
                    metadata: [
                        "capabilityId": definition.id,
                        "commands": definition.commands.joined(separator: ","),
                        "risk": String(describing: definition.riskLevel),
                        "relatedDeviceTypes": relatedDeviceTypes.joined(separator: ",")
                    ]
                )
            }
    }

    public func deviceChunks(devices: [HomeCandidateRecord]) -> [DocumentChunk] {
        devices.map { device in
            let content = [
                "Device \(device.displayName)",
                "ID \(device.id)",
                "Type \(device.deviceType)",
                "Room \(device.room ?? "none")",
                "Capabilities \(device.capabilities.joined(separator: " "))",
                "Commands \(device.supportedCommands.map { "\($0.key) \($0.value.joined(separator: " "))" }.joined(separator: " "))",
                "Modes \(device.supportedModes.joined(separator: " "))",
                "State \(device.currentState.map { "\($0.key) \($0.value)" }.joined(separator: " "))",
                "Risk \(device.riskLevel)"
            ].joined(separator: ". ")
            let semanticContent = [
                device.displayName,
                device.deviceType,
                device.room ?? "",
                device.capabilities.joined(separator: " "),
                device.metadata["nickname"] ?? "",
                device.metadata["aliases"] ?? "",
                device.metadata["description"] ?? ""
            ].joined(separator: " ")

            return DocumentChunk(
                id: "device:\(device.id)",
                content: content,
                semanticContent: semanticContent,
                source: .device,
                metadata: [
                    "deviceId": device.id,
                    "room": device.room ?? "",
                    "deviceType": device.deviceType,
                    "capabilities": device.capabilities.joined(separator: ",")
                ]
            )
        }
    }

    public func bixbyCommandChunks(
        commands: [HomeBixbyVoiceCommand] = HomeBixbyCommandCatalog.commands
    ) -> [DocumentChunk] {
        commands.map { command in
            let content = [
                "Bixby command \(command.capabilityAction)",
                "Capability \(command.capability)",
                "Action \(command.action)",
                "Method \(command.method)",
                "Access \(command.accessLevel)",
                "Hint \(command.hint)"
            ].joined(separator: ". ")
            let semanticContent = [
                command.capabilityAction,
                command.capability,
                command.action,
                command.method,
                command.hint
            ].joined(separator: " ")
            let relatedDeviceTypes = Self.relatedDeviceTypes(for: command.capability)

            return DocumentChunk(
                id: "bixby:\(stableID(command.id))",
                content: content,
                semanticContent: semanticContent,
                source: .bixbyCommand,
                metadata: [
                    "capability": command.capability,
                    "action": command.action,
                    "method": command.method,
                    "relatedDeviceTypes": relatedDeviceTypes.joined(separator: ",")
                ]
            )
        }
    }

    public func nlDatasetChunks(
        examples: [HomeGeneratedCommandExample] = HomeAutomationKnowledgeBase.generatedDatasetCommands()
    ) -> [DocumentChunk] {
        examples.map { example in
            let content = [
                "Natural language example \(example.text)",
                "Language \(example.language)",
                "Device type \(example.deviceType)",
                "Device name \(example.deviceName)",
                "Room \(example.room)",
                "Capability \(example.capability)",
                "Command \(example.command)",
                "Intent \(example.intent)",
                "Risk \(example.riskLevel)"
            ].joined(separator: ". ")

            return DocumentChunk(
                id: "nl:\(example.id)",
                content: content,
                semanticContent: example.text,
                source: .nlDataset,
                metadata: [
                    "exampleId": example.id,
                    "language": example.language,
                    "deviceType": example.deviceType,
                    "capability": example.capability,
                    "command": example.command
                ]
            )
        }
    }

    public func allChunks(devices: [HomeCandidateRecord]) -> [DocumentChunk] {
        capabilityChunks() +
            deviceChunks(devices: devices) +
            bixbyCommandChunks() +
            nlDatasetChunks()
    }

    private func stableID(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func relatedDeviceTypes(for capabilityID: String) -> [String] {
        capabilityDeviceTypes()[capabilityID] ?? []
    }

    private static func capabilityDeviceTypes() -> [String: [String]] {
        var mapping: [String: Set<String>] = [:]
        let devices = MockHomeDeviceRegistry.defaultDevices + HomeAutomationKnowledgeBase.shared.makeCatalogDeviceRecords()
        for device in devices {
            for capability in device.capabilities {
                mapping[capability, default: []].insert(device.deviceType)
            }
        }
        return mapping.mapValues { $0.sorted() }
    }
}
