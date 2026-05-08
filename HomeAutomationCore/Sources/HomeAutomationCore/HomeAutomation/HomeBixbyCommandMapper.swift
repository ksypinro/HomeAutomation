import Foundation

public struct HomeBixbyLinkedVoiceIntentPair: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let capability: String
    public let component: String?
    public let sourceCapability: String
    public let action: String
    public let enumeration: String?
    public let method: String
    public let accessLevel: String
    public let capabilityType: String?
    public let description: String
    public let hints: [String]

    public init(
        id: String,
        capability: String,
        component: String? = nil,
        sourceCapability: String,
        action: String,
        enumeration: String? = nil,
        method: String,
        accessLevel: String,
        capabilityType: String? = nil,
        description: String,
        hints: [String]
    ) {
        self.id = id
        self.capability = capability
        self.component = component
        self.sourceCapability = sourceCapability
        self.action = action
        self.enumeration = enumeration
        self.method = method
        self.accessLevel = accessLevel
        self.capabilityType = capabilityType
        self.description = description
        self.hints = hints
    }
}

public struct HomeBixbyCommandMapper: Sendable {
    public init() {}

    public func makeDraft(
        from pair: HomeBixbyLinkedVoiceIntentPair,
        targetDeviceID: String,
        confidence: Double = 1
    ) -> HomeCommandDraft {
        let command = appCommand(for: pair)
        return HomeCommandDraft(
            intent: intent(for: pair),
            targetDeviceID: targetDeviceID,
            capability: pair.capability,
            command: command,
            parameters: parameters(for: pair),
            needsClarification: false,
            requiresConfirmation: false,
            confidence: confidence
        )
    }

    public func makeDraft(
        for utterance: String,
        pairs: [HomeBixbyLinkedVoiceIntentPair],
        targetDeviceID: String,
        confidence: Double = 1
    ) -> HomeCommandDraft? {
        let normalizedUtterance = normalize(utterance)
        guard let pair = pairs.first(where: { pair in
            pair.hints.contains { normalize(render($0)) == normalizedUtterance }
        }) else {
            return nil
        }

        return makeDraft(from: pair, targetDeviceID: targetDeviceID, confidence: confidence)
    }

    public func appCommand(for pair: HomeBixbyLinkedVoiceIntentPair) -> String {
        pair.action
    }

    private func intent(for pair: HomeBixbyLinkedVoiceIntentPair) -> HomeAutomationIntent {
        let action = pair.action.normalizedHomeTokenString

        if pair.method.uppercased() == "GET" || action.hasPrefix("get") || action == "show" || action == "list" {
            return .getStatus
        }
        if action.contains("turnon") { return .turnOn }
        if action.contains("turnoff") { return .turnOff }
        if action.contains("increase") { return .increaseValue }
        if action.contains("decrease") { return .decreaseValue }
        if action.contains("open") { return .open }
        if action.contains("close") { return .close }
        if action.contains("lock") && action.contains("unlock") { return .unlock }
        if action == "lock" || action.contains("lock") { return .lock }
        if action.contains("start") || action == "play" || action == "launch" || action == "dispense" { return .start }
        if action.contains("stop") || action == "cancel" || action == "exit" { return .stop }
        if action.contains("pause") { return .pause }
        if action.contains("resume") { return .resume }
        if action.hasPrefix("set") || action == "press" || action == "beep" { return .setValue }

        return .setValue
    }

    private func parameters(for pair: HomeBixbyLinkedVoiceIntentPair) -> [HomeResolvedParameter] {
        if let enumeration = pair.enumeration {
            let value = enumParameterValue(for: pair, fallback: enumeration)
            return [
                HomeResolvedParameter(
                    name: "value",
                    value: value,
                    confidence: 1
                )
            ]
        }

        if requiresEnumValue(command: pair.action),
           let enumValue = HomeCapabilityRegistry.definitions[pair.capability]?.enumValues.first {
            return [
                HomeResolvedParameter(
                    name: "value",
                    value: enumValue,
                    confidence: 1
                )
            ]
        }

        if requiresNumericValue(command: pair.action),
           let numericRange = HomeCapabilityRegistry.definitions[pair.capability]?.numericRange {
            return [
                HomeResolvedParameter(
                    name: "value",
                    value: nil,
                    numericValue: (numericRange.lowerBound + numericRange.upperBound) / 2,
                    unit: nil,
                    confidence: 1
                )
            ]
        }

        let hintText = pair.hints.joined(separator: " ")
        if hintText.contains("#{") {
            return [
                HomeResolvedParameter(
                    name: "bixbySlots",
                    value: hintText,
                    confidence: 1
                )
            ]
        }

        return []
    }

    private func enumParameterValue(for pair: HomeBixbyLinkedVoiceIntentPair, fallback: String) -> String {
        guard requiresEnumValue(command: pair.action),
              let enumValues = HomeCapabilityRegistry.definitions[pair.capability]?.enumValues,
              !enumValues.isEmpty else {
            return fallback
        }

        let normalizedFallback = fallback.normalizedHomeTokenString
        return enumValues.first { $0.normalizedHomeTokenString == normalizedFallback } ?? enumValues[0]
    }

    private func requiresEnumValue(command: String) -> Bool {
        [
            "setFanMode",
            "setThermostatFanMode",
            "setThermostatMode",
            "setAirConditionerMode",
            "setAirPurifierFanMode",
            "setInputSource",
            "setWasherMode",
            "setDryerMode",
            "setOvenMode",
            "setRobotCleanerCleaningMode",
            "setMode"
        ].contains(command)
    }

    private func requiresNumericValue(command: String) -> Bool {
        [
            "setLevel",
            "setColorTemperature",
            "setHue",
            "setSaturation",
            "setCoolingSetpoint",
            "setHeatingSetpoint",
            "setShadeLevel",
            "setVolume",
            "setChannel",
            "setOvenSetpoint"
        ].contains(command)
    }

    private func render(_ hint: String) -> String {
        hint
            .replacingOccurrences(of: "#{Device}", with: "test device")
            .replacingOccurrences(of: "#{device}", with: "test device")
            .replacingOccurrences(of: "#{Location}", with: "living room")
            .replacingOccurrences(of: "#{location}", with: "living room")
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
