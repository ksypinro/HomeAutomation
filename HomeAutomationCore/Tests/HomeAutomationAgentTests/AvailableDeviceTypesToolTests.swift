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
    func catalogEntriesHaveDescriptions() {
        let catalog = AvailableDeviceTypesTool.defaultCatalog()

        for entry in catalog {
            #expect(!entry.description.isEmpty, "Missing description for: \(entry.id)")
        }
    }
}
