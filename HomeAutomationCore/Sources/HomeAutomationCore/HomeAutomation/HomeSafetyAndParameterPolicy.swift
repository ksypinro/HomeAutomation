import Foundation

public enum HomeRiskPolicy {
    public static func requiresConfirmation(
        intent: HomeAutomationIntent,
        capability: String?,
        deviceType: String,
        candidateRisk: HomeAutomationRiskLevel,
        command: String? = nil
    ) -> Bool {
        if candidateRisk == .high || candidateRisk == .critical {
            return true
        }
        if let capability {
            let capabilityRisk = HomeCapabilityRegistry.riskLevel(for: capability)
            if capabilityRisk == .high || capabilityRisk == .critical {
                return true
            }
        }

        switch intent {
        case .unlock, .open:
            return true
        case .start:
            return ["oven", "stove", "washer", "dryer"].contains(deviceType.normalizedHomeTokenString)
        default:
            return ["unlock", "open", "setCode", "deleteCode", "startStream", "take", "setOvenMode", "setOvenSetpoint"]
                .contains(command ?? "")
        }
    }
}

public enum HomeParameterValidator {
    public static func validate(
        _ parameters: [HomeResolvedParameter],
        capability: String,
        command: String,
        device: HomeCandidateRecord
    ) -> Bool {
        switch command {
        case "on", "off", "lock", "unlock", "open", "close", "run", "refresh", "getStatus",
             "volumeUp", "volumeDown", "mute", "unmute", "play", "pause", "stop",
             "start", "channelUp", "channelDown", "returnToHome", "startStream",
             "stopStream", "take", "fastForward", "rewind", "locate", "reboot", "installUpdate",
             "drain", "fill", "dispense", "press":
            return true
        case "setLevel", "setColorTemperature", "setHue", "setSaturation",
             "setCoolingSetpoint", "setHeatingSetpoint", "setShadeLevel",
             "setVolume", "setChannel", "setOvenSetpoint", "increaseValue",
             "decreaseValue", "setRotation":
            guard let value = firstNumber(in: parameters) else {
                return false
            }
            guard let range = HomeCapabilityRegistry.definitions[capability]?.numericRange else {
                return true
            }
            return range.contains(value)
        case "setColor":
            return !parameters.isEmpty
        case "setFanMode", "setThermostatFanMode", "setThermostatMode",
             "setAirConditionerMode", "setAirPurifierFanMode", "setInputSource",
             "setWasherMode", "setDryerMode", "setOvenMode",
             "setRobotCleanerCleaningMode", "setMode", "setCookMode", "arm", "disarm":
            guard let mode = firstString(in: parameters)?.normalizedHomeTokenString else { return false }
            let allowedValues = HomeCapabilityRegistry.definitions[capability]?.enumValues ?? device.supportedModes
            return allowedValues.isEmpty || allowedValues.contains { allowedValue in
                let normalizedAllowed = allowedValue.normalizedHomeTokenString
                return normalizedAllowed == mode || normalizedAllowed.compactHomeTokenString == mode.compactHomeTokenString
            }
        default:
            return true
        }
    }

    private static func firstNumber(in parameters: [HomeResolvedParameter]) -> Double? {
        parameters.compactMap(\.numericValue).first
    }

    private static func firstString(in parameters: [HomeResolvedParameter]) -> String? {
        parameters.compactMap { $0.value ?? $0.unit }.first
    }
}

private extension String {
    var compactHomeTokenString: String {
        replacingOccurrences(of: " ", with: "")
    }
}
