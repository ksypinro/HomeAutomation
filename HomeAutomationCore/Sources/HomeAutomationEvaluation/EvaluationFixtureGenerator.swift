import Foundation
import HomeAutomationCore

public struct EvaluationFixtureGenerator: Sendable {
    public init() {}

    public func generateFixtures(count: Int) -> [GeneratedEvaluationFixture] {
        guard count > 0 else { return [] }
        let seedFixtures = generateSeedFixtures()
        guard count > seedFixtures.count else {
            return Array(seedFixtures.prefix(count))
        }

        var fixtures = seedFixtures
        var sourceIndex = 0
        while fixtures.count < count {
            let sourceFixture = seedFixtures[sourceIndex % seedFixtures.count]
            let variantNumber = (sourceIndex / seedFixtures.count) + 2
            fixtures.append(variantFixture(
                from: sourceFixture,
                variantNumber: variantNumber,
                ordinal: fixtures.count + 1
            ))
            sourceIndex += 1
        }
        return fixtures
    }

    public func generateFullFixtures(count: Int = 100) -> [GeneratedEvaluationFixture] {
        generateFixtures(count: count)
    }

    public func generateSeedFixtures() -> [GeneratedEvaluationFixture] {
        [
            simpleHome(),
            duplicateLights(),
            numberedBulbs(),
            climateHeavy(),
            mediaHeavy(),
            securitySafety(),
            automationHeavy(),
            ambiguousRoomNames(),
            applianceHeavy(),
            mixedCatalogCustom()
        ]
    }

    private func simpleHome() -> GeneratedEvaluationFixture {
        GeneratedEvaluationFixture(
            id: "simple-home",
            name: "Simple Home",
            category: "simple-home",
            devices: [
                light(id: "simple_living_room_light", name: "Living Room Light", room: "living room"),
                light(id: "simple_bedroom_lamp", name: "Bedroom Lamp", room: "bedroom", aliases: "lamp"),
                switchDevice(id: "simple_kitchen_switch", name: "Kitchen Switch", room: "kitchen"),
                thermostat(id: "simple_hallway_thermostat", name: "Hallway Thermostat", room: "hallway")
            ],
            notes: "Small happy-path fixture for direct commands."
        )
    }

    private func duplicateLights() -> GeneratedEvaluationFixture {
        GeneratedEvaluationFixture(
            id: "duplicate-lights",
            name: "Duplicate Lights",
            category: "duplicate-lights",
            devices: [
                light(id: "duplicate_bedroom_ceiling_light", name: "Ceiling Light", room: "bedroom"),
                light(id: "duplicate_bedroom_lamp", name: "Lamp", room: "bedroom"),
                light(id: "duplicate_guest_lamp", name: "Lamp", room: "guest room"),
                light(id: "duplicate_living_room_lamp", name: "Lamp", room: "living room"),
                light(id: "duplicate_kitchen_light", name: "Kitchen Light", room: "kitchen")
            ],
            notes: "Ambiguous names across rooms for retrieval and ranking."
        )
    }

    private func numberedBulbs() -> GeneratedEvaluationFixture {
        GeneratedEvaluationFixture(
            id: "numbered-bulbs",
            name: "Numbered Bulbs",
            category: "numbered-bulbs",
            devices: [
                light(id: "numbered_bulb_1", name: "Bulb 1", room: "living room", aliases: "bulb one,bulb number 1,first bulb"),
                light(id: "numbered_bulb_2", name: "Bulb2", room: "living room", aliases: "bulb two,bulb number 2,second bulb"),
                light(id: "numbered_bulb_3", name: "Bulb 3", room: "living room", aliases: "bulb three,bulb number 3,third bulb"),
                light(id: "numbered_lamp_01", name: "Lamp 01", room: "bedroom", aliases: "lamp one,lamp 1"),
                light(id: "numbered_kitchen_light_2", name: "Kitchen Light 2", room: "kitchen", aliases: "kitchen light two,kitchen second light")
            ],
            notes: "Preserves numeric device-name distinctions."
        )
    }

    private func climateHeavy() -> GeneratedEvaluationFixture {
        GeneratedEvaluationFixture(
            id: "climate-heavy",
            name: "Climate Heavy",
            category: "climate-heavy",
            devices: [
                airConditioner(id: "climate_bedroom_ac", name: "Bedroom AC", room: "bedroom"),
                airConditioner(id: "climate_living_room_ac", name: "Living Room AC", room: "living room"),
                thermostat(id: "climate_hallway_thermostat", name: "Hallway Thermostat", room: "hallway"),
                climateSwitch(id: "climate_office_heater", name: "Office Heater", deviceType: "heater", room: "office"),
                climateSwitch(id: "climate_nursery_humidifier", name: "Nursery Humidifier", deviceType: "humidifier", room: "nursery"),
                climateSwitch(id: "climate_basement_dehumidifier", name: "Basement Dehumidifier", deviceType: "dehumidifier", room: "basement"),
                airPurifier(id: "climate_air_purifier", name: "Air Purifier", room: "living room")
            ],
            notes: "Climate controls, modes, and measurement devices."
        )
    }

    private func mediaHeavy() -> GeneratedEvaluationFixture {
        GeneratedEvaluationFixture(
            id: "media-heavy",
            name: "Media Heavy",
            category: "media-heavy",
            devices: [
                mediaDevice(id: "media_living_room_tv", name: "Living Room TV", deviceType: "tv", room: "living room", aliases: "television,smart tv"),
                mediaDevice(id: "media_soundbar", name: "Soundbar", deviceType: "soundbar", room: "living room"),
                mediaDevice(id: "media_receiver", name: "Receiver", deviceType: "receiver", room: "media room"),
                mediaDevice(id: "media_streaming_box", name: "Streaming Box", deviceType: "streamingBox", room: "media room"),
                mediaDevice(id: "media_game_console", name: "Game Console", deviceType: "gameConsole", room: "media room"),
                mediaDevice(id: "media_kitchen_speaker", name: "Kitchen Speaker", deviceType: "speaker", room: "kitchen")
            ],
            notes: "Media devices for power, playback, volume, and input commands."
        )
    }

    private func securitySafety() -> GeneratedEvaluationFixture {
        GeneratedEvaluationFixture(
            id: "security-safety",
            name: "Security And Safety",
            category: "security-safety",
            devices: [
                lock(id: "security_front_door_lock", name: "Front Door Lock", room: "entry"),
                contactSensor(id: "security_entry_contact", name: "Entry Contact Sensor", room: "entry"),
                garageDoor(id: "security_garage_door", name: "Garage Door", room: "garage"),
                camera(id: "security_front_porch_camera", name: "Front Porch Camera", room: "porch"),
                sensor(id: "security_smoke_detector", name: "Hallway Smoke Detector", deviceType: "smokeDetector", room: "hallway", capability: "smokeDetector", stateKey: "smoke", state: "clear", risk: .high)
            ],
            notes: "High-risk and confirmation-heavy commands."
        )
    }

    private func automationHeavy() -> GeneratedEvaluationFixture {
        GeneratedEvaluationFixture(
            id: "automation-heavy",
            name: "Automation Heavy",
            category: "automation-heavy",
            devices: [
                airConditioner(id: "automation_bedroom_ac", name: "Bedroom AC", room: "bedroom"),
                light(id: "automation_bedroom_lamp", name: "Bedroom Lamp", room: "bedroom"),
                light(id: "automation_living_room_light", name: "Living Room Light", room: "living room"),
                lock(id: "automation_front_door_lock", name: "Front Door Lock", room: "entry"),
                contactSensor(id: "automation_entry_contact", name: "Entry Contact Sensor", room: "entry"),
                sensor(id: "automation_hallway_motion", name: "Hallway Motion Sensor", deviceType: "motionSensor", room: "hallway", capability: "motionSensor", stateKey: "motion", state: "inactive"),
                airPurifier(id: "automation_air_purifier", name: "Air Purifier", room: "living room")
            ],
            notes: "Schedule, trigger, action, and condition automation fixture."
        )
    }

    private func ambiguousRoomNames() -> GeneratedEvaluationFixture {
        GeneratedEvaluationFixture(
            id: "ambiguous-room-names",
            name: "Ambiguous Room Names",
            category: "ambiguous-room-names",
            devices: [
                light(id: "ambiguous_office_lamp", name: "Office Lamp", room: "office"),
                light(id: "ambiguous_bedroom_lamp", name: "Bedroom Lamp", room: "bedroom"),
                light(id: "ambiguous_guest_room_lamp", name: "Guest Room Lamp", room: "guest room"),
                light(id: "ambiguous_main_bedroom_lamp", name: "Main Bedroom Lamp", room: "main bedroom"),
                switchDevice(id: "ambiguous_office_switch", name: "Office Switch", room: "office")
            ],
            notes: "Similar room and device labels."
        )
    }

    private func applianceHeavy() -> GeneratedEvaluationFixture {
        GeneratedEvaluationFixture(
            id: "appliance-heavy",
            name: "Appliance Heavy",
            category: "appliance-heavy",
            devices: [
                appliance(id: "appliance_washer", name: "Washer", deviceType: "washer", room: "laundry"),
                appliance(id: "appliance_dryer", name: "Dryer", deviceType: "dryer", room: "laundry"),
                cookingAppliance(id: "appliance_oven", name: "Oven", deviceType: "oven", room: "kitchen"),
                appliance(id: "appliance_dishwasher", name: "Dishwasher", deviceType: "dishwasher", room: "kitchen"),
                appliance(id: "appliance_robot_cleaner", name: "Robot Cleaner", deviceType: "robotCleaner", room: "home", aliases: "robot vacuum,vacuum"),
                climateSwitch(id: "appliance_kettle", name: "Kettle", deviceType: "kettle", room: "kitchen")
            ],
            notes: "Appliance cycles and higher-risk operations."
        )
    }

    private func mixedCatalogCustom() -> GeneratedEvaluationFixture {
        let defaults = Array(MockHomeDeviceRegistry.defaultDevices.prefix(8))
        return GeneratedEvaluationFixture(
            id: "mixed-catalog-custom",
            name: "Mixed Catalog Custom",
            category: "mixed-catalog-custom",
            devices: defaults + [
                light(id: "mixed_custom_art_light", name: "Art Light", room: "hallway", aliases: "gallery light"),
                mediaDevice(id: "mixed_custom_den_tv", name: "Den TV", deviceType: "television", room: "den", aliases: "den television")
            ],
            notes: "Default registry records plus custom catalog-style devices."
        )
    }

    private func variantFixture(
        from fixture: GeneratedEvaluationFixture,
        variantNumber: Int,
        ordinal: Int
    ) -> GeneratedEvaluationFixture {
        let fixtureID = "\(fixture.id)-variant-\(String(format: "%02d", variantNumber))"
        let devicePrefix = fixtureID.replacingOccurrences(of: "-", with: "_")
        return GeneratedEvaluationFixture(
            id: fixtureID,
            name: "\(fixture.name) Variant \(variantNumber)",
            category: fixture.category,
            devices: fixture.devices.map { device in
                variantDevice(
                    from: device,
                    devicePrefix: devicePrefix,
                    variantNumber: variantNumber,
                    ordinal: ordinal
                )
            },
            notes: [
                fixture.notes,
                "Deterministic full-dataset variant \(variantNumber) for scale-out fixture \(ordinal)."
            ].compactMap { $0 }.joined(separator: " ")
        )
    }

    private func variantDevice(
        from device: HomeCandidateRecord,
        devicePrefix: String,
        variantNumber: Int,
        ordinal: Int
    ) -> HomeCandidateRecord {
        var metadata = device.metadata
        metadata["fixtureVariant"] = String(variantNumber)
        metadata["fixtureOrdinal"] = String(ordinal)
        return HomeCandidateRecord(
            id: "\(devicePrefix)_\(device.id)",
            type: device.type,
            displayName: device.displayName,
            deviceType: device.deviceType,
            room: device.room,
            capabilities: device.capabilities,
            supportedCommands: device.supportedCommands,
            supportedModes: device.supportedModes,
            currentState: device.currentState,
            metadata: metadata,
            riskLevel: device.riskLevel
        )
    }

    private func light(id: String, name: String, room: String, aliases: String = "") -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: id,
            displayName: name,
            deviceType: "light",
            room: room,
            capabilities: ["switch", "switchLevel", "colorTemperature"],
            supportedCommands: [
                "switch": ["on", "off"],
                "switchLevel": ["setLevel", "increaseValue", "decreaseValue"],
                "colorTemperature": ["setColorTemperature", "increaseValue", "decreaseValue"]
            ],
            supportedModes: ["on", "off", "K"],
            currentState: ["switch": "off", "level": "50", "colorTemperature": "2700"],
            metadata: metadata(aliases: aliases, category: "lighting"),
            riskLevel: .low
        )
    }

    private func switchDevice(id: String, name: String, room: String) -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: id,
            displayName: name,
            deviceType: "switch",
            room: room,
            capabilities: ["switch", "switchLevel"],
            supportedCommands: [
                "switch": ["on", "off"],
                "switchLevel": ["setLevel", "increaseValue", "decreaseValue"]
            ],
            supportedModes: ["on", "off"],
            currentState: ["switch": "off", "level": "50"],
            metadata: metadata(aliases: "wall switch,dimmer", category: "lighting"),
            riskLevel: .low
        )
    }

    private func airConditioner(id: String, name: String, room: String) -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: id,
            displayName: name,
            deviceType: "airConditioner",
            room: room,
            capabilities: [
                "switch",
                "temperatureMeasurement",
                "relativeHumidityMeasurement",
                "thermostatCoolingSetpoint",
                "airConditionerMode",
                "airConditionerFanMode"
            ],
            supportedCommands: [
                "switch": ["on", "off"],
                "temperatureMeasurement": ["getStatus"],
                "relativeHumidityMeasurement": ["getStatus"],
                "thermostatCoolingSetpoint": ["setCoolingSetpoint", "increaseValue", "decreaseValue"],
                "airConditionerMode": ["setAirConditionerMode"],
                "airConditionerFanMode": ["setFanMode"]
            ],
            supportedModes: ["on", "off", "cool", "heat", "auto", "dry", "fanOnly", "low", "medium", "high"],
            currentState: ["switch": "off", "temperature": "25", "humidity": "55", "coolingSetpoint": "24", "airConditionerMode": "cool", "fanMode": "auto"],
            metadata: metadata(aliases: "AC,aircon", category: "climate"),
            riskLevel: .medium
        )
    }

    private func thermostat(id: String, name: String, room: String) -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: id,
            displayName: name,
            deviceType: "thermostat",
            room: room,
            capabilities: ["temperatureMeasurement", "relativeHumidityMeasurement", "thermostatMode", "thermostatCoolingSetpoint", "thermostatHeatingSetpoint", "thermostatFanMode"],
            supportedCommands: [
                "temperatureMeasurement": ["getStatus"],
                "relativeHumidityMeasurement": ["getStatus"],
                "thermostatMode": ["setThermostatMode"],
                "thermostatCoolingSetpoint": ["setCoolingSetpoint", "increaseValue", "decreaseValue"],
                "thermostatHeatingSetpoint": ["setHeatingSetpoint", "increaseValue", "decreaseValue"],
                "thermostatFanMode": ["setThermostatFanMode"]
            ],
            supportedModes: ["auto", "cool", "heat", "off", "on", "circulate"],
            currentState: ["temperature": "22", "humidity": "45", "thermostatMode": "auto", "coolingSetpoint": "24", "heatingSetpoint": "20"],
            metadata: metadata(aliases: "", category: "climate"),
            riskLevel: .medium
        )
    }

    private func climateSwitch(id: String, name: String, deviceType: String, room: String) -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: id,
            displayName: name,
            deviceType: deviceType,
            room: room,
            capabilities: ["switch", "temperatureMeasurement"],
            supportedCommands: [
                "switch": ["on", "off"],
                "temperatureMeasurement": ["getStatus"]
            ],
            supportedModes: ["on", "off"],
            currentState: ["switch": "off", "temperature": "unknown"],
            metadata: metadata(aliases: "", category: "climate"),
            riskLevel: .medium
        )
    }

    private func airPurifier(id: String, name: String, room: String) -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: id,
            displayName: name,
            deviceType: "airPurifier",
            room: room,
            capabilities: ["switch", "airQualitySensor", "filterStatus"],
            supportedCommands: [
                "switch": ["on", "off"],
                "airQualitySensor": ["getStatus"],
                "filterStatus": ["getStatus"]
            ],
            supportedModes: ["on", "off", "good", "moderate", "poor", "replace"],
            currentState: ["switch": "off", "airQuality": "good", "filterStatus": "normal"],
            metadata: metadata(aliases: "purifier", category: "air quality"),
            riskLevel: .low
        )
    }

    private func mediaDevice(id: String, name: String, deviceType: String, room: String, aliases: String = "") -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: id,
            displayName: name,
            deviceType: deviceType,
            room: room,
            capabilities: ["switch", "audioVolume", "mediaPlayback", "mediaInputSource"],
            supportedCommands: [
                "switch": ["on", "off"],
                "audioVolume": ["setVolume", "volumeUp", "volumeDown", "mute", "unmute"],
                "mediaPlayback": ["play", "pause", "stop", "fastForward", "rewind"],
                "mediaInputSource": ["setInputSource"]
            ],
            supportedModes: ["on", "off", "playing", "paused", "stopped", "HDMI1", "HDMI2", "TV"],
            currentState: ["switch": "off", "volume": "35", "playbackStatus": "stopped", "inputSource": "HDMI1"],
            metadata: metadata(aliases: aliases, category: "media"),
            riskLevel: .low
        )
    }

    private func lock(id: String, name: String, room: String) -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: id,
            displayName: name,
            deviceType: "lock",
            room: room,
            capabilities: ["lock", "contactSensor", "battery"],
            supportedCommands: [
                "lock": ["lock", "unlock", "getStatus"],
                "contactSensor": ["getStatus"],
                "battery": ["getStatus"]
            ],
            supportedModes: ["locked", "unlocked", "open", "closed"],
            currentState: ["lock": "locked", "contact": "closed", "battery": "92"],
            metadata: metadata(aliases: "smart lock,door lock", category: "security"),
            riskLevel: .high
        )
    }

    private func contactSensor(id: String, name: String, room: String) -> HomeCandidateRecord {
        sensor(
            id: id,
            name: name,
            deviceType: "contactSensor",
            room: room,
            capability: "contactSensor",
            stateKey: "contact",
            state: "closed"
        )
    }

    private func garageDoor(id: String, name: String, room: String) -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: id,
            displayName: name,
            deviceType: "garageDoor",
            room: room,
            capabilities: ["garageDoorControl", "contactSensor"],
            supportedCommands: [
                "garageDoorControl": ["open", "close", "getStatus"],
                "contactSensor": ["getStatus"]
            ],
            supportedModes: ["open", "closed", "opening", "closing"],
            currentState: ["door": "closed", "contact": "closed"],
            metadata: metadata(aliases: "garage", category: "security"),
            riskLevel: .high
        )
    }

    private func camera(id: String, name: String, room: String) -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: id,
            displayName: name,
            deviceType: "camera",
            room: room,
            capabilities: ["switch", "motionSensor", "videoStream", "imageCapture"],
            supportedCommands: [
                "switch": ["on", "off"],
                "motionSensor": ["getStatus"],
                "videoStream": ["startStream", "stopStream"],
                "imageCapture": ["take"]
            ],
            supportedModes: ["on", "off", "active", "inactive"],
            currentState: ["switch": "on", "motion": "inactive", "stream": "idle"],
            metadata: metadata(aliases: "", category: "security"),
            riskLevel: .high
        )
    }

    private func sensor(
        id: String,
        name: String,
        deviceType: String,
        room: String,
        capability: String,
        stateKey: String,
        state: String,
        risk: HomeAutomationRiskLevel = .low
    ) -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: id,
            displayName: name,
            deviceType: deviceType,
            room: room,
            capabilities: [capability, "battery"],
            supportedCommands: [
                capability: ["getStatus"],
                "battery": ["getStatus"]
            ],
            supportedModes: ["open", "closed", "active", "inactive", "clear", "detected"],
            currentState: [stateKey: state, "battery": "90"],
            metadata: metadata(aliases: "", category: "sensor"),
            riskLevel: risk
        )
    }

    private func appliance(id: String, name: String, deviceType: String, room: String, aliases: String = "") -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: id,
            displayName: name,
            deviceType: deviceType,
            room: room,
            capabilities: ["switch", "startStop", "mode", "runCycle"],
            supportedCommands: [
                "switch": ["on", "off"],
                "startStop": ["start", "stop", "pause", "resume"],
                "mode": ["setMode"],
                "runCycle": ["getStatus"]
            ],
            supportedModes: ["on", "off", "ready", "running", "paused", "finished", "normal", "quick", "eco"],
            currentState: ["switch": "off", "machineState": "ready", "mode": "normal", "runCycle": "idle"],
            metadata: metadata(aliases: aliases, category: "appliance"),
            riskLevel: .medium
        )
    }

    private func cookingAppliance(id: String, name: String, deviceType: String, room: String) -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: id,
            displayName: name,
            deviceType: deviceType,
            room: room,
            capabilities: ["switch", "cook", "temperatureMeasurement", "timer"],
            supportedCommands: [
                "switch": ["on", "off"],
                "cook": ["start", "stop", "setCookMode"],
                "temperatureMeasurement": ["getStatus"],
                "timer": ["setTimer", "pauseTimer", "resumeTimer", "cancelTimer", "getStatus"]
            ],
            supportedModes: ["on", "off", "bake", "broil", "roast", "warm"],
            currentState: ["switch": "off", "cookMode": "bake", "temperature": "24"],
            metadata: metadata(aliases: "", category: "cooking"),
            riskLevel: .high
        )
    }

    private func metadata(aliases: String, category: String) -> [String: String] {
        [
            "aliases": aliases,
            "category": category
        ]
    }
}
