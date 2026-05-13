import Foundation
import HomeAutomationCore

public struct AutomationConditionOperandResolver: Sendable {
    private let registry: MockHomeDeviceRegistry

    public init(registry: MockHomeDeviceRegistry) {
        self.registry = registry
    }

    public func resolve(_ condition: HomeAutomationCondition?) async -> HomeAutomationCondition? {
        guard let condition else { return nil }
        let devices = await registry.allDevices()
        return resolve(condition, devices: devices)
    }

    private func resolve(
        _ condition: HomeAutomationCondition,
        devices: [HomeCandidateRecord]
    ) -> HomeAutomationCondition {
        switch condition {
        case .and(let children):
            return .and(children.map { resolve($0, devices: devices) })
        case .or(let children):
            return .or(children.map { resolve($0, devices: devices) })
        case .not(let child):
            return .not(resolve(child, devices: devices))
        case .comparison(let comparison):
            return .comparison(
                HomeAutomationComparisonCondition(
                    left: resolve(comparison.left, devices: devices, comparison: comparison),
                    operatorName: comparison.operatorName,
                    right: comparison.right,
                    triggerPolicy: comparison.triggerPolicy
                )
            )
        }
    }

    private func resolve(
        _ operand: HomeAutomationConditionOperand,
        devices: [HomeCandidateRecord],
        comparison: HomeAutomationComparisonCondition
    ) -> HomeAutomationConditionOperand {
        guard case .deviceAttribute(let description, let deviceID, let capability, let attribute) = operand,
              deviceID == nil || capability == nil || attribute == nil else {
            return operand
        }

        guard let device = bestDevice(for: description, devices: devices),
              let resolvedCapability = bestCapability(
                for: description,
                device: device,
                comparison: comparison
              ),
              let resolvedAttribute = HomeCapabilityRegistry.definitions[resolvedCapability]?.attributeNames.first else {
            return operand
        }

        return .deviceAttribute(
            description: description,
            deviceID: device.id,
            capability: resolvedCapability,
            attribute: resolvedAttribute
        )
    }

    private func bestDevice(
        for description: String,
        devices: [HomeCandidateRecord]
    ) -> HomeCandidateRecord? {
        let query = normalize(description)
        let scored = devices.map { device in
            (device, score(device, query: query))
        }
        .filter { $0.1 > 0 }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.0.displayName < rhs.0.displayName
            }
            return lhs.1 > rhs.1
        }
        return scored.first?.0
    }

    private func score(_ device: HomeCandidateRecord, query: String) -> Int {
        var total = 0
        let name = normalize(device.displayName)
        let type = normalize(device.deviceType)
        let room = device.room.map(normalize)
        let aliases = device.metadata["aliases"]?
            .split(separator: ",")
            .map { normalize(String($0)) } ?? []
        if query.contains(name) { total += 12 }
        if query.contains(type) { total += 8 }
        if let room, query.contains(room) { total += 5 }
        for alias in aliases where query.contains(alias) {
            total += 6
        }
        if query.contains("window") || query.contains("door") {
            if device.capabilities.contains("contactSensor") { total += 4 }
            if device.capabilities.contains("garageDoorControl") { total += 4 }
            if device.capabilities.contains("doorControl") { total += 4 }
        }
        if query.contains("motion"), device.capabilities.contains("motionSensor") {
            total += 6
        }
        if query.contains("temperature"), device.capabilities.contains("temperatureMeasurement") {
            total += 6
        }
        return total
    }

    private func bestCapability(
        for description: String,
        device: HomeCandidateRecord,
        comparison: HomeAutomationComparisonCondition
    ) -> String? {
        let query = normalize(description)
        if query.contains("motion"), device.capabilities.contains("motionSensor") {
            return "motionSensor"
        }
        if query.contains("temperature"), device.capabilities.contains("temperatureMeasurement") {
            return "temperatureMeasurement"
        }
        if case .literalString(let value) = comparison.right {
            switch value {
            case "open", "closed":
                if device.capabilities.contains("contactSensor") { return "contactSensor" }
                if device.capabilities.contains("garageDoorControl") { return "garageDoorControl" }
                if device.capabilities.contains("doorControl") { return "doorControl" }
                if device.capabilities.contains("windowShade") { return "windowShade" }
            case "on", "off":
                if device.capabilities.contains("switch") { return "switch" }
            case "active", "inactive":
                if device.capabilities.contains("motionSensor") { return "motionSensor" }
            default:
                break
            }
        }
        return device.capabilities.first { capability in
            guard let definition = HomeCapabilityRegistry.definitions[capability] else { return false }
            return definition.commands.isEmpty && !definition.attributeNames.isEmpty
        }
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\s]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
