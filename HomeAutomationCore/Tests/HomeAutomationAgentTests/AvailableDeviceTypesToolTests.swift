import HomeAutomationAgents
import Testing

@Suite
struct AvailableDeviceTypesToolTests {
    @Test
    func toolReturnsAllDeviceTypes() async throws {
        let tool = AvailableDeviceTypesTool()
        let output = try await tool.call(arguments: .init())

        #expect(output.contains("light"))
        #expect(output.contains("thermostat"))
        #expect(output.contains("lock"))
    }

    @Test
    func toolFiltersDeviceTypesByKeyword() async throws {
        let tool = AvailableDeviceTypesTool()
        let output = try await tool.call(arguments: .init(filterKeyword: "light"))

        #expect(output.contains("light"))
        #expect(!output.contains("lock"))
    }

    @Test
    func toolCustomCatalogWorks() async throws {
        let catalog = [
            DeviceTypeCatalogEntry(id: "light", displayName: "Light", aliases: ["lamp", "bulb"], description: "Any light fixture."),
            DeviceTypeCatalogEntry(id: "lock", displayName: "Lock", aliases: ["deadbolt"], description: "Smart door lock.")
        ]
        let tool = AvailableDeviceTypesTool(catalog: catalog)
        let output = try await tool.call(arguments: .init())

        #expect(output.contains("light"))
        #expect(output.contains("lock"))
        #expect(!output.contains("thermostat"))
    }

    @Test
    func defaultCatalogContainsAllCoreTypes() {
        let catalog = AvailableDeviceTypesTool.defaultCatalog()
        let ids = Set(catalog.map(\.id))
        let coreTypes = [
            "light",
            "airConditioner",
            "thermostat",
            "lock",
            "garageDoor",
            "blind",
            "tv",
            "speaker",
            "washer",
            "dryer",
            "oven",
            "robotCleaner",
            "camera",
            "routine"
        ]

        for type in coreTypes {
            #expect(ids.contains(type), "Missing core type: \(type)")
        }
    }

    @Test
    func defaultCatalogContainsRequestedDeviceCategories() {
        let ids = Set(AvailableDeviceTypesTool.defaultCatalog().map(\.id))
        let requestedTypes = [
            "accessManagementService",
            "activeSpeaker",
            "activityTracker",
            "airCompressor",
            "airConditioner",
            "airer",
            "airPurifier",
            "airQualityMonitor",
            "arcFaultCircuitInterrupter",
            "audioSystem",
            "avPlayer",
            "bathroomGeneral",
            "battery",
            "batteryCharger",
            "blind",
            "bloodPressureMonitor",
            "bodyCompositionAnalyser",
            "bodyScale",
            "bodyThermometer",
            "bridge",
            "businessEquipment",
            "camera",
            "circuitBreaker",
            "clothesWasherDryer",
            "coffeeMachine",
            "computer",
            "condenser",
            "condensingUnit",
            "continuousGlucoseMeter",
            "cookerHood",
            "cooktop",
            "credentialManagementService",
            "cyclingCadenceSensor",
            "cyclingPowerMeter",
            "cyclingSpeedSensor",
            "dataStorageUnit",
            "decorativeLighting",
            "dehumidifier",
            "desktopPC",
            "deviceOwnershipTransferService",
            "dishwasher",
            "display",
            "door",
            "dryerLaundry",
            "electricMeter",
            "electricVehicleCharger",
            "electronics",
            "emergencyLighting",
            "energyGenerator",
            "energyMonitor",
            "exerciseMachine",
            "fan",
            "fireplace",
            "fitnessDevice",
            "foodProbe",
            "freezer",
            "furnace",
            "gameConsole",
            "garageDoor",
            "genericSensor",
            "glucoseMeter",
            "grinder",
            "groundFaultCircuitInterrupter",
            "handset",
            "heartRateMonitor",
            "humidifier",
            "hvac",
            "iceMachine",
            "indoorGarden",
            "inverter",
            "kettle",
            "light",
            "lightingControls",
            "mattress",
            "medicalDevice",
            "microwaveOven",
            "muscleOxygenMonitor",
            "musicalInstrument",
            "networkingEquipment",
            "notebookPC",
            "opticalAugmentedRFIDReader",
            "oven",
            "personalHealthDevice",
            "portableElectronics",
            "portableHVAC",
            "portableStove",
            "printer",
            "printer3D",
            "printerMultiFunction",
            "pulseOximeter",
            "pump",
            "pvArraySystem",
            "range",
            "receiver",
            "refrigerator",
            "robotCleaner",
            "scanner",
            "securityPanel",
            "server",
            "setTopBox",
            "sleepMonitor",
            "smartLock",
            "smartPlug",
            "steamCloset",
            "switch",
            "telephony",
            "television",
            "thermostat",
            "vendingMachine",
            "virtualDevice",
            "washerLaundry",
            "waterDispenser",
            "waterHeater",
            "waterPurifier",
            "waterValve",
            "window"
        ]

        for type in requestedTypes {
            #expect(ids.contains(type), "Missing requested type: \(type)")
        }
    }

    @Test
    func deterministicDeviceTypeFallbackUsesExpandedCatalog() {
        #expect(AgentTextParser.deviceTypes(for: "turn on the 3d printer").contains("printer3D"))
        #expect(AgentTextParser.deviceTypes(for: "check the blood pressure monitor").contains("bloodPressureMonitor"))
        #expect(AgentTextParser.deviceTypes(for: "turn off the smart plug").contains("smartPlug"))
        #expect(AgentTextParser.deviceTypes(for: "mute the television").contains("television"))
        #expect(AgentTextParser.deviceTypes(for: "start the ev charger").contains("electricVehicleCharger"))
    }

    @Test
    func toolFiltersExpandedDeviceCategoriesByKeyword() async throws {
        let tool = AvailableDeviceTypesTool()

        let medicalOutput = try await tool.call(arguments: .init(filterKeyword: "blood pressure"))
        #expect(medicalOutput.contains("bloodPressureMonitor"))
        #expect(!medicalOutput.contains("printer3D"))

        let printerOutput = try await tool.call(arguments: .init(filterKeyword: "3D Printer"))
        #expect(printerOutput.contains("printer3D"))
        #expect(!printerOutput.contains("bloodPressureMonitor"))
    }

    @Test
    func catalogEntriesHaveDescriptions() {
        let catalog = AvailableDeviceTypesTool.defaultCatalog()

        for entry in catalog {
            #expect(!entry.description.isEmpty, "Missing description for: \(entry.id)")
        }
    }
}
