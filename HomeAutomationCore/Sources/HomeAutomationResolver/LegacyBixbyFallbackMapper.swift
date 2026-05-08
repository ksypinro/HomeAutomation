import Foundation
import HomeAutomationCore

public struct LegacyBixbyDraftMatch: Sendable, Hashable {
    public let device: HomeCandidateRecord
    public let draft: HomeCommandDraft
    public let sourceCapability: String
    public let sourceAction: String
    public let score: Int

    public init(
        device: HomeCandidateRecord,
        draft: HomeCommandDraft,
        sourceCapability: String,
        sourceAction: String,
        score: Int
    ) {
        self.device = device
        self.draft = draft
        self.sourceCapability = sourceCapability
        self.sourceAction = sourceAction
        self.score = score
    }
}

public struct LegacyBixbyFallbackMapper: Sendable {
    public init() {}

    public func matches(
        text: String,
        devices: [HomeCandidateRecord]
    ) -> [LegacyBixbyDraftMatch] {
        var bestByKey: [String: LegacyBixbyDraftMatch] = [:]

        for device in devices {
            for name in deviceNames(for: device) {
                let commands = HomeBixbyCommandCatalog.commands(matching: text, deviceName: name)
                for command in commands {
                    guard let draft = makeDraft(from: command, text: text, device: device) else {
                        continue
                    }

                    let score = scoreMatch(text: text, deviceName: name, command: command, device: device)
                    let match = LegacyBixbyDraftMatch(
                        device: device,
                        draft: draft,
                        sourceCapability: command.capability,
                        sourceAction: command.action,
                        score: score
                    )
                    let key = [
                        device.id,
                        draft.capability ?? "none",
                        draft.command ?? "none",
                        String(describing: draft.intent)
                    ].joined(separator: "|")

                    if let existing = bestByKey[key], existing.score >= score {
                        continue
                    }
                    bestByKey[key] = match
                }
            }
        }

        return bestByKey.values.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.device.displayName < rhs.device.displayName
            }
            return lhs.score > rhs.score
        }
    }

    private func makeDraft(
        from command: HomeBixbyVoiceCommand,
        text: String,
        device: HomeCandidateRecord
    ) -> HomeCommandDraft? {
        guard let mapping = mappedCommand(from: command, text: text, device: device) else {
            return nil
        }

        return HomeCommandDraft(
            intent: mapping.intent,
            targetDeviceID: device.id,
            capability: mapping.capability,
            command: mapping.command,
            parameters: mapping.parameters,
            needsClarification: false,
            requiresConfirmation: false,
            confidence: min(0.98, Double(mapping.score) / 36.0)
        )
    }

    private func mappedCommand(
        from command: HomeBixbyVoiceCommand,
        text: String,
        device: HomeCandidateRecord
    ) -> LegacyBixbyCommandMapping? {
        let action = command.action.legacyCompactHomeTokenString
        let sourceCapability = command.capability.legacyCompactHomeTokenString
        let isRead = command.method.uppercased() == "GET" ||
            action.hasPrefix("get") ||
            action == "show" ||
            action == "list"

        if isRead, let capability = statusCapability(for: sourceCapability, device: device) {
            return LegacyBixbyCommandMapping(
                intent: .getStatus,
                capability: capability,
                command: "getStatus",
                parameters: [],
                score: 30
            )
        }

        if action == "turnon" || action == "on" {
            return powerMapping(device: device, command: "on", intent: .turnOn)
        }

        if action == "turnoff" || action == "off" {
            return powerMapping(device: device, command: "off", intent: .turnOff)
        }

        if action.contains("open"), let capability = firstSupported(device, ["garageDoorControl", "doorControl", "windowShade", "valve"]) {
            return LegacyBixbyCommandMapping(intent: .open, capability: capability, command: "open", parameters: [], score: 29)
        }

        if action.contains("close"), let capability = firstSupported(device, ["garageDoorControl", "doorControl", "windowShade", "valve"]) {
            return LegacyBixbyCommandMapping(intent: .close, capability: capability, command: "close", parameters: [], score: 29)
        }

        if action == "unlock", device.capabilities.contains("lock") {
            return LegacyBixbyCommandMapping(intent: .unlock, capability: "lock", command: "unlock", parameters: [], score: 31)
        }

        if action == "lock", device.capabilities.contains("lock") {
            return LegacyBixbyCommandMapping(intent: .lock, capability: "lock", command: "lock", parameters: [], score: 31)
        }

        if ["play", "pause", "stop", "fastforward", "rewind"].contains(action),
           device.capabilities.contains("mediaPlayback") {
            let mappedAction = action == "fastforward" ? "fastForward" : command.action
            let intent: HomeAutomationIntent = action == "play" ? .start :
                action == "pause" ? .pause :
                action == "stop" ? .stop : .setValue
            return LegacyBixbyCommandMapping(intent: intent, capability: "mediaPlayback", command: mappedAction, parameters: [], score: 28)
        }

        if action == "start", let capability = firstSupported(device, ["washerOperatingState", "dryerOperatingState", "robotCleanerMovement"]) {
            return LegacyBixbyCommandMapping(intent: .start, capability: capability, command: "start", parameters: [], score: 27)
        }

        if action == "pause", let capability = firstSupported(device, ["washerOperatingState", "dryerOperatingState", "robotCleanerMovement"]) {
            return LegacyBixbyCommandMapping(intent: .pause, capability: capability, command: "pause", parameters: [], score: 27)
        }

        if action == "stop" || action == "cancel",
           let capability = firstSupported(device, ["washerOperatingState", "dryerOperatingState", "robotCleanerMovement"]) {
            return LegacyBixbyCommandMapping(intent: .stop, capability: capability, command: "stop", parameters: [], score: 27)
        }

        if action.contains("increase"),
           let mapping = relativeNumericMapping(text: text, sourceCapability: sourceCapability, device: device, command: "increaseValue", intent: .increaseValue) {
            return mapping
        }

        if action.contains("decrease"),
           let mapping = relativeNumericMapping(text: text, sourceCapability: sourceCapability, device: device, command: "decreaseValue", intent: .decreaseValue) {
            return mapping
        }

        if action.hasPrefix("set") || action == "setvalue" {
            return setterMapping(text: text, sourceCapability: sourceCapability, device: device)
        }

        if action == "show", let capability = firstSupported(device, ["videoStream", "imageCapture", "switch"]) {
            return LegacyBixbyCommandMapping(intent: .getStatus, capability: capability, command: "getStatus", parameters: [], score: 25)
        }

        return nil
    }

    private func powerMapping(
        device: HomeCandidateRecord,
        command: String,
        intent: HomeAutomationIntent
    ) -> LegacyBixbyCommandMapping? {
        guard device.capabilities.contains("switch") else { return nil }
        return LegacyBixbyCommandMapping(intent: intent, capability: "switch", command: command, parameters: [], score: 30)
    }

    private func setterMapping(
        text: String,
        sourceCapability: String,
        device: HomeCandidateRecord
    ) -> LegacyBixbyCommandMapping? {
        if sourceCapability.contains("brightness"), device.capabilities.contains("switchLevel") {
            return numericMapping(text: text, capability: "switchLevel", command: "setLevel", intent: .setValue, fallbackScore: 28)
        }

        if sourceCapability.contains("colortemperature"), device.capabilities.contains("colorTemperature") {
            return numericMapping(text: text, capability: "colorTemperature", command: "setColorTemperature", intent: .setValue, fallbackScore: 28)
        }

        if sourceCapability.contains("coolingtemperature"), device.capabilities.contains("thermostatCoolingSetpoint") {
            return numericMapping(text: text, capability: "thermostatCoolingSetpoint", command: "setCoolingSetpoint", intent: .setValue, fallbackScore: 28)
        }

        if sourceCapability.contains("heatingtemperature"), device.capabilities.contains("thermostatHeatingSetpoint") {
            return numericMapping(text: text, capability: "thermostatHeatingSetpoint", command: "setHeatingSetpoint", intent: .setValue, fallbackScore: 28)
        }

        if sourceCapability.contains("volume"), device.capabilities.contains("audioVolume") {
            return numericMapping(text: text, capability: "audioVolume", command: "setVolume", intent: .setValue, fallbackScore: 27)
        }

        if sourceCapability.contains("fanmode"), let capability = firstSupported(device, ["airConditionerFanMode", "thermostatFanMode", "airPurifierFanMode"]) {
            let command = capability == "thermostatFanMode" ? "setThermostatFanMode" :
                capability == "airPurifierFanMode" ? "setAirPurifierFanMode" : "setFanMode"
            return enumMapping(text: text, capability: capability, command: command, fallbackScore: 28)
        }

        if sourceCapability.contains("thermostatmode"), device.capabilities.contains("thermostatMode") {
            return enumMapping(text: text, capability: "thermostatMode", command: "setThermostatMode", fallbackScore: 28)
        }

        if sourceCapability.contains("airconditioningmode"), device.capabilities.contains("airConditionerMode") {
            return enumMapping(text: text, capability: "airConditionerMode", command: "setAirConditionerMode", fallbackScore: 28)
        }

        if sourceCapability.contains("inputsource"), device.capabilities.contains("mediaInputSource") {
            return enumMapping(text: text, capability: "mediaInputSource", command: "setInputSource", fallbackScore: 26)
        }

        return nil
    }

    private func relativeNumericMapping(
        text: String,
        sourceCapability: String,
        device: HomeCandidateRecord,
        command: String,
        intent: HomeAutomationIntent
    ) -> LegacyBixbyCommandMapping? {
        let capability: String
        if sourceCapability.contains("brightness"), device.capabilities.contains("switchLevel") {
            capability = "switchLevel"
        } else if sourceCapability.contains("coolingtemperature"), device.capabilities.contains("thermostatCoolingSetpoint") {
            capability = "thermostatCoolingSetpoint"
        } else if sourceCapability.contains("heatingtemperature"), device.capabilities.contains("thermostatHeatingSetpoint") {
            capability = "thermostatHeatingSetpoint"
        } else if sourceCapability.contains("volume"), device.capabilities.contains("audioVolume") {
            capability = "audioVolume"
        } else {
            return nil
        }

        return numericMapping(text: text, capability: capability, command: command, intent: intent, fallbackScore: 27)
    }

    private func numericMapping(
        text: String,
        capability: String,
        command: String,
        intent: HomeAutomationIntent,
        fallbackScore: Int
    ) -> LegacyBixbyCommandMapping? {
        guard let value = LegacyTextParser.extractedNumbers(from: text.legacyNormalizedHomeTokenString).first else {
            return nil
        }
        return LegacyBixbyCommandMapping(
            intent: intent,
            capability: capability,
            command: command,
            parameters: [
                HomeResolvedParameter(
                    name: "value",
                    numericValue: Double(value),
                    unit: unit(for: capability, text: text),
                    confidence: 0.9
                )
            ],
            score: fallbackScore + 2
        )
    }

    private func enumMapping(
        text: String,
        capability: String,
        command: String,
        fallbackScore: Int
    ) -> LegacyBixbyCommandMapping? {
        let normalized = text.legacyNormalizedHomeTokenString
        let allowed = HomeCapabilityRegistry.definitions[capability]?.enumValues ?? []
        let mode = allowed.first { normalized.contains($0.legacyNormalizedHomeTokenString) } ??
            LegacyTextParser.modeCandidates(in: normalized).first
        guard let mode else { return nil }

        return LegacyBixbyCommandMapping(
            intent: .setValue,
            capability: capability,
            command: command,
            parameters: [
                HomeResolvedParameter(name: "value", value: mode, confidence: 0.88)
            ],
            score: fallbackScore + 1
        )
    }

    private func statusCapability(
        for sourceCapability: String,
        device: HomeCandidateRecord
    ) -> String? {
        if device.capabilities.contains(sourceCapability) {
            return sourceCapability
        }

        let preferences: [String]
        if sourceCapability.contains("battery") {
            preferences = ["battery"]
        } else if sourceCapability.contains("temperature") {
            preferences = ["temperatureMeasurement", "thermostatCoolingSetpoint", "thermostatHeatingSetpoint"]
        } else if sourceCapability.contains("humidity") {
            preferences = ["relativeHumidityMeasurement"]
        } else if sourceCapability.contains("contact") || sourceCapability.contains("deviceState") {
            preferences = ["contactSensor", "garageDoorControl", "doorControl", "lock"]
        } else if sourceCapability.contains("motion") {
            preferences = ["motionSensor"]
        } else if sourceCapability.contains("airquality") {
            preferences = ["airQualitySensor", "carbonDioxideMeasurement", "carbonMonoxideDetector"]
        } else if sourceCapability.contains("smoke") {
            preferences = ["smokeDetector"]
        } else if sourceCapability.contains("carbonmonoxide") {
            preferences = ["carbonMonoxideDetector"]
        } else if sourceCapability.contains("water") {
            preferences = ["waterSensor"]
        } else if sourceCapability.contains("volume") {
            preferences = ["audioVolume"]
        } else if sourceCapability.contains("camera") {
            preferences = ["videoStream", "imageCapture", "motionSensor"]
        } else {
            preferences = [sourceCapability, "healthCheck", "switch"]
        }

        return firstSupported(device, preferences) ?? readOnlyCapability(in: device)
    }

    private func firstSupported(
        _ device: HomeCandidateRecord,
        _ capabilities: [String]
    ) -> String? {
        capabilities.first { device.capabilities.contains($0) }
    }

    private func readOnlyCapability(in device: HomeCandidateRecord) -> String? {
        device.capabilities.first { capability in
            guard let definition = HomeCapabilityRegistry.definitions[capability] else { return false }
            return definition.commands.isEmpty && definition.attributeNames.contains { device.currentState[$0] != nil }
        }
    }

    private func deviceNames(for device: HomeCandidateRecord) -> [String] {
        var names = [device.displayName]

        if let nickname = device.metadata["nickname"], !nickname.isEmpty {
            names.append(nickname)
        }

        if let aliases = device.metadata["aliases"] {
            names.append(contentsOf: aliases.split(separator: ",").map { String($0) })
        }

        return names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func scoreMatch(
        text: String,
        deviceName: String,
        command: HomeBixbyVoiceCommand,
        device: HomeCandidateRecord
    ) -> Int {
        let normalized = text.legacyNormalizedHomeTokenString
        var score = 18
        if normalized.contains(deviceName.legacyNormalizedHomeTokenString) {
            score += 10
        }
        if device.capabilities.contains(command.capability) {
            score += 4
        }
        if command.method.uppercased() == "GET" {
            score += 2
        }
        if device.riskLevel == .low {
            score += 1
        }
        return score
    }

    private func unit(for capability: String, text: String) -> String? {
        let normalized = text.legacyNormalizedHomeTokenString
        if normalized.contains("percent") || capability == "switchLevel" || capability == "audioVolume" {
            return "percent"
        }
        if normalized.contains("degree") || capability.contains("Setpoint") {
            return "degrees"
        }
        return nil
    }
}

private struct LegacyBixbyCommandMapping {
    let intent: HomeAutomationIntent
    let capability: String
    let command: String
    let parameters: [HomeResolvedParameter]
    let score: Int
}
