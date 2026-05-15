import Foundation

public actor MockHomeDeviceRegistry {
    private var devices: [HomeCandidateRecord]

    public init(devices: [HomeCandidateRecord] = MockHomeDeviceRegistry.defaultDevices) {
        self.devices = devices
    }

    public func allDevices() -> [HomeCandidateRecord] {
        devices
    }

    public func retrieveCandidates(
        text: String,
        hints: HomeResolutionState,
        limit: Int = 80
    ) -> [HomeCandidateRecord] {
        let query = text.normalizedHomeTokenString
        let hintedRooms = Set(hints.slots.rooms.map(\.normalizedHomeTokenString))
        let hintedTypes = Set(hints.deviceType.deviceTypes.map(\.normalizedHomeTokenString))
        let hintedNicknames = Set(hints.slots.deviceNicknames.map(\.normalizedHomeTokenString))
        let hintedFamilies = Set(hints.intent.topFamilies)

        let scored = devices.map { device in
            (
                device: device,
                score: score(
                    device,
                    query: query,
                    hintedRooms: hintedRooms,
                    hintedTypes: hintedTypes,
                    hintedNicknames: hintedNicknames,
                    hintedFamilies: hintedFamilies
                )
            )
        }

        let positiveMatches = scored
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.device.displayName < rhs.device.displayName
                }
                return lhs.score > rhs.score
            }
            .map(\.device)

        if !positiveMatches.isEmpty {
            return Array(positiveMatches.prefix(limit))
        }

        return Array(devices.prefix(limit))
    }

    public func executeLowRiskPlan(_ plan: HomeAutomationExecutionPlan) throws -> HomeCandidateRecord {
        guard let originalStep = plan.steps.last(where: { $0.type == "command" }) ?? plan.steps.first else {
            throw FoundationLabCoreError.invalidRequest("Missing execution step")
        }

        guard let index = devices.firstIndex(where: { $0.id == originalStep.deviceID }) else {
            throw FoundationLabCoreError.invalidRequest("Device does not exist")
        }

        var updated = devices[index]
        let step = HomeAutomationExecutionStep(
            id: originalStep.id,
            type: originalStep.type,
            deviceID: originalStep.deviceID,
            deviceName: originalStep.deviceName,
            capability: originalStep.capability,
            command: originalStep.command,
            value: try resolvedValue(for: originalStep, device: updated),
            attribute: originalStep.attribute,
            valueFormula: originalStep.valueFormula
        )

        switch step.command {
        case "getStatus":
            break
        case "on":
            updated.currentState["switch"] = "on"
        case "off":
            updated.currentState["switch"] = "off"
        case "increaseValue":
            if let attribute = primaryAttribute(for: step.capability),
               let value = step.value,
               let delta = Int(value) {
                updated.currentState[attribute] = adjustedNumericString(updated.currentState[attribute], delta: delta, range: 0...100)
            }
        case "decreaseValue":
            if let attribute = primaryAttribute(for: step.capability),
               let value = step.value,
               let delta = Int(value) {
                updated.currentState[attribute] = adjustedNumericString(updated.currentState[attribute], delta: -delta, range: 0...100)
            }
        case "setLevel":
            if let value = step.value {
                updated.currentState["level"] = value
            }
        case "setColorTemperature":
            if let value = step.value {
                updated.currentState["colorTemperature"] = value
            }
        case "setHue":
            if let value = step.value {
                updated.currentState["hue"] = value
            }
        case "setSaturation":
            if let value = step.value {
                updated.currentState["saturation"] = value
            }
        case "setColor":
            if let value = step.value {
                updated.currentState["color"] = value
            }
        case "setCoolingSetpoint":
            if let value = step.value {
                updated.currentState["coolingSetpoint"] = value
            }
        case "setHeatingSetpoint":
            if let value = step.value {
                updated.currentState["heatingSetpoint"] = value
            }
        case "setThermostatMode":
            if let value = step.value {
                updated.currentState["thermostatMode"] = value
            }
        case "setThermostatFanMode":
            if let value = step.value {
                updated.currentState["thermostatFanMode"] = value
            }
        case "setAirConditionerMode":
            if let value = step.value {
                updated.currentState["airConditionerMode"] = value
            }
        case "setFanMode":
            if let value = step.value {
                updated.currentState["fanMode"] = value
            }
        case "setMode", "setCookMode", "setToggle", "setRotation", "setDuration", "setTimer",
             "setCode", "deleteCode", "requestCode":
            if let attribute = primaryAttribute(for: step.capability) {
                updated.currentState[attribute] = step.value ?? step.command
            }
        case "arm":
            updated.currentState["securitySystem"] = step.value ?? "armedAway"
        case "disarm":
            updated.currentState["securitySystem"] = "disarmed"
        case "open":
            updated.currentState[step.capability] = "open"
        case "close":
            updated.currentState[step.capability] = "closed"
        case "pause":
            updated.currentState[step.capability] = "paused"
        case "setShadeLevel":
            if let value = step.value {
                updated.currentState["shadeLevel"] = value
            }
        case "setVolume":
            if let value = step.value {
                updated.currentState["volume"] = value
            }
        case "volumeUp":
            updated.currentState["volume"] = adjustedNumericString(updated.currentState["volume"], delta: 5, range: 0...100)
        case "volumeDown":
            updated.currentState["volume"] = adjustedNumericString(updated.currentState["volume"], delta: -5, range: 0...100)
        case "mute":
            updated.currentState["mute"] = "true"
        case "unmute":
            updated.currentState["mute"] = "false"
        case "play":
            updated.currentState["playbackStatus"] = "playing"
        case "stop":
            updated.currentState["playbackStatus"] = "stopped"
            updated.currentState["machineState"] = "stopped"
            updated.currentState["robotCleanerMovement"] = "idle"
        case "start":
            updated.currentState["machineState"] = "running"
            updated.currentState["robotCleanerMovement"] = "cleaning"
        case "setInputSource":
            if let value = step.value {
                updated.currentState["inputSource"] = value
            }
        case "launchApp":
            if let value = step.value {
                updated.currentState["app"] = value
            }
        case "setChannel":
            if let value = step.value {
                updated.currentState["tvChannel"] = value
            }
        case "channelUp":
            updated.currentState["tvChannel"] = adjustedNumericString(updated.currentState["tvChannel"], delta: 1, range: 1...999)
        case "channelDown":
            updated.currentState["tvChannel"] = adjustedNumericString(updated.currentState["tvChannel"], delta: -1, range: 1...999)
        case "setWasherMode":
            if let value = step.value {
                updated.currentState["washerMode"] = value
            }
        case "setDryerMode":
            if let value = step.value {
                updated.currentState["dryerMode"] = value
            }
        case "setRobotCleanerCleaningMode":
            if let value = step.value {
                updated.currentState["robotCleanerCleaningMode"] = value
            }
        case "returnToHome":
            updated.currentState["robotCleanerMovement"] = "homing"
        case "setAirPurifierFanMode":
            if let value = step.value {
                updated.currentState["airPurifierFanMode"] = value
            }
        case "run":
            updated.currentState["routineStatus"] = "lastRun"
        case "fill":
            updated.currentState["fillLevel"] = step.value ?? "100"
        case "drain":
            updated.currentState["fillLevel"] = "0"
        case "dispense":
            updated.currentState["dispensedAmount"] = step.value ?? "dispensed"
        case "locate":
            updated.currentState["locator"] = "locating"
        case "press":
            updated.currentState["button"] = step.value ?? "pressed"
        case "reboot":
            updated.currentState["rebootStatus"] = "rebooting"
        case "installUpdate":
            updated.currentState["softwareUpdate"] = "installing"
        default:
            updated.currentState[step.capability] = step.value ?? step.command
        }

        devices[index] = updated
        return updated
    }

    private func adjustedNumericString(
        _ value: String?,
        delta: Int,
        range: ClosedRange<Int>
    ) -> String {
        let current = Int(value ?? "") ?? range.lowerBound
        return String(min(max(current + delta, range.lowerBound), range.upperBound))
    }

    private func primaryAttribute(for capability: String) -> String? {
        HomeCapabilityRegistry.definitions[capability]?.attributeNames.first ?? capability
    }

    private func resolvedValue(
        for step: HomeAutomationExecutionStep,
        device: HomeCandidateRecord
    ) throws -> String? {
        guard let formula = step.valueFormula?.trimmingCharacters(in: .whitespacesAndNewlines),
              !formula.isEmpty else {
            return step.value
        }

        let parts = formula.split(separator: " ").map(String.init)
        guard parts.count == 3,
              parts[0] == "current",
              parts[1] == "+" || parts[1] == "-",
              let delta = Double(parts[2]) else {
            throw FoundationLabCoreError.invalidRequest("Unsupported value formula")
        }

        guard let attribute = step.attribute ?? primaryAttribute(for: step.capability),
              let currentValue = device.currentState[attribute],
              let current = Double(currentValue) else {
            throw FoundationLabCoreError.invalidRequest("Unable to resolve current value for formula")
        }

        let resolved = parts[1] == "+" ? current + delta : current - delta
        if resolved.rounded() == resolved {
            return String(Int(resolved))
        }
        return String(resolved)
    }

    private func score(
        _ device: HomeCandidateRecord,
        query: String,
        hintedRooms: Set<String>,
        hintedTypes: Set<String>,
        hintedNicknames: Set<String>,
        hintedFamilies: Set<HomeAutomationIntentFamily>
    ) -> Int {
        var total = 0
        let name = device.displayName.normalizedHomeTokenString
        let room = device.room?.normalizedHomeTokenString
        let type = device.deviceType.normalizedHomeTokenString
        let capabilities = device.capabilities.map(\.normalizedHomeTokenString)
        let aliases = device.metadata["aliases"]?
            .split(separator: ",")
            .map { String($0).normalizedHomeTokenString } ?? []

        if query.contains(name) { total += 8 }
        if query.contains(type) { total += 5 }
        if let room, query.contains(room) { total += 5 }
        for alias in aliases where !alias.isEmpty && query.contains(alias) {
            total += 4
        }
        if hintedTypes.contains(type) { total += 4 }
        if let room, hintedRooms.contains(room) { total += 4 }
        if hintedNicknames.contains(name) { total += 4 }

        for capability in capabilities where query.contains(capability) {
            total += 2
        }

        if hintedFamilies.contains(.power), device.capabilities.contains("switch") {
            total += 2
        }
        if hintedFamilies.contains(.brightness), device.capabilities.contains("switchLevel") {
            total += 3
        }
        if hintedFamilies.contains(.temperature),
           device.capabilities.contains("thermostatCoolingSetpoint") ||
           device.capabilities.contains("thermostatHeatingSetpoint") ||
           device.capabilities.contains("thermostatMode") ||
           device.capabilities.contains("airConditionerFanMode") ||
           device.capabilities.contains("temperatureMeasurement") {
            total += 3
        }
        if hintedFamilies.contains(.media),
           device.capabilities.contains("mediaPlayback") ||
           device.capabilities.contains("audioVolume") ||
           device.capabilities.contains("channel") {
            total += 3
        }
        if hintedFamilies.contains(.applianceCycle),
           device.capabilities.contains("washerOperatingState") ||
           device.capabilities.contains("dryerOperatingState") ||
           device.capabilities.contains("robotCleanerMovement") ||
           device.capabilities.contains("ovenMode") {
            total += 3
        }
        if hintedFamilies.contains(.statusQuery),
           device.capabilities.contains("contactSensor") ||
           device.capabilities.contains("motionSensor") ||
           device.capabilities.contains("temperatureMeasurement") ||
           device.capabilities.contains("airQualitySensor") {
            total += 2
        }
        if hintedFamilies.contains(.lockUnlock),
           device.capabilities.contains("lock") {
            total += 4
        }
        if hintedFamilies.contains(.openClose),
           device.capabilities.contains("doorControl") ||
           device.capabilities.contains("garageDoorControl") ||
           device.capabilities.contains("windowShade") ||
           device.capabilities.contains("valve") {
            total += 4
        }

        return total
    }
}

public extension MockHomeDeviceRegistry {
    static let defaultDevices: [HomeCandidateRecord] = [
        makeDevice(
            id: "living_room_ceiling_light",
            displayName: "Living Room Ceiling Light",
            deviceType: "light",
            room: "living room",
            capabilities: ["switch", "switchLevel", "colorControl", "colorTemperature", "powerMeter", "energyMeter"],
            currentState: ["switch": "off", "level": "60", "colorTemperature": "3000", "power": "0", "energy": "12.4"],
            metadata: ["brand": "Nanoleaf", "nickname": "main light", "worksWith": "SmartThings"]
        ),
        makeDevice(
            id: "bedroom_lamp",
            displayName: "Bedroom Lamp",
            deviceType: "light",
            room: "bedroom",
            capabilities: ["switch", "switchLevel", "colorTemperature", "battery"],
            currentState: ["switch": "on", "level": "35", "colorTemperature": "2700", "battery": "88"],
            metadata: ["brand": "Eve", "nickname": "lamp"]
        ),
        makeDevice(
            id: "kitchen_strip_light",
            displayName: "Kitchen Strip Light",
            deviceType: "light",
            room: "kitchen",
            capabilities: ["switch", "switchLevel", "colorControl", "colorTemperature"],
            currentState: ["switch": "off", "level": "100", "hue": "18", "saturation": "80"]
        ),
        makeDevice(
            id: "porch_light",
            displayName: "Porch Light",
            deviceType: "light",
            room: "porch",
            capabilities: ["switch", "switchLevel", "motionSensor"],
            currentState: ["switch": "off", "level": "75", "motion": "inactive"],
            metadata: ["location": "outside"]
        ),
        makeDevice(
            id: "bedroom_ac",
            displayName: "Bedroom AC",
            deviceType: "airConditioner",
            room: "bedroom",
            capabilities: [
                "switch",
                "temperatureMeasurement",
                "relativeHumidityMeasurement",
                "thermostatCoolingSetpoint",
                "airConditionerMode",
                "airConditionerFanMode",
                "powerMeter",
                "energyMeter",
                "filterStatus"
            ],
            currentState: [
                "switch": "on",
                "temperature": "25",
                "humidity": "55",
                "coolingSetpoint": "24",
                "airConditionerMode": "cool",
                "fanMode": "auto",
                "filterStatus": "normal"
            ],
            riskLevel: .medium
        ),
        makeDevice(
            id: "bedroom_temperature_sensor",
            displayName: "Temperature Sensor",
            deviceType: "temperatureSensor",
            room: "bedroom",
            capabilities: ["temperatureMeasurement", "battery"],
            currentState: ["temperature": "25", "battery": "93"],
            metadata: ["aliases": "temperature sensor,temp sensor,room temperature sensor"]
        ),
        makeDevice(
            id: "hallway_thermostat",
            displayName: "Hallway Thermostat",
            deviceType: "thermostat",
            room: "hallway",
            capabilities: [
                "temperatureMeasurement",
                "relativeHumidityMeasurement",
                "thermostatMode",
                "thermostatFanMode",
                "thermostatHeatingSetpoint",
                "thermostatCoolingSetpoint",
                "battery"
            ],
            currentState: [
                "temperature": "22",
                "humidity": "48",
                "thermostatMode": "auto",
                "thermostatFanMode": "auto",
                "heatingSetpoint": "20",
                "coolingSetpoint": "25",
                "battery": "91"
            ],
            riskLevel: .medium
        ),
        makeDevice(
            id: "front_door_lock",
            displayName: "Front Door Lock",
            deviceType: "lock",
            room: "entry",
            capabilities: ["lock", "lockCodes", "battery", "tamperAlert", "contactSensor"],
            currentState: ["lock": "locked", "battery": "72", "contact": "closed", "tamper": "clear"],
            metadata: ["brand": "Nuki"],
            riskLevel: .high
        ),
        makeDevice(
            id: "garage_door",
            displayName: "Garage Door",
            deviceType: "garageDoor",
            room: "garage",
            capabilities: ["garageDoorControl", "contactSensor", "motionSensor", "battery"],
            currentState: ["door": "closed", "contact": "closed", "motion": "inactive", "battery": "64"],
            riskLevel: .high
        ),
        makeDevice(
            id: "living_room_blinds",
            displayName: "Living Room Blinds",
            deviceType: "blind",
            room: "living room",
            capabilities: ["windowShade", "windowShadeLevel", "battery"],
            currentState: ["windowShade": "closed", "shadeLevel": "0", "battery": "81"],
            riskLevel: .medium
        ),
        makeDevice(
            id: "patio_valve",
            displayName: "Patio Water Valve",
            deviceType: "valve",
            room: "patio",
            capabilities: ["valve", "waterSensor", "battery"],
            currentState: ["valve": "closed", "water": "dry", "battery": "77"],
            riskLevel: .high
        ),
        makeDevice(
            id: "entry_contact_sensor",
            displayName: "Entry Contact Sensor",
            deviceType: "contactSensor",
            room: "entry",
            capabilities: ["contactSensor", "battery", "temperatureMeasurement"],
            currentState: ["contact": "closed", "battery": "90", "temperature": "21"]
        ),
        makeDevice(
            id: "hallway_motion_sensor",
            displayName: "Hallway Motion Sensor",
            deviceType: "motionSensor",
            room: "hallway",
            capabilities: ["motionSensor", "illuminanceMeasurement", "battery"],
            currentState: ["motion": "inactive", "illuminance": "18", "battery": "86"]
        ),
        makeDevice(
            id: "air_quality_monitor",
            displayName: "Air Quality Monitor",
            deviceType: "airQualityDetector",
            room: "living room",
            capabilities: [
                "airQualitySensor",
                "temperatureMeasurement",
                "relativeHumidityMeasurement",
                "carbonDioxideMeasurement",
                "carbonMonoxideDetector"
            ],
            currentState: ["airQuality": "good", "temperature": "22", "humidity": "45", "carbonDioxide": "620", "carbonMonoxide": "clear"]
        ),
        makeDevice(
            id: "nursery_air_purifier",
            displayName: "Nursery Air Purifier",
            deviceType: "airPurifier",
            room: "nursery",
            capabilities: ["switch", "airPurifierFanMode", "airQualitySensor", "filterStatus", "powerMeter"],
            currentState: ["switch": "on", "airPurifierFanMode": "auto", "airQuality": "moderate", "filterStatus": "normal", "power": "18"]
        ),
        makeDevice(
            id: "living_room_tv",
            displayName: "Living Room TV",
            deviceType: "tv",
            room: "living room",
            capabilities: ["switch", "audioVolume", "mediaPlayback", "mediaInputSource", "channel"],
            currentState: ["switch": "off", "volume": "18", "mute": "false", "playbackStatus": "stopped", "inputSource": "HDMI1", "tvChannel": "5"]
        ),
        makeDevice(
            id: "kitchen_speaker",
            displayName: "Kitchen Speaker",
            deviceType: "speaker",
            room: "kitchen",
            capabilities: ["switch", "audioVolume", "mediaPlayback"],
            currentState: ["switch": "on", "volume": "35", "mute": "false", "playbackStatus": "paused"]
        ),
        makeDevice(
            id: "laundry_washer",
            displayName: "Laundry Washer",
            deviceType: "washer",
            room: "laundry",
            capabilities: ["switch", "washerMode", "washerOperatingState", "powerMeter", "energyMeter"],
            currentState: ["switch": "off", "washerMode": "normal", "machineState": "ready"],
            riskLevel: .medium
        ),
        makeDevice(
            id: "laundry_dryer",
            displayName: "Laundry Dryer",
            deviceType: "dryer",
            room: "laundry",
            capabilities: ["switch", "dryerMode", "dryerOperatingState", "powerMeter", "energyMeter"],
            currentState: ["switch": "off", "dryerMode": "normal", "machineState": "ready"],
            riskLevel: .medium
        ),
        makeDevice(
            id: "kitchen_oven",
            displayName: "Kitchen Oven",
            deviceType: "oven",
            room: "kitchen",
            capabilities: ["ovenMode", "ovenSetpoint", "temperatureMeasurement"],
            currentState: ["ovenMode": "off", "ovenSetpoint": "0", "temperature": "24"],
            riskLevel: .high
        ),
        makeDevice(
            id: "robot_vacuum",
            displayName: "Robot Vacuum",
            deviceType: "robotCleaner",
            room: "home",
            capabilities: ["switch", "robotCleanerCleaningMode", "robotCleanerMovement", "battery"],
            currentState: ["switch": "off", "robotCleanerCleaningMode": "auto", "robotCleanerMovement": "idle", "battery": "96"],
            riskLevel: .medium
        ),
        makeDevice(
            id: "front_porch_camera",
            displayName: "Front Porch Camera",
            deviceType: "camera",
            room: "porch",
            capabilities: ["videoStream", "imageCapture", "motionSensor", "soundDetection", "switch"],
            currentState: ["stream": "idle", "motion": "inactive", "sound": "notDetected", "switch": "on"],
            riskLevel: .high
        ),
        makeDevice(
            id: "basement_water_sensor",
            displayName: "Basement Water Sensor",
            deviceType: "waterSensor",
            room: "basement",
            capabilities: ["waterSensor", "temperatureMeasurement", "battery"],
            currentState: ["water": "dry", "temperature": "18", "battery": "93"]
        ),
        makeDevice(
            id: "smoke_detector",
            displayName: "Hallway Smoke Detector",
            deviceType: "smokeDetector",
            room: "hallway",
            capabilities: ["smokeDetector", "carbonMonoxideDetector", "battery"],
            currentState: ["smoke": "clear", "carbonMonoxide": "clear", "battery": "89"]
        ),
        makeDevice(
            id: "movie_time",
            type: .routine,
            displayName: "Movie Time",
            deviceType: "routine",
            room: "living room",
            capabilities: ["routine"],
            currentState: [:],
            metadata: ["description": "Dims lights, closes blinds, and prepares the TV"]
        ),
        makeDevice(
            id: "good_night",
            type: .routine,
            displayName: "Good Night",
            deviceType: "routine",
            room: "home",
            capabilities: ["routine"],
            currentState: [:],
            metadata: ["description": "Turns off lights, locks doors, lowers thermostat"],
            riskLevel: .high
        )
    ] + HomeAutomationKnowledgeBase.shared.makeCatalogDeviceRecords()

    private static func makeDevice(
        id: String,
        type: HomeCandidateType = .device,
        displayName: String,
        deviceType: String,
        room: String?,
        capabilities: [String],
        currentState: [String: String],
        metadata: [String: String] = [:],
        riskLevel: HomeAutomationRiskLevel? = nil
    ) -> HomeCandidateRecord {
        let derivedRisk = riskLevel ?? capabilities
            .map { HomeCapabilityRegistry.riskLevel(for: $0) }
            .maxBySeverity()

        return HomeCandidateRecord(
            id: id,
            type: type,
            displayName: displayName,
            deviceType: deviceType,
            room: room,
            capabilities: capabilities,
            supportedCommands: HomeCapabilityRegistry.supportedCommands(for: capabilities),
            supportedModes: HomeCapabilityRegistry.supportedModes(for: capabilities),
            currentState: currentState,
            metadata: metadata,
            riskLevel: derivedRisk
        )
    }
}

private extension [HomeAutomationRiskLevel] {
    func maxBySeverity() -> HomeAutomationRiskLevel {
        self.max { lhs, rhs in
            lhs.severity < rhs.severity
        } ?? .low
    }
}

private extension HomeAutomationRiskLevel {
    var severity: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .critical: 3
        }
    }
}

extension String {
    var normalizedHomeTokenString: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}
