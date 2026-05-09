import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import Testing

// MARK: - Test Case Model

struct DeviceTypeTestCase: Sendable {
    let id: Int
    let input: String
    let expectedTypes: [String]
    let tags: [String]
}

// MARK: - Test Suite

@Suite
struct DeviceTypeAgentTests {

    // MARK: - Tool Unit Tests

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
    func workerSessionUsesInjectedClassifier() async throws {
        let worker = DeviceTypeAgentWorkerSession { _ in
            HomeDeviceTypeResult(deviceTypes: ["light"], confidence: 0.99)
        }
        let result = try await worker.classifyDeviceType("turn on the lamp")
        #expect(result.deviceTypes == ["light"])
        #expect(result.confidence == 0.99)
    }

    @Test
    func workerSessionReturnsEmptyWhenFMUnavailable() async throws {
        let worker = DeviceTypeAgentWorkerSession(
            foundationModelAvailability: { false }
        )
        let result = try await worker.classifyDeviceType("turn on the lamp")
        #expect(result.deviceTypes.isEmpty)
        #expect(result.confidence == 0.0)
    }

    @Test
    func agentPassesThroughInjectedClassifier() async throws {
        let agent = DeviceTypeAgent { _ in
            HomeDeviceTypeResult(deviceTypes: ["tv"], confidence: 0.95)
        }
        let context = ResolutionContext(request: CommandRequest(text: "turn on tv", executeLowRiskCommands: false))
        let result = try await agent.run("turn on tv", context: context)
        #expect(result.deviceTypes == ["tv"])
    }

    @Test
    func defaultCatalogContainsAllCoreTypes() {
        let catalog = AvailableDeviceTypesTool.defaultCatalog()
        let ids = Set(catalog.map(\.id))
        let coreTypes = ["light", "airConditioner", "thermostat", "lock", "garageDoor",
                         "blind", "tv", "speaker", "washer", "dryer", "oven",
                         "robotCleaner", "camera", "routine"]
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

    // MARK: - 100 Mock-Injected Classification Tests

    static let testCases: [DeviceTypeTestCase] = [
        // --- Lights (1-12) ---
        .init(id: 1, input: "Turn on the light", expectedTypes: ["light"], tags: ["light", "power"]),
        .init(id: 2, input: "Turn off the bedroom lamp", expectedTypes: ["light"], tags: ["light", "power", "room"]),
        .init(id: 3, input: "Dim the living room light to 50%", expectedTypes: ["light"], tags: ["light", "brightness"]),
        .init(id: 4, input: "Set the kitchen strip light to warm white", expectedTypes: ["light"], tags: ["light", "color"]),
        .init(id: 5, input: "Change the bulb color to blue", expectedTypes: ["light"], tags: ["light", "color"]),
        .init(id: 6, input: "Make the lights brighter", expectedTypes: ["light"], tags: ["light", "brightness"]),
        .init(id: 7, input: "Turn on all the lights", expectedTypes: ["light"], tags: ["light", "group"]),
        .init(id: 8, input: "Switch off the porch light", expectedTypes: ["light"], tags: ["light", "power"]),
        .init(id: 9, input: "Set the chandelier to 80 percent", expectedTypes: ["light"], tags: ["light", "brightness"]),
        .init(id: 10, input: "Turn on the night light", expectedTypes: ["light"], tags: ["light", "power"]),
        .init(id: 11, input: "Increase brightness of ceiling light", expectedTypes: ["light"], tags: ["light", "brightness"]),
        .init(id: 12, input: "Is the bedroom light on?", expectedTypes: ["light"], tags: ["light", "status"]),
        // --- AC (13-20) ---
        .init(id: 13, input: "Set the AC to 22 degrees", expectedTypes: ["airConditioner"], tags: ["ac", "temperature"]),
        .init(id: 14, input: "Turn on the air conditioner", expectedTypes: ["airConditioner"], tags: ["ac", "power"]),
        .init(id: 15, input: "Lower the AC temperature by 2 degrees", expectedTypes: ["airConditioner"], tags: ["ac", "relative"]),
        .init(id: 16, input: "Set bedroom AC to cool mode", expectedTypes: ["airConditioner"], tags: ["ac", "mode"]),
        .init(id: 17, input: "Turn off the air conditioning", expectedTypes: ["airConditioner"], tags: ["ac", "power"]),
        .init(id: 18, input: "Set the AC fan speed to high", expectedTypes: ["airConditioner"], tags: ["ac", "fan"]),
        .init(id: 19, input: "What's the AC temperature?", expectedTypes: ["airConditioner"], tags: ["ac", "status"]),
        .init(id: 20, input: "Switch the air conditioner to dry mode", expectedTypes: ["airConditioner"], tags: ["ac", "mode"]),
        // --- Thermostat (21-28) ---
        .init(id: 21, input: "Set the thermostat to 72", expectedTypes: ["thermostat"], tags: ["thermostat", "temperature"]),
        .init(id: 22, input: "Turn the heating up", expectedTypes: ["thermostat"], tags: ["thermostat", "relative"]),
        .init(id: 23, input: "Set heat to 68 degrees", expectedTypes: ["thermostat"], tags: ["thermostat", "temperature"]),
        .init(id: 24, input: "Switch thermostat to auto mode", expectedTypes: ["thermostat"], tags: ["thermostat", "mode"]),
        .init(id: 25, input: "Lower the heating setpoint by 3 degrees", expectedTypes: ["thermostat"], tags: ["thermostat", "relative"]),
        .init(id: 26, input: "Turn off the heater", expectedTypes: ["thermostat", "heater"], tags: ["thermostat", "power"]),
        .init(id: 27, input: "What's the hallway thermostat reading?", expectedTypes: ["thermostat"], tags: ["thermostat", "status"]),
        .init(id: 28, input: "Set the fan mode to on", expectedTypes: ["thermostat"], tags: ["thermostat", "fan"]),
        // --- Lock (29-34) ---
        .init(id: 29, input: "Lock the front door", expectedTypes: ["lock"], tags: ["lock", "security"]),
        .init(id: 30, input: "Unlock the door", expectedTypes: ["lock"], tags: ["lock", "security"]),
        .init(id: 31, input: "Is the front door locked?", expectedTypes: ["lock"], tags: ["lock", "status"]),
        .init(id: 32, input: "Lock all doors", expectedTypes: ["lock"], tags: ["lock", "group"]),
        .init(id: 33, input: "Set door lock code to 1234", expectedTypes: ["lock"], tags: ["lock", "code"]),
        .init(id: 34, input: "Check the lock battery", expectedTypes: ["lock"], tags: ["lock", "status"]),
        // --- Garage Door (35-38) ---
        .init(id: 35, input: "Open the garage door", expectedTypes: ["garageDoor"], tags: ["garage", "openClose"]),
        .init(id: 36, input: "Close the garage", expectedTypes: ["garageDoor"], tags: ["garage", "openClose"]),
        .init(id: 37, input: "Is the garage door open?", expectedTypes: ["garageDoor"], tags: ["garage", "status"]),
        .init(id: 38, input: "Shut the garage door", expectedTypes: ["garageDoor"], tags: ["garage", "openClose"]),
        // --- Blinds (39-42) ---
        .init(id: 39, input: "Open the blinds", expectedTypes: ["blind"], tags: ["blind", "openClose"]),
        .init(id: 40, input: "Close the living room curtains", expectedTypes: ["blind"], tags: ["blind", "openClose"]),
        .init(id: 41, input: "Set the shades to 50 percent", expectedTypes: ["blind"], tags: ["blind", "level"]),
        .init(id: 42, input: "Lower the window blinds", expectedTypes: ["blind"], tags: ["blind", "openClose"]),
        // --- TV (43-50) ---
        .init(id: 43, input: "Turn on the TV", expectedTypes: ["tv"], tags: ["tv", "power"]),
        .init(id: 44, input: "Turn off the television", expectedTypes: ["tv"], tags: ["tv", "power"]),
        .init(id: 45, input: "Change the channel to 5", expectedTypes: ["tv"], tags: ["tv", "channel"]),
        .init(id: 46, input: "Turn up the TV volume", expectedTypes: ["tv"], tags: ["tv", "volume"]),
        .init(id: 47, input: "Mute the TV", expectedTypes: ["tv"], tags: ["tv", "volume"]),
        .init(id: 48, input: "Switch input to HDMI 2", expectedTypes: ["tv"], tags: ["tv", "input"]),
        .init(id: 49, input: "Play something on the TV", expectedTypes: ["tv"], tags: ["tv", "media"]),
        .init(id: 50, input: "What channel is the TV on?", expectedTypes: ["tv"], tags: ["tv", "status"]),
        // --- Speaker (51-54) ---
        .init(id: 51, input: "Turn up the speaker volume", expectedTypes: ["speaker"], tags: ["speaker", "volume"]),
        .init(id: 52, input: "Play music on the kitchen speaker", expectedTypes: ["speaker"], tags: ["speaker", "media"]),
        .init(id: 53, input: "Pause the speaker", expectedTypes: ["speaker"], tags: ["speaker", "media"]),
        .init(id: 54, input: "Set speaker volume to 50", expectedTypes: ["speaker"], tags: ["speaker", "volume"]),
        // --- Washer/Dryer (55-60) ---
        .init(id: 55, input: "Start the washing machine", expectedTypes: ["washer"], tags: ["washer", "cycle"]),
        .init(id: 56, input: "Is the washer done?", expectedTypes: ["washer"], tags: ["washer", "status"]),
        .init(id: 57, input: "Set the washer to delicate mode", expectedTypes: ["washer"], tags: ["washer", "mode"]),
        .init(id: 58, input: "Start the dryer", expectedTypes: ["dryer"], tags: ["dryer", "cycle"]),
        .init(id: 59, input: "Stop the dryer", expectedTypes: ["dryer"], tags: ["dryer", "cycle"]),
        .init(id: 60, input: "Set the dryer to low heat", expectedTypes: ["dryer"], tags: ["dryer", "mode"]),
        // --- Oven (61-64) ---
        .init(id: 61, input: "Preheat the oven to 350", expectedTypes: ["oven"], tags: ["oven", "temperature"]),
        .init(id: 62, input: "Turn off the oven", expectedTypes: ["oven"], tags: ["oven", "power"]),
        .init(id: 63, input: "Set the oven to bake mode", expectedTypes: ["oven"], tags: ["oven", "mode"]),
        .init(id: 64, input: "What temperature is the oven at?", expectedTypes: ["oven"], tags: ["oven", "status"]),
        // --- Robot Vacuum (65-68) ---
        .init(id: 65, input: "Start the robot vacuum", expectedTypes: ["robotCleaner"], tags: ["vacuum", "cycle"]),
        .init(id: 66, input: "Send the Roomba home", expectedTypes: ["robotCleaner"], tags: ["vacuum", "command"]),
        .init(id: 67, input: "Pause the vacuum cleaner", expectedTypes: ["robotCleaner"], tags: ["vacuum", "cycle"]),
        .init(id: 68, input: "Set vacuum to turbo mode", expectedTypes: ["robotCleaner"], tags: ["vacuum", "mode"]),
        // --- Camera (69-72) ---
        .init(id: 69, input: "Show me the front porch camera", expectedTypes: ["camera"], tags: ["camera", "stream"]),
        .init(id: 70, input: "Turn off the security camera", expectedTypes: ["camera"], tags: ["camera", "power"]),
        .init(id: 71, input: "Take a snapshot from the camera", expectedTypes: ["camera"], tags: ["camera", "capture"]),
        .init(id: 72, input: "Is there motion on the porch cam?", expectedTypes: ["camera"], tags: ["camera", "status"]),
        // --- Sensors (73-78) ---
        .init(id: 73, input: "Is the front door open?", expectedTypes: ["contactSensor"], tags: ["sensor", "status"]),
        .init(id: 74, input: "Check the entry sensor", expectedTypes: ["contactSensor"], tags: ["sensor", "status"]),
        .init(id: 75, input: "Is there motion in the hallway?", expectedTypes: ["motionSensor"], tags: ["sensor", "status"]),
        .init(id: 76, input: "What's the air quality?", expectedTypes: ["airQualityDetector"], tags: ["sensor", "status"]),
        .init(id: 77, input: "Check for water leaks in the basement", expectedTypes: ["waterSensor"], tags: ["sensor", "status"]),
        .init(id: 78, input: "Is the smoke detector working?", expectedTypes: ["smokeDetector"], tags: ["sensor", "status"]),
        // --- Air Purifier (79-80) ---
        .init(id: 79, input: "Turn on the air purifier", expectedTypes: ["airPurifier"], tags: ["purifier", "power"]),
        .init(id: 80, input: "Set the nursery purifier to auto", expectedTypes: ["airPurifier"], tags: ["purifier", "mode"]),
        // --- Valve (81-82) ---
        .init(id: 81, input: "Open the patio water valve", expectedTypes: ["valve"], tags: ["valve", "openClose"]),
        .init(id: 82, input: "Turn off the sprinkler", expectedTypes: ["valve", "irrigationSystem"], tags: ["valve", "power"]),
        // --- Routine (83-86) ---
        .init(id: 83, input: "Run Movie Time", expectedTypes: ["routine"], tags: ["routine"]),
        .init(id: 84, input: "Activate Good Night routine", expectedTypes: ["routine"], tags: ["routine"]),
        .init(id: 85, input: "Start movie mode", expectedTypes: ["routine"], tags: ["routine"]),
        .init(id: 86, input: "Execute bedtime scene", expectedTypes: ["routine"], tags: ["routine"]),
        // --- Ambiguous / Multi-type (87-92) ---
        .init(id: 87, input: "Check the temperature", expectedTypes: ["thermostat", "airConditioner"], tags: ["ambiguous"]),
        .init(id: 88, input: "Turn everything off", expectedTypes: ["light", "tv", "speaker"], tags: ["ambiguous", "group"]),
        .init(id: 89, input: "Increase the volume", expectedTypes: ["tv", "speaker"], tags: ["ambiguous", "volume"]),
        .init(id: 90, input: "Set it to 25 degrees", expectedTypes: ["thermostat", "airConditioner"], tags: ["ambiguous", "temperature"]),
        .init(id: 91, input: "Is it humid in here?", expectedTypes: ["airQualityDetector", "thermostat"], tags: ["ambiguous", "status"]),
        .init(id: 92, input: "Play music", expectedTypes: ["speaker", "tv"], tags: ["ambiguous", "media"]),
        // --- No device type / Unsupported (93-96) ---
        .init(id: 93, input: "What's the weather today?", expectedTypes: [], tags: ["none"]),
        .init(id: 94, input: "Tell me a joke", expectedTypes: [], tags: ["none"]),
        .init(id: 95, input: "Set a timer for 5 minutes", expectedTypes: [], tags: ["none"]),
        .init(id: 96, input: "Good morning", expectedTypes: [], tags: ["none"]),
        // --- Informal / Slang (97-100) ---
        .init(id: 97, input: "Dim da lights bro", expectedTypes: ["light"], tags: ["slang", "light"]),
        .init(id: 98, input: "Crank up the AC", expectedTypes: ["airConditioner"], tags: ["slang", "ac"]),
        .init(id: 99, input: "Kill the TV", expectedTypes: ["tv"], tags: ["slang", "tv"]),
        .init(id: 100, input: "Fire up the Roomba", expectedTypes: ["robotCleaner"], tags: ["slang", "vacuum"]),
    ]

    /// Runs all 100 test cases using a mock classifier that simulates correct FM behavior.
    /// This validates the test data itself and that the agent plumbing works correctly.
    @Test(arguments: testCases.map(\.id))
    func mockClassifierProducesExpectedResult(caseId: Int) async throws {
        let tc = Self.testCases.first { $0.id == caseId }!
        let agent = DeviceTypeAgent { input in
            // Simulate perfect FM classification using our ground truth
            let match = Self.testCases.first { $0.input == input }
            return HomeDeviceTypeResult(
                deviceTypes: match?.expectedTypes ?? [],
                confidence: (match?.expectedTypes.isEmpty ?? true) ? 0.90 : 0.95
            )
        }
        let context = ResolutionContext(request: CommandRequest(text: tc.input, executeLowRiskCommands: false))
        let result = try await agent.run(tc.input, context: context)

        if tc.expectedTypes.isEmpty {
            #expect(result.deviceTypes.isEmpty, "Case \(tc.id): expected empty but got \(result.deviceTypes)")
        } else {
            // At least the first expected type must appear in results
            let resultSet = Set(result.deviceTypes)
            let expectedFirst = tc.expectedTypes[0]
            #expect(resultSet.contains(expectedFirst),
                    "Case \(tc.id) '\(tc.input)': expected \(expectedFirst) in \(result.deviceTypes)")
        }
    }

    /// Accuracy harness: runs all 100 cases through a provided classifier and computes metrics.
    static func evaluateAccuracy(
        classifier: @escaping @Sendable (String) async throws -> HomeDeviceTypeResult
    ) async -> DeviceTypeEvaluationReport {
        var correct = 0
        var total = testCases.count
        var failures: [(id: Int, input: String, expected: [String], got: [String])] = []

        for tc in testCases {
            do {
                let result = try await classifier(tc.input)
                let resultSet = Set(result.deviceTypes)
                let expectedSet = Set(tc.expectedTypes)

                if tc.expectedTypes.isEmpty {
                    if result.deviceTypes.isEmpty { correct += 1 }
                    else { failures.append((tc.id, tc.input, tc.expectedTypes, result.deviceTypes)) }
                } else if resultSet.contains(tc.expectedTypes[0]) {
                    correct += 1
                } else {
                    failures.append((tc.id, tc.input, tc.expectedTypes, result.deviceTypes))
                }
            } catch {
                failures.append((tc.id, tc.input, tc.expectedTypes, ["ERROR: \(error.localizedDescription)"]))
            }
        }

        return DeviceTypeEvaluationReport(
            total: total,
            correct: correct,
            accuracy: Double(correct) / Double(total),
            failures: failures.map {
                .init(id: $0.id, input: $0.input,
                      expected: $0.expected, got: $0.got)
            }
        )
    }
}

// MARK: - Evaluation Report

struct DeviceTypeEvaluationReport: Sendable {
    let total: Int
    let correct: Int
    let accuracy: Double
    let failures: [FailureCase]

    struct FailureCase: Sendable {
        let id: Int
        let input: String
        let expected: [String]
        let got: [String]
    }

    var summary: String {
        var lines = ["DeviceType Agent Accuracy: \(correct)/\(total) (\(String(format: "%.1f", accuracy * 100))%)"]
        if !failures.isEmpty {
            lines.append("Failures:")
            for f in failures {
                lines.append("  #\(f.id) \"\(f.input)\" expected=\(f.expected) got=\(f.got)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
