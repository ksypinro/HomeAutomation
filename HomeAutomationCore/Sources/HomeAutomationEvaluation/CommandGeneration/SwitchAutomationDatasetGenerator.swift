import Foundation
import HomeAutomationCore

public enum SwitchAutomationTemplate: Int, Sendable, Codable, Hashable, CaseIterable {
    case oneActionSchedule = 1
    case twoActionSchedule = 2
    case oneActionOneCondition = 3
    case oneActionTwoConditions = 4
    case twoActionsTwoConditions = 5

    public var datasetName: String {
        switch self {
        case .oneActionSchedule:
            return "switch-automation-v1-template-1"
        case .twoActionSchedule:
            return "switch-automation-v1-template-2"
        case .oneActionOneCondition:
            return "switch-automation-v1-template-3"
        case .oneActionTwoConditions:
            return "switch-automation-v1-template-4"
        case .twoActionsTwoConditions:
            return "switch-automation-v1-template-5"
        }
    }

    public var actionSlotCount: Int {
        switch self {
        case .oneActionSchedule, .oneActionOneCondition, .oneActionTwoConditions:
            return 1
        case .twoActionSchedule, .twoActionsTwoConditions:
            return 2
        }
    }

    public var conditionSlotCount: Int {
        switch self {
        case .oneActionSchedule, .twoActionSchedule:
            return 0
        case .oneActionOneCondition:
            return 1
        case .oneActionTwoConditions, .twoActionsTwoConditions:
            return 2
        }
    }
}

public struct SwitchAutomationDatasetRange: Sendable, Codable, Hashable {
    public let start: Int
    public let count: Int

    public init(start: Int, count: Int) {
        self.start = start
        self.count = count
    }
}

public struct SwitchAutomationDatasetIndex: Sendable, Codable, Hashable {
    public let datasetName: String
    public let template: Int
    public let switchDeviceCount: Int
    public let totalCaseCount: Int
    public let actionCombinationCount: Int
    public let conditionCombinationCount: Int
    public let cursorFormula: String

    public init(
        datasetName: String,
        template: Int,
        switchDeviceCount: Int,
        totalCaseCount: Int,
        actionCombinationCount: Int,
        conditionCombinationCount: Int,
        cursorFormula: String
    ) {
        self.datasetName = datasetName
        self.template = template
        self.switchDeviceCount = switchDeviceCount
        self.totalCaseCount = totalCaseCount
        self.actionCombinationCount = actionCombinationCount
        self.conditionCombinationCount = conditionCombinationCount
        self.cursorFormula = cursorFormula
    }
}

public struct SwitchAutomationDatasetGenerator: Sendable {
    public let devices: [HomeCandidateRecord]
    public let generatedAt: String

    private let compiler = SmartThingsRuleCompiler()

    public init(
        devices: [HomeCandidateRecord] = MockHomeDeviceRegistry.defaultDevices,
        generatedAt: String = "2026-08-08T00:00:00Z"
    ) {
        self.devices = devices
            .filter(Self.isSwitchCapable)
            .sorted { lhs, rhs in
                if lhs.id == rhs.id { return lhs.displayName < rhs.displayName }
                return lhs.id < rhs.id
            }
        self.generatedAt = generatedAt
    }

    public static func isSwitchCapable(_ device: HomeCandidateRecord) -> Bool {
        let commands = Set(device.supportedCommands["switch"] ?? [])
        return commands.contains("on") && commands.contains("off")
    }

    public func totalCaseCount(for template: SwitchAutomationTemplate) -> Int {
        actionCombinationCount(slots: template.actionSlotCount)
            * conditionCombinationCount(slots: template.conditionSlotCount)
    }

    public func index(for template: SwitchAutomationTemplate) -> SwitchAutomationDatasetIndex {
        SwitchAutomationDatasetIndex(
            datasetName: template == .twoActionsTwoConditions ? "switch-automation-v1-template-5-index" : template.datasetName,
            template: template.rawValue,
            switchDeviceCount: devices.count,
            totalCaseCount: totalCaseCount(for: template),
            actionCombinationCount: actionCombinationCount(slots: template.actionSlotCount),
            conditionCombinationCount: conditionCombinationCount(slots: template.conditionSlotCount),
            cursorFormula: "caseIndex = actionCombinationIndex * conditionCombinationCount + conditionCombinationIndex; action and condition combination indexes are deterministic row-major ordered choices over commands, statuses, and switch-capable devices"
        )
    }

    public func makeIndexDataset(for template: SwitchAutomationTemplate) -> GeneratedEvaluationDataset {
        let name = template == .twoActionsTwoConditions ? "switch-automation-v1-template-5-index" : "\(template.datasetName)-index"
        return GeneratedEvaluationDataset(
            manifest: EvaluationDatasetManifest(
                name: name,
                version: "1.0.0",
                generatedAt: generatedAt,
                generatorVersion: "switch-automation-dataset-generator-v1",
                fixtureCount: 1,
                caseCount: 0,
                commandsPerFixture: 0,
                generationMode: EvaluationCommandGenerationMode.template.rawValue,
                randomSeed: 20260808,
                validationStatus: "passed"
            ),
            fixtures: [fixture(notes: "Index-only shard for \(template.datasetName). Total cases: \(totalCaseCount(for: template)).")],
            cases: [],
            traceContracts: [],
            metricsContracts: []
        )
    }

    public func generateDataset(
        template: SwitchAutomationTemplate,
        range: SwitchAutomationDatasetRange? = nil
    ) throws -> GeneratedEvaluationDataset {
        if template == .twoActionsTwoConditions, range == nil {
            return makeIndexDataset(for: template)
        }

        let total = totalCaseCount(for: template)
        let resolvedRange = range ?? SwitchAutomationDatasetRange(start: 0, count: total)
        guard resolvedRange.start >= 0,
              resolvedRange.count >= 0,
              resolvedRange.start <= total,
              resolvedRange.start + resolvedRange.count <= total else {
            throw SwitchAutomationDatasetGeneratorError.invalidRange(
                start: resolvedRange.start,
                count: resolvedRange.count,
                total: total
            )
        }

        let cases = try (resolvedRange.start..<(resolvedRange.start + resolvedRange.count)).map {
            try makeCase(template: template, caseIndex: $0)
        }
        let manifestName = range.map {
            "\(template.datasetName)-range-\($0.start)-\($0.count)"
        } ?? template.datasetName
        let fixture = fixture(notes: "Switch-capable devices only; action-condition overlap allowed; no repeated action-slot or condition-slot devices.")
        return GeneratedEvaluationDataset(
            manifest: EvaluationDatasetManifest(
                name: manifestName,
                version: "1.0.0",
                generatedAt: generatedAt,
                generatorVersion: "switch-automation-dataset-generator-v1",
                fixtureCount: 1,
                caseCount: cases.count,
                commandsPerFixture: cases.count,
                generationMode: EvaluationCommandGenerationMode.template.rawValue,
                randomSeed: 20260808,
                validationStatus: "passed"
            ),
            fixtures: [fixture],
            cases: cases,
            traceContracts: ExpectedTraceContractFactory().makeContracts(for: cases),
            metricsContracts: ExpectedMetricsContractFactory().makeContracts(for: cases)
        )
    }

    public func makeCase(
        template: SwitchAutomationTemplate,
        caseIndex: Int
    ) throws -> GeneratedEvaluationCase {
        let total = totalCaseCount(for: template)
        guard caseIndex >= 0, caseIndex < total else {
            throw SwitchAutomationDatasetGeneratorError.invalidCaseIndex(caseIndex, total: total)
        }

        let conditionCount = conditionCombinationCount(slots: template.conditionSlotCount)
        let actionIndex = caseIndex / conditionCount
        let conditionIndex = caseIndex % conditionCount
        let actions = actionChoices(slots: template.actionSlotCount, index: actionIndex)
        let conditions = conditionChoices(slots: template.conditionSlotCount, index: conditionIndex)
        let actionDescriptions = actions.map { "\($0.phrase) \($0.device.displayName)" }
        let input = inputText(actions: actions, conditions: conditions)
        let plan = try creationPlan(
            name: "Switch automation template \(template.rawValue) case \(caseIndex)",
            actionDescriptions: actionDescriptions,
            actions: actions,
            conditions: conditions
        )
        let expectedJSON = try compiler.compile(plan).jsonString
        let actionDeviceIDs = actions.map(\.device.id)
        let conditionDeviceIDs = conditions.map(\.device.id)
        let allDeviceIDs = stableUnique(actionDeviceIDs + conditionDeviceIDs)
        let smartThingsMarkers = stableUnique(allDeviceIDs + ["\"every\"", "\"command\""] + (conditions.isEmpty ? [] : ["\"equals\""]))
        let caseID = "switch-t\(template.rawValue)-\(String(format: "%010d", caseIndex))"

        return GeneratedEvaluationCase(
            id: caseID,
            fixtureID: Self.fixtureID,
            suite: "switch-automation-exhaustive",
            tags: [
                "automation",
                "switch-automation",
                "template:\(template.rawValue)",
                "actions:\(template.actionSlotCount)",
                "conditions:\(template.conditionSlotCount)",
                "schedule:daily-1900"
            ],
            input: input,
            canonicalCommandID: "switch-template-\(template.rawValue)",
            expected: ExpectedResolvedOutput(
                operation: .automationCreation,
                domain: .homeAutomation,
                allowedOutcome: .drafted,
                expectedDeviceIDs: allDeviceIDs,
                targetDeviceID: actions.first?.device.id,
                capability: "switch",
                command: actions.first?.command,
                actionCount: actions.count,
                conditionCount: conditions.count,
                conditionTreeKind: conditions.count <= 1 ? (conditions.isEmpty ? nil : "leaf") : "and",
                smartThingsJSONContains: smartThingsMarkers,
                expectedSmartThingsRuleJSON: expectedJSON
            ),
            traceContractID: "\(caseID).trace",
            metricsContractID: "\(caseID).metrics"
        )
    }

    private static let fixtureID = "switch-automation-all-switch-capable"

    private func fixture(notes: String) -> GeneratedEvaluationFixture {
        GeneratedEvaluationFixture(
            id: Self.fixtureID,
            name: "All switch-capable mock registry devices",
            category: "switch-automation-exhaustive",
            devices: devices,
            notes: notes
        )
    }

    private func actionCombinationCount(slots: Int) -> Int {
        switch slots {
        case 0:
            return 1
        case 1:
            return devices.count * Self.commands.count
        case 2:
            return devices.count * Self.commands.count * max(devices.count - 1, 0) * Self.commands.count
        default:
            return 0
        }
    }

    private func conditionCombinationCount(slots: Int) -> Int {
        switch slots {
        case 0:
            return 1
        case 1:
            return devices.count * Self.statuses.count
        case 2:
            return devices.count * Self.statuses.count * max(devices.count - 1, 0) * Self.statuses.count
        default:
            return 0
        }
    }

    private func actionChoices(slots: Int, index: Int) -> [SwitchActionChoice] {
        guard slots > 0 else { return [] }
        if slots == 1 {
            let commandIndex = index % Self.commands.count
            let deviceIndex = index / Self.commands.count
            return [SwitchActionChoice(device: devices[deviceIndex], command: Self.commands[commandIndex])]
        }

        let secondCommandIndex = index % Self.commands.count
        var remaining = index / Self.commands.count
        let secondOrdinal = remaining % max(devices.count - 1, 1)
        remaining /= max(devices.count - 1, 1)
        let firstCommandIndex = remaining % Self.commands.count
        let firstDeviceIndex = remaining / Self.commands.count
        let secondDeviceIndex = deviceIndex(excluding: firstDeviceIndex, ordinal: secondOrdinal)
        return [
            SwitchActionChoice(device: devices[firstDeviceIndex], command: Self.commands[firstCommandIndex]),
            SwitchActionChoice(device: devices[secondDeviceIndex], command: Self.commands[secondCommandIndex])
        ]
    }

    private func conditionChoices(slots: Int, index: Int) -> [SwitchConditionChoice] {
        guard slots > 0 else { return [] }
        if slots == 1 {
            let statusIndex = index % Self.statuses.count
            let deviceIndex = index / Self.statuses.count
            return [SwitchConditionChoice(device: devices[deviceIndex], status: Self.statuses[statusIndex])]
        }

        let secondStatusIndex = index % Self.statuses.count
        var remaining = index / Self.statuses.count
        let secondOrdinal = remaining % max(devices.count - 1, 1)
        remaining /= max(devices.count - 1, 1)
        let firstStatusIndex = remaining % Self.statuses.count
        let firstDeviceIndex = remaining / Self.statuses.count
        let secondDeviceIndex = deviceIndex(excluding: firstDeviceIndex, ordinal: secondOrdinal)
        return [
            SwitchConditionChoice(device: devices[firstDeviceIndex], status: Self.statuses[firstStatusIndex]),
            SwitchConditionChoice(device: devices[secondDeviceIndex], status: Self.statuses[secondStatusIndex])
        ]
    }

    private func deviceIndex(excluding excluded: Int, ordinal: Int) -> Int {
        ordinal >= excluded ? ordinal + 1 : ordinal
    }

    private func inputText(
        actions: [SwitchActionChoice],
        conditions: [SwitchConditionChoice]
    ) -> String {
        let actionText = actions.map { "\($0.phrase) \($0.device.displayName)" }.joined(separator: " and ")
        let conditionText = conditions.map { "\($0.device.displayName) is \($0.status)" }.joined(separator: " and ")
        if conditionText.isEmpty {
            return "\(actionText) everyday at 7.00PM"
        }
        return "\(actionText) everyday at 7.00PM if \(conditionText)"
    }

    private func creationPlan(
        name: String,
        actionDescriptions: [String],
        actions: [SwitchActionChoice],
        conditions: [SwitchConditionChoice]
    ) throws -> HomeAutomationCreationPlan {
        let ruleDraft = HomeAutomationRuleDraft(
            name: name,
            trigger: .schedule(HomeAutomationScheduleTrigger(
                repeatRule: .everyDay,
                timeOfDay: HomeAutomationTimeOfDay(hour: 19, minute: 0)
            )),
            condition: conditionTree(conditions),
            actionDescriptions: actionDescriptions,
            confidence: 1.0
        )
        let resolvedActions = actions.map { action in
            HomeAutomationResolvedAction(
                originalText: "\(action.phrase) \(action.device.displayName)",
                draft: HomeCommandDraft(
                    intent: action.command == "on" ? .turnOn : .turnOff,
                    targetDeviceID: action.device.id,
                    capability: "switch",
                    command: action.command,
                    needsClarification: false,
                    requiresConfirmation: false,
                    confidence: 1.0
                ),
                device: action.device,
                confidence: 1.0
            )
        }
        return HomeAutomationCreationPlan(
            name: name,
            ruleDraft: ruleDraft,
            resolvedActions: resolvedActions,
            smartThingsRuleJSON: nil,
            requiresConfirmation: false,
            unsupportedCompilationReason: nil
        )
    }

    private func conditionTree(_ conditions: [SwitchConditionChoice]) -> HomeAutomationCondition? {
        let leaves = conditions.map { condition in
            HomeAutomationCondition.comparison(HomeAutomationComparisonCondition(
                left: .deviceAttribute(
                    description: "\(condition.device.displayName) is \(condition.status)",
                    deviceID: condition.device.id,
                    capability: "switch",
                    attribute: "switch"
                ),
                operatorName: .equals,
                right: .literalString(condition.status),
                triggerPolicy: .never
            ))
        }
        if leaves.isEmpty { return nil }
        if leaves.count == 1 { return leaves[0] }
        return .and(leaves)
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    private static let commands = ["on", "off"]
    private static let statuses = ["on", "off"]
}

public enum SwitchAutomationDatasetGeneratorError: Error, Sendable, LocalizedError, Equatable {
    case invalidRange(start: Int, count: Int, total: Int)
    case invalidCaseIndex(Int, total: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidRange(let start, let count, let total):
            return "Invalid switch automation dataset range start=\(start) count=\(count); total=\(total)"
        case .invalidCaseIndex(let index, let total):
            return "Invalid switch automation case index \(index); total=\(total)"
        }
    }
}

private struct SwitchActionChoice: Sendable, Hashable {
    let device: HomeCandidateRecord
    let command: String

    var phrase: String {
        command == "on" ? "Turn on" : "Turn off"
    }
}

private struct SwitchConditionChoice: Sendable, Hashable {
    let device: HomeCandidateRecord
    let status: String
}
