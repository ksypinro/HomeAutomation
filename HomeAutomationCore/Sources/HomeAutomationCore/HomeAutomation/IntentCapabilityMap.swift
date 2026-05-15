import Foundation

public enum IntentCapabilityMap {
    public static func capabilities(for intent: HomeAutomationIntentFamily) -> [String] {
        switch intent {
        case .createAutomation:
            return []
        case .power:
            return ["switch", "button"]
        case .temperature:
            return [
                "temperatureMeasurement",
                "thermostatCoolingSetpoint",
                "thermostatHeatingSetpoint",
                "thermostatMode",
                "thermostatFanMode",
                "airConditionerMode",
                "airConditionerFanMode"
            ]
        case .brightness:
            return ["switchLevel", "colorControl", "colorTemperature", "illuminanceMeasurement"]
        case .media:
            return ["mediaPlayback", "audioVolume", "mediaInputSource", "channel", "videoStream"]
        case .applianceCycle:
            return [
                "washerOperatingState",
                "washerMode",
                "dryerOperatingState",
                "dryerMode",
                "robotCleanerMovement",
                "robotCleanerCleaningMode",
                "ovenMode",
                "ovenSetpoint"
            ]
        case .lockUnlock:
            return ["lock", "lockCodes"]
        case .openClose:
            return ["doorControl", "garageDoorControl", "windowShade", "windowShadeLevel", "valve"]
        case .routine:
            return ["routine"]
        case .statusQuery:
            return []
        case .maintenanceQuery:
            return ["battery", "filterStatus", "softwareUpdate", "tamperAlert"]
        case .unsupported:
            return []
        }
    }

    public static func capabilities(for intents: [HomeAutomationIntentFamily]) -> [String] {
        stableUnique(intents.flatMap(capabilities(for:)))
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !value.isEmpty && !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
