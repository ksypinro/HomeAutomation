import Foundation

public struct HomeCapabilityDefinition: Identifiable, Sendable, Hashable, Codable {
    public let id: String
    public let displayName: String
    public let commands: [String]
    public let attributeNames: [String]
    public let numericRange: ClosedRange<Double>?
    public let enumValues: [String]
    public let riskLevel: HomeAutomationRiskLevel

    public init(
        id: String,
        displayName: String,
        commands: [String] = [],
        attributeNames: [String] = [],
        numericRange: ClosedRange<Double>? = nil,
        enumValues: [String] = [],
        riskLevel: HomeAutomationRiskLevel = .low
    ) {
        self.id = id
        self.displayName = displayName
        self.commands = commands
        self.attributeNames = attributeNames
        self.numericRange = numericRange
        self.enumValues = enumValues
        self.riskLevel = riskLevel
    }
}

public enum HomeCapabilityRegistry {
    public static let definitions: [String: HomeCapabilityDefinition] = {
        let items: [HomeCapabilityDefinition] = [
            HomeCapabilityDefinition(
                id: "switch",
                displayName: "Switch",
                commands: ["on", "off"],
                attributeNames: ["switch"],
                enumValues: ["on", "off"]
            ),
            HomeCapabilityDefinition(
                id: "switchLevel",
                displayName: "Switch Level",
                commands: ["setLevel"],
                attributeNames: ["level"],
                numericRange: 0...100
            ),
            HomeCapabilityDefinition(
                id: "colorControl",
                displayName: "Color Control",
                commands: ["setColor", "setHue", "setSaturation"],
                attributeNames: ["color", "hue", "saturation"],
                numericRange: 0...100
            ),
            HomeCapabilityDefinition(
                id: "colorTemperature",
                displayName: "Color Temperature",
                commands: ["setColorTemperature"],
                attributeNames: ["colorTemperature"],
                numericRange: 2600...9000,
                enumValues: ["K"]
            ),
            HomeCapabilityDefinition(
                id: "lock",
                displayName: "Lock",
                commands: ["lock", "unlock"],
                attributeNames: ["lock"],
                enumValues: ["locked", "unlocked", "jammed"],
                riskLevel: .high
            ),
            HomeCapabilityDefinition(
                id: "lockCodes",
                displayName: "Lock Codes",
                commands: ["setCode", "deleteCode", "reloadAllCodes", "requestCode"],
                attributeNames: ["codeReport", "lockCodes"],
                riskLevel: .high
            ),
            HomeCapabilityDefinition(
                id: "thermostatMode",
                displayName: "Thermostat Mode",
                commands: ["setThermostatMode"],
                attributeNames: ["thermostatMode"],
                enumValues: ["off", "heat", "cool", "auto", "eco"],
                riskLevel: .medium
            ),
            HomeCapabilityDefinition(
                id: "thermostatFanMode",
                displayName: "Thermostat Fan Mode",
                commands: ["setThermostatFanMode"],
                attributeNames: ["thermostatFanMode"],
                enumValues: ["auto", "circulate", "followschedule", "on"],
                riskLevel: .medium
            ),
            HomeCapabilityDefinition(
                id: "thermostatCoolingSetpoint",
                displayName: "Thermostat Cooling Setpoint",
                commands: ["setCoolingSetpoint"],
                attributeNames: ["coolingSetpoint"],
                numericRange: 16...30,
                riskLevel: .medium
            ),
            HomeCapabilityDefinition(
                id: "thermostatHeatingSetpoint",
                displayName: "Thermostat Heating Setpoint",
                commands: ["setHeatingSetpoint"],
                attributeNames: ["heatingSetpoint"],
                numericRange: 10...30,
                riskLevel: .medium
            ),
            HomeCapabilityDefinition(
                id: "airConditionerMode",
                displayName: "Air Conditioner Mode",
                commands: ["setAirConditionerMode"],
                attributeNames: ["airConditionerMode"],
                enumValues: ["auto", "cool", "dry", "fanOnly", "heat"],
                riskLevel: .medium
            ),
            HomeCapabilityDefinition(
                id: "airConditionerFanMode",
                displayName: "Air Conditioner Fan Mode",
                commands: ["setFanMode"],
                attributeNames: ["fanMode"],
                enumValues: ["auto", "low", "medium", "high", "turbo"],
                riskLevel: .medium
            ),
            HomeCapabilityDefinition(
                id: "temperatureMeasurement",
                displayName: "Temperature Measurement",
                attributeNames: ["temperature"]
            ),
            HomeCapabilityDefinition(
                id: "relativeHumidityMeasurement",
                displayName: "Relative Humidity Measurement",
                attributeNames: ["humidity"]
            ),
            HomeCapabilityDefinition(
                id: "windowShade",
                displayName: "Window Shade",
                commands: ["open", "close", "pause"],
                attributeNames: ["windowShade"],
                enumValues: ["open", "closed", "partially open", "opening", "closing"],
                riskLevel: .medium
            ),
            HomeCapabilityDefinition(
                id: "windowShadeLevel",
                displayName: "Window Shade Level",
                commands: ["setShadeLevel"],
                attributeNames: ["shadeLevel"],
                numericRange: 0...100,
                riskLevel: .medium
            ),
            HomeCapabilityDefinition(
                id: "doorControl",
                displayName: "Door Control",
                commands: ["open", "close"],
                attributeNames: ["door"],
                enumValues: ["open", "closed", "opening", "closing", "unknown"],
                riskLevel: .high
            ),
            HomeCapabilityDefinition(
                id: "garageDoorControl",
                displayName: "Garage Door Control",
                commands: ["open", "close"],
                attributeNames: ["door"],
                enumValues: ["open", "closed", "opening", "closing", "unknown"],
                riskLevel: .high
            ),
            HomeCapabilityDefinition(
                id: "contactSensor",
                displayName: "Contact Sensor",
                attributeNames: ["contact"],
                enumValues: ["open", "closed"]
            ),
            HomeCapabilityDefinition(
                id: "motionSensor",
                displayName: "Motion Sensor",
                attributeNames: ["motion"],
                enumValues: ["active", "inactive"]
            ),
            HomeCapabilityDefinition(
                id: "presenceSensor",
                displayName: "Presence Sensor",
                attributeNames: ["presence"],
                enumValues: ["present", "not present"]
            ),
            HomeCapabilityDefinition(
                id: "button",
                displayName: "Button",
                attributeNames: ["button"],
                enumValues: ["pushed", "held", "double"]
            ),
            HomeCapabilityDefinition(
                id: "battery",
                displayName: "Battery",
                attributeNames: ["battery"],
                numericRange: 0...100
            ),
            HomeCapabilityDefinition(
                id: "powerMeter",
                displayName: "Power Meter",
                attributeNames: ["power"]
            ),
            HomeCapabilityDefinition(
                id: "energyMeter",
                displayName: "Energy Meter",
                attributeNames: ["energy"]
            ),
            HomeCapabilityDefinition(
                id: "refresh",
                displayName: "Refresh",
                commands: ["refresh"]
            ),
            HomeCapabilityDefinition(
                id: "healthCheck",
                displayName: "Health Check",
                attributeNames: ["healthStatus"],
                enumValues: ["online", "offline"]
            ),
            HomeCapabilityDefinition(
                id: "audioVolume",
                displayName: "Audio Volume",
                commands: ["setVolume", "volumeUp", "volumeDown", "mute", "unmute"],
                attributeNames: ["volume", "mute"],
                numericRange: 0...100
            ),
            HomeCapabilityDefinition(
                id: "mediaPlayback",
                displayName: "Media Playback",
                commands: ["play", "pause", "stop", "fastForward", "rewind"],
                attributeNames: ["playbackStatus"],
                enumValues: ["playing", "paused", "stopped"]
            ),
            HomeCapabilityDefinition(
                id: "mediaInputSource",
                displayName: "Media Input Source",
                commands: ["setInputSource"],
                attributeNames: ["inputSource"],
                enumValues: ["HDMI1", "HDMI2", "TV", "USB", "AV"]
            ),
            HomeCapabilityDefinition(
                id: "channel",
                displayName: "Channel",
                commands: ["setChannel", "channelUp", "channelDown"],
                attributeNames: ["tvChannel"]
            ),
            HomeCapabilityDefinition(
                id: "washerMode",
                displayName: "Washer Mode",
                commands: ["setWasherMode"],
                attributeNames: ["washerMode"],
                enumValues: ["normal", "quick", "heavyDuty", "delicates", "rinseSpin"],
                riskLevel: .medium
            ),
            HomeCapabilityDefinition(
                id: "washerOperatingState",
                displayName: "Washer Operating State",
                commands: ["start", "pause", "stop"],
                attributeNames: ["machineState", "washerJobState"],
                enumValues: ["ready", "running", "paused", "finished"],
                riskLevel: .medium
            ),
            HomeCapabilityDefinition(
                id: "dryerMode",
                displayName: "Dryer Mode",
                commands: ["setDryerMode"],
                attributeNames: ["dryerMode"],
                enumValues: ["normal", "quickDry", "heavyDuty", "delicates", "airFluff"],
                riskLevel: .medium
            ),
            HomeCapabilityDefinition(
                id: "dryerOperatingState",
                displayName: "Dryer Operating State",
                commands: ["start", "pause", "stop"],
                attributeNames: ["machineState", "dryerJobState"],
                enumValues: ["ready", "running", "paused", "finished"],
                riskLevel: .medium
            ),
            HomeCapabilityDefinition(
                id: "ovenMode",
                displayName: "Oven Mode",
                commands: ["setOvenMode"],
                attributeNames: ["ovenMode"],
                enumValues: ["bake", "broil", "convection", "warming"],
                riskLevel: .high
            ),
            HomeCapabilityDefinition(
                id: "ovenSetpoint",
                displayName: "Oven Setpoint",
                commands: ["setOvenSetpoint"],
                attributeNames: ["ovenSetpoint"],
                numericRange: 75...260,
                riskLevel: .high
            ),
            HomeCapabilityDefinition(
                id: "robotCleanerCleaningMode",
                displayName: "Robot Cleaner Cleaning Mode",
                commands: ["setRobotCleanerCleaningMode"],
                attributeNames: ["robotCleanerCleaningMode"],
                enumValues: ["auto", "part", "repeat", "manual"],
                riskLevel: .medium
            ),
            HomeCapabilityDefinition(
                id: "robotCleanerMovement",
                displayName: "Robot Cleaner Movement",
                commands: ["start", "pause", "stop", "returnToHome"],
                attributeNames: ["robotCleanerMovement"],
                enumValues: ["idle", "cleaning", "paused", "homing"],
                riskLevel: .medium
            ),
            HomeCapabilityDefinition(
                id: "airPurifierFanMode",
                displayName: "Air Purifier Fan Mode",
                commands: ["setAirPurifierFanMode"],
                attributeNames: ["airPurifierFanMode"],
                enumValues: ["auto", "low", "medium", "high", "sleep"]
            ),
            HomeCapabilityDefinition(
                id: "filterStatus",
                displayName: "Filter Status",
                attributeNames: ["filterStatus"],
                enumValues: ["normal", "replace"]
            ),
            HomeCapabilityDefinition(
                id: "airQualitySensor",
                displayName: "Air Quality Sensor",
                attributeNames: ["airQuality"],
                enumValues: ["good", "moderate", "poor", "veryPoor"]
            ),
            HomeCapabilityDefinition(
                id: "carbonDioxideMeasurement",
                displayName: "Carbon Dioxide Measurement",
                attributeNames: ["carbonDioxide"]
            ),
            HomeCapabilityDefinition(
                id: "carbonMonoxideDetector",
                displayName: "Carbon Monoxide Detector",
                attributeNames: ["carbonMonoxide"],
                enumValues: ["clear", "detected", "tested"]
            ),
            HomeCapabilityDefinition(
                id: "smokeDetector",
                displayName: "Smoke Detector",
                attributeNames: ["smoke"],
                enumValues: ["clear", "detected", "tested"]
            ),
            HomeCapabilityDefinition(
                id: "waterSensor",
                displayName: "Water Sensor",
                attributeNames: ["water"],
                enumValues: ["dry", "wet"]
            ),
            HomeCapabilityDefinition(
                id: "videoStream",
                displayName: "Video Stream",
                commands: ["startStream", "stopStream"],
                attributeNames: ["stream"],
                riskLevel: .high
            ),
            HomeCapabilityDefinition(
                id: "imageCapture",
                displayName: "Image Capture",
                commands: ["take"],
                attributeNames: ["image"],
                riskLevel: .high
            ),
            HomeCapabilityDefinition(
                id: "soundDetection",
                displayName: "Sound Detection",
                attributeNames: ["sound"],
                enumValues: ["detected", "notDetected"],
                riskLevel: .medium
            ),
            HomeCapabilityDefinition(
                id: "valve",
                displayName: "Valve",
                commands: ["open", "close"],
                attributeNames: ["valve"],
                enumValues: ["open", "closed"],
                riskLevel: .high
            ),
            HomeCapabilityDefinition(
                id: "mode",
                displayName: "Mode",
                commands: ["setMode"],
                attributeNames: ["mode"]
            ),
            HomeCapabilityDefinition(
                id: "routine",
                displayName: "Routine",
                commands: ["run"],
                attributeNames: ["routineStatus"]
            )
        ]

        func mergedValues(_ first: [String], _ second: [String]) -> [String] {
            var seen = Set<String>()
            return (first + second).filter { seen.insert($0).inserted }
        }

        var definitions = HomeAutomationKnowledgeBase.shared.capabilityDefinitions()
        for item in items {
            if let generated = definitions[item.id] {
                definitions[item.id] = HomeCapabilityDefinition(
                    id: item.id,
                    displayName: item.displayName,
                    commands: mergedValues(item.commands, generated.commands),
                    attributeNames: mergedValues(item.attributeNames, generated.attributeNames),
                    numericRange: item.numericRange ?? generated.numericRange,
                    enumValues: mergedValues(item.enumValues, generated.enumValues),
                    riskLevel: item.riskLevel
                )
            } else {
                definitions[item.id] = item
            }
        }
        return definitions
    }()

    public static func supportedCommands(for capability: String) -> [String] {
        definitions[capability]?.commands ?? []
    }

    public static func riskLevel(for capability: String) -> HomeAutomationRiskLevel {
        definitions[capability]?.riskLevel ?? .low
    }

    public static func supportedCommands(for capabilities: [String]) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: capabilities.map { ($0, supportedCommands(for: $0)) })
    }

    public static func supportedModes(for capabilities: [String]) -> [String] {
        Array(Set(capabilities.flatMap { definitions[$0]?.enumValues ?? [] })).sorted()
    }
}
