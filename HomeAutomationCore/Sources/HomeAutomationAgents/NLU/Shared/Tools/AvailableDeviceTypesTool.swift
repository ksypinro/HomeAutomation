import Foundation
import FoundationModels
import HomeAutomationCore
import os

// MARK: - Tool: Available Device Types Lookup

/// A Foundation Model Tool that returns all supported smart-home device types
/// with rich descriptions so the model can reason about which types match a user command.
public struct AvailableDeviceTypesTool: Tool {
    public let name = "getAvailableDeviceTypes"
    public let description = """
        Returns every supported smart-home device type with its identifier, human-readable name, \
        common aliases, and a description of what the device is. \
        Call this tool first to see which device types exist before classifying the user command.
        """

    private let catalog: [DeviceTypeCatalogEntry]

    public init(catalog: [DeviceTypeCatalogEntry]? = nil) {
        self.catalog = catalog ?? Self.defaultCatalog()
    }

    @Generable
    public struct Arguments {
        @Guide(description: "Optional keyword to filter device types. Pass empty string to get all types.")
        public let filterKeyword: String?

        public init(filterKeyword: String? = nil) {
            self.filterKeyword = filterKeyword
        }
    }

    public func call(arguments: Arguments) async throws -> String {
        let keyword = arguments.filterKeyword?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let filtered: [DeviceTypeCatalogEntry]
        if keyword.isEmpty {
            filtered = catalog
        } else {
            filtered = catalog.filter { entry in
                entry.id.lowercased().contains(keyword) ||
                entry.displayName.lowercased().contains(keyword) ||
                entry.description.lowercased().contains(keyword) ||
                entry.aliases.contains { $0.lowercased().contains(keyword) }
            }
        }
        return filtered.map { entry in
            let aliasText = entry.aliases.isEmpty ? "" : " aliases=[\(entry.aliases.joined(separator: ", "))]"
            return "• \(entry.id) (\(entry.displayName))\(aliasText): \(entry.description)"
        }.joined(separator: "\n")
    }

    // MARK: - Default Catalog

    public static func defaultCatalog() -> [DeviceTypeCatalogEntry] {
        HomeAutomationKnowledgeBase.shared.deviceTypes.map { catalogType in
            var id = catalogType.id
            if id == "scene" { id = "routine" }
            else if id == "vacuum" { id = "robotCleaner" }
            return DeviceTypeCatalogEntry(
                id: id,
                displayName: catalogType.displayName,
                aliases: catalogType.aliases,
                description: Self.descriptionForDeviceType(catalogType)
            )
        }
    }

    private static func descriptionForDeviceType(_ type: HomeCatalogDeviceType) -> String {
        switch type.id {
        case "light":
            return "Any light fixture: ceiling lights, lamps, strip lights, bulbs, chandeliers, sconces, night lights. Supports on/off, brightness, color, color temperature."
        case "airConditioner":
            return "Air conditioning unit, AC, mini-split, window AC. Controls cooling temperature setpoint, fan speed, and AC modes like cool/dry/fan."
        case "thermostat":
            return "Central heating/cooling thermostat. Controls heating and cooling setpoints, thermostat modes (heat/cool/auto/off), and fan modes."
        case "fan":
            return "Standalone fan, ceiling fan, tower fan. Controls on/off and fan speed levels."
        case "lock":
            return "Smart door lock, deadbolt, keypad lock. Controls lock/unlock state and lock codes. Security-sensitive device."
        case "garageDoor":
            return "Motorized garage door opener. Controls open/close state. Security-sensitive device."
        case "blind":
            return "Window blinds, shades, curtains, roller shutters, window coverings. Controls open/close and shade level position."
        case "valve":
            return "Water valve, irrigation valve, sprinkler valve, gas valve. Controls open/close state of fluid flow."
        case "contactSensor":
            return "Door/window contact sensor, open/close sensor. Reports whether a door or window is open or closed. Read-only sensor."
        case "motionSensor":
            return "Motion detector, occupancy sensor, presence sensor. Reports motion activity. Read-only sensor."
        case "airQualityDetector":
            return "Air quality monitor, AQI sensor, CO2 sensor, particulate sensor. Measures air quality, CO2 levels, humidity, and temperature. Read-only sensor."
        case "airPurifier":
            return "Air purifier, air cleaner, air filtration unit. Controls on/off, purifier fan speed/mode, and reports filter status."
        case "tv":
            return "Television, smart TV, display. Controls on/off, volume, media playback, input source, and TV channels."
        case "speaker":
            return "Smart speaker, soundbar, audio player, wireless speaker. Controls on/off, volume, mute, and media playback."
        case "washer":
            return "Washing machine, clothes washer, laundry machine. Controls on/off, wash mode, and reports operating state."
        case "dryer":
            return "Clothes dryer, tumble dryer. Controls on/off, dryer mode, and reports operating state."
        case "oven":
            return "Kitchen oven, range, cooktop. Controls oven mode, temperature setpoint. Can be a safety-sensitive device."
        case "robotCleaner", "vacuum":
            return "Robot vacuum, robotic cleaner, Roomba-style device. Controls start/stop/pause cleaning, cleaning mode, and return-to-home."
        case "camera":
            return "Security camera, IP camera, doorbell camera, surveillance camera. Supports video streaming, image capture, motion detection."
        case "waterSensor":
            return "Water leak sensor, flood sensor. Detects presence of water. Read-only sensor."
        case "smokeDetector":
            return "Smoke detector, smoke alarm, fire alarm, CO detector. Detects smoke and carbon monoxide. Read-only safety sensor."
        case "routine", "scene":
            return "Automation routine, scene, scenario. A named sequence of actions across multiple devices. Examples: 'Good Night', 'Movie Time'."
        case "doorbell":
            return "Video doorbell, smart doorbell. Detects button presses, streams video, and detects motion."
        case "hub":
            return "Smart home hub, bridge, gateway. Central controller that connects other smart devices."
        case "refrigerator":
            return "Smart refrigerator, fridge. Reports temperature, filter status, and door state."
        case "dishwasher":
            return "Smart dishwasher. Controls wash mode and reports operating state."
        case "microwave":
            return "Smart microwave oven. Controls cook mode, timer, and power level."
        case "outlet":
            return "Smart plug, smart outlet, power socket. Controls on/off state of connected devices and may report power consumption."
        case "switch":
            return "Smart switch, wall switch, toggle switch. Controls on/off state. Different from a smart plug in that it's hardwired."
        case "irrigationSystem":
            return "Sprinkler system, irrigation controller. Controls watering zones and schedules."
        case "humidifier":
            return "Humidifier or dehumidifier. Controls moisture level in air."
        case "heater":
            return "Space heater, portable heater, radiator. Controls on/off and temperature."
        default:
            let aliasHint = type.aliases.isEmpty ? "" : " Also known as: \(type.aliases.joined(separator: ", "))."
            return "\(type.displayName) device.\(aliasHint)"
        }
    }
}

/// A single entry in the device type catalog returned by the tool.
public struct DeviceTypeCatalogEntry: Sendable, Codable, Hashable {
    public let id: String
    public let displayName: String
    public let aliases: [String]
    public let description: String

    public init(id: String, displayName: String, aliases: [String], description: String) {
        self.id = id
        self.displayName = displayName
        self.aliases = aliases
        self.description = description
    }
}
