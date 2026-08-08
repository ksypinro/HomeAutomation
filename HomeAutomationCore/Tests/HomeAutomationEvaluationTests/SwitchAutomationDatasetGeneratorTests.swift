import Foundation
import HomeAutomationCore
import HomeAutomationEvaluation
import Testing

@Suite("Switch automation dataset generator")
struct SwitchAutomationDatasetGeneratorTests {

    @Test("counts match ordered no-repeat template combinatorics")
    func countsMatchTemplateCombinatorics() {
        let generator = SwitchAutomationDatasetGenerator(devices: Self.devices)

        #expect(generator.totalCaseCount(for: .oneActionSchedule) == 6)
        #expect(generator.totalCaseCount(for: .twoActionSchedule) == 24)
        #expect(generator.totalCaseCount(for: .oneActionOneCondition) == 36)
        #expect(generator.totalCaseCount(for: .oneActionTwoConditions) == 144)
        #expect(generator.totalCaseCount(for: .twoActionsTwoConditions) == 576)
    }

    @Test("generated inputs follow requested templates")
    func generatedInputsFollowTemplates() throws {
        let generator = SwitchAutomationDatasetGenerator(devices: Self.devices)

        #expect(try generator.makeCase(template: .oneActionSchedule, caseIndex: 0).input == "Turn on Alpha Plug everyday at 7.00PM")
        #expect(try generator.makeCase(template: .twoActionSchedule, caseIndex: 0).input == "Turn on Alpha Plug and Turn on Beta Lamp everyday at 7.00PM")
        #expect(try generator.makeCase(template: .oneActionOneCondition, caseIndex: 0).input == "Turn on Alpha Plug everyday at 7.00PM if Alpha Plug is on")
        #expect(try generator.makeCase(template: .oneActionTwoConditions, caseIndex: 0).input == "Turn on Alpha Plug everyday at 7.00PM if Alpha Plug is on and Beta Lamp is on")
        #expect(try generator.makeCase(template: .twoActionsTwoConditions, caseIndex: 0).input == "Turn on Alpha Plug and Turn on Beta Lamp everyday at 7.00PM if Alpha Plug is on and Beta Lamp is on")
    }

    @Test("expected output records actions conditions and exact SmartThings JSON")
    func expectedOutputRecordsExactJSON() throws {
        let generator = SwitchAutomationDatasetGenerator(devices: Self.devices)
        let testCase = try generator.makeCase(template: .twoActionsTwoConditions, caseIndex: 0)
        let expected = testCase.expected
        let json = try #require(expected.expectedSmartThingsRuleJSON)

        #expect(expected.expectedDeviceIDs == ["alpha_plug", "beta_lamp"])
        #expect(expected.actionCount == 2)
        #expect(expected.conditionCount == 2)
        #expect(expected.conditionTreeKind == "and")
        #expect(json.contains(#""every""#))
        #expect(json.contains(#""offset""#))
        #expect(json.contains(#""integer" : 1140"#))
        #expect(json.contains("alpha_plug"))
        #expect(json.contains("beta_lamp"))
        #expect(json.contains(#""equals""#))

        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        #expect(object is [String: Any])
    }

    @Test("range generation is deterministic and non-overlapping")
    func rangeGenerationIsDeterministicAndNonOverlapping() throws {
        let generator = SwitchAutomationDatasetGenerator(devices: Self.devices)
        let first = try generator.generateDataset(
            template: .twoActionsTwoConditions,
            range: SwitchAutomationDatasetRange(start: 0, count: 3)
        )
        let second = try generator.generateDataset(
            template: .twoActionsTwoConditions,
            range: SwitchAutomationDatasetRange(start: 3, count: 3)
        )
        let firstAgain = try generator.generateDataset(
            template: .twoActionsTwoConditions,
            range: SwitchAutomationDatasetRange(start: 0, count: 3)
        )

        #expect(first.cases.map(\.id) == firstAgain.cases.map(\.id))
        #expect(Set(first.cases.map(\.id)).isDisjoint(with: Set(second.cases.map(\.id))))
        #expect(first.manifest.caseCount == 3)
        #expect(first.traceContracts.count == 3)
        #expect(first.metricsContracts.count == 3)
    }

    @Test("template five without range produces index dataset")
    func templateFiveWithoutRangeProducesIndexDataset() throws {
        let generator = SwitchAutomationDatasetGenerator(devices: Self.devices)
        let dataset = try generator.generateDataset(template: .twoActionsTwoConditions)
        let index = generator.index(for: .twoActionsTwoConditions)

        #expect(dataset.manifest.name == "switch-automation-v1-template-5-index")
        #expect(dataset.cases.isEmpty)
        #expect(index.totalCaseCount == 576)
        #expect(index.cursorFormula.contains("caseIndex"))
    }

    @Test("writer and loader round-trip switch automation shards")
    func writerAndLoaderRoundTripSwitchAutomationShard() throws {
        let generator = SwitchAutomationDatasetGenerator(devices: Self.devices)
        let dataset = try generator.generateDataset(
            template: .oneActionOneCondition,
            range: SwitchAutomationDatasetRange(start: 0, count: 5)
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("switch-automation-round-trip-\(UUID().uuidString)", isDirectory: true)

        try EvaluationDatasetWriter().write(dataset, to: directory)
        let decoded = try EvaluationDatasetResourceLoader().loadExternalDataset(from: directory)

        #expect(decoded.manifest.name == dataset.manifest.name)
        #expect(decoded.cases.count == 5)
        #expect(decoded.cases.first?.expected.expectedSmartThingsRuleJSON == dataset.cases.first?.expected.expectedSmartThingsRuleJSON)
    }

    @Test("seed dataset decodes when exact SmartThings JSON is absent")
    func seedDatasetDecodesWithMissingExactSmartThingsJSON() throws {
        let dataset = try EvaluationDatasetResourceLoader().loadBuiltInDataset(named: "seed-v1")

        #expect(!dataset.cases.isEmpty)
        #expect(dataset.cases.first?.expected.expectedSmartThingsRuleJSON == nil)
    }

    private static let devices: [HomeCandidateRecord] = [
        switchDevice(id: "alpha_plug", name: "Alpha Plug"),
        switchDevice(id: "beta_lamp", name: "Beta Lamp"),
        switchDevice(id: "gamma_tv", name: "Gamma TV")
    ]

    private static func switchDevice(id: String, name: String) -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: id,
            displayName: name,
            deviceType: "switch",
            room: "test",
            capabilities: ["switch"],
            supportedCommands: ["switch": ["on", "off"]],
            currentState: ["switch": "off"]
        )
    }
}
