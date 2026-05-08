import Foundation
import HomeAutomationCore

/// Private support types for the rule-based fallback resolver.

struct AgentScoredDevice {
    let device: HomeCandidateRecord
    let draftIntent: AgentDraftIntent
    let score: Int
}

struct AgentDraftIntent {
    let intent: HomeAutomationIntent
    let capability: String
    let command: String
    let parameters: [HomeResolvedParameter]
}

struct AgentCapabilityCommand {
    let capability: String
    let command: String
}

struct AgentSemanticHints {
    let preferredDeviceIDs: Set<String>
    let preferredCapabilityIDs: Set<String>
    let preferredCommands: Set<String>

    init(
        preferredDeviceIDs: Set<String> = [],
        preferredCapabilityIDs: Set<String> = [],
        preferredCommands: Set<String> = []
    ) {
        self.preferredDeviceIDs = preferredDeviceIDs
        self.preferredCapabilityIDs = preferredCapabilityIDs
        self.preferredCommands = preferredCommands
    }
}

struct AgentRuleIntent {
    let family: HomeAutomationIntentFamily
    let intent: HomeAutomationIntent
    let capabilityPreferences: [AgentCapabilityCommand]
    let parameters: [HomeResolvedParameter]
    let deviceTypeHints: Set<String>

    init?(normalized: String) {
        let numbers = AgentTextParser.extractedNumbers(from: normalized)
        let firstNumber = numbers.first

        if AgentTextParser.containsAny(normalized, ["movie time", "good night", "routine", "scene"]) {
            self.init(family: .routine, intent: .runRoutine, capabilityPreferences: [.init(capability: "routine", command: "run")], parameters: [], deviceTypeHints: ["routine"])
            return
        }
        if normalized.contains("unlock") || normalized.contains("open the lock") {
            self.init(family: .lockUnlock, intent: .unlock, capabilityPreferences: [.init(capability: "lock", command: "unlock")], parameters: [], deviceTypeHints: ["lock"])
            return
        }
        if normalized.contains("lock") || normalized.contains("secure") {
            self.init(family: .lockUnlock, intent: .lock, capabilityPreferences: [.init(capability: "lock", command: "lock")], parameters: [], deviceTypeHints: ["lock"])
            return
        }
        if AgentTextParser.containsAny(normalized, ["open", "raise"]) &&
            AgentTextParser.containsAny(normalized, ["door", "garage", "blind", "shade", "valve"]) {
            self.init(
                family: .openClose,
                intent: .open,
                capabilityPreferences: [
                    .init(capability: "garageDoorControl", command: "open"),
                    .init(capability: "doorControl", command: "open"),
                    .init(capability: "windowShade", command: "open"),
                    .init(capability: "valve", command: "open")
                ],
                parameters: [],
                deviceTypeHints: ["garage door", "door", "blind", "valve"]
            )
            return
        }
        if AgentTextParser.containsAny(normalized, ["close", "lower"]) &&
            AgentTextParser.containsAny(normalized, ["door", "garage", "blind", "shade", "valve"]) {
            self.init(
                family: .openClose,
                intent: .close,
                capabilityPreferences: [
                    .init(capability: "garageDoorControl", command: "close"),
                    .init(capability: "doorControl", command: "close"),
                    .init(capability: "windowShade", command: "close"),
                    .init(capability: "valve", command: "close")
                ],
                parameters: [],
                deviceTypeHints: ["garage door", "door", "blind", "valve"]
            )
            return
        }
        if AgentTextParser.containsAny(normalized, ["status", "check", "what is", "is the", "tell me", "battery"]) {
            self.init(
                family: .statusQuery,
                intent: .getStatus,
                capabilityPreferences: statusCapabilityPreferences(for: normalized),
                parameters: [],
                deviceTypeHints: Set(AgentTextParser.deviceTypes(for: normalized).map(\.agentNormalizedHomeTokenString))
            )
            return
        }
        if AgentTextParser.containsAny(normalized, ["cooler", "warmer"]) {
            let direction = normalized.contains("cooler") ? -1 : 1
            self.init(
                family: .temperature,
                intent: direction < 0 ? .decreaseValue : .increaseValue,
                capabilityPreferences: [
                    .init(capability: "thermostatCoolingSetpoint", command: "setCoolingSetpoint"),
                    .init(capability: "thermostatHeatingSetpoint", command: "setHeatingSetpoint")
                ],
                parameters: [
                    HomeResolvedParameter(name: "delta", numericValue: Double(firstNumber ?? 1), unit: "degrees", confidence: 0.85)
                ],
                deviceTypeHints: ["air conditioner", "thermostat"]
            )
            return
        }
        if AgentTextParser.containsAny(normalized, ["temperature", "setpoint", "degrees"]) && firstNumber != nil {
            self.init(
                family: .temperature,
                intent: .setValue,
                capabilityPreferences: [
                    .init(capability: "thermostatCoolingSetpoint", command: "setCoolingSetpoint"),
                    .init(capability: "thermostatHeatingSetpoint", command: "setHeatingSetpoint")
                ],
                parameters: [
                    HomeResolvedParameter(name: "value", numericValue: Double(firstNumber ?? 0), unit: "degrees", confidence: 0.85)
                ],
                deviceTypeHints: ["air conditioner", "thermostat"]
            )
            return
        }
        if AgentTextParser.containsAny(normalized, ["brightness", "bright", "dim", "percent", "level"]) && firstNumber != nil {
            let isIncrease = AgentTextParser.containsAny(normalized, ["increase", "raise", "brighter"])
            let isDecrease = AgentTextParser.containsAny(normalized, ["decrease", "lower", "dim"])
            let command = isIncrease ? "increaseValue" : isDecrease ? "decreaseValue" : "setLevel"
            self.init(
                family: .brightness,
                intent: isIncrease ? .increaseValue : isDecrease ? .decreaseValue : .setValue,
                capabilityPreferences: [.init(capability: "switchLevel", command: command)],
                parameters: [
                    HomeResolvedParameter(name: "value", numericValue: Double(firstNumber ?? 0), unit: "percent", confidence: 0.9)
                ],
                deviceTypeHints: ["light"]
            )
            return
        }
        if AgentTextParser.containsAny(normalized, ["turn on", "switch on", "power on"]) {
            self.init(
                family: .power,
                intent: .turnOn,
                capabilityPreferences: [.init(capability: "switch", command: "on")],
                parameters: [],
                deviceTypeHints: Set(AgentTextParser.deviceTypes(for: normalized).map(\.agentNormalizedHomeTokenString))
            )
            return
        }
        if AgentTextParser.containsAny(normalized, ["turn off", "switch off", "power off"]) {
            self.init(
                family: .power,
                intent: .turnOff,
                capabilityPreferences: [.init(capability: "switch", command: "off")],
                parameters: [],
                deviceTypeHints: Set(AgentTextParser.deviceTypes(for: normalized).map(\.agentNormalizedHomeTokenString))
            )
            return
        }

        return nil
    }

    private init(
        family: HomeAutomationIntentFamily,
        intent: HomeAutomationIntent,
        capabilityPreferences: [AgentCapabilityCommand],
        parameters: [HomeResolvedParameter],
        deviceTypeHints: Set<String>
    ) {
        self.family = family
        self.intent = intent
        self.capabilityPreferences = capabilityPreferences
        self.parameters = parameters
        self.deviceTypeHints = deviceTypeHints
    }

    func makeDraftIntent(for device: HomeCandidateRecord) -> AgentDraftIntent? {
        guard let preference = capabilityPreferences.first(where: { device.capabilities.contains($0.capability) }) else {
            return nil
        }
        return AgentDraftIntent(
            intent: intent,
            capability: preference.capability,
            command: preference.command,
            parameters: parameters
        )
    }
}

private func statusCapabilityPreferences(for normalized: String) -> [AgentCapabilityCommand] {
    if normalized.contains("battery") {
        return [AgentCapabilityCommand(capability: "battery", command: "getStatus")]
    }
    if AgentTextParser.containsAny(normalized, ["temperature", "hot", "cold"]) {
        return [AgentCapabilityCommand(capability: "temperatureMeasurement", command: "getStatus")]
    }
    if normalized.contains("humidity") {
        return [AgentCapabilityCommand(capability: "relativeHumidityMeasurement", command: "getStatus")]
    }
    if AgentTextParser.containsAny(normalized, ["open", "closed", "door"]) {
        return [
            AgentCapabilityCommand(capability: "contactSensor", command: "getStatus"),
            AgentCapabilityCommand(capability: "garageDoorControl", command: "getStatus"),
            AgentCapabilityCommand(capability: "lock", command: "getStatus")
        ]
    }
    return [
        AgentCapabilityCommand(capability: "temperatureMeasurement", command: "getStatus"),
        AgentCapabilityCommand(capability: "contactSensor", command: "getStatus"),
        AgentCapabilityCommand(capability: "motionSensor", command: "getStatus"),
        AgentCapabilityCommand(capability: "switch", command: "getStatus"),
        AgentCapabilityCommand(capability: "battery", command: "getStatus")
    ]
}
