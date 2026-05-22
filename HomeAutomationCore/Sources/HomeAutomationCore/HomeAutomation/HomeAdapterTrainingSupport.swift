import Foundation

public struct HomeAdapterTrainingExample: Sendable, Codable, Hashable {
    public let id: String
    public let source: String
    public let input: String
    public let expectedDraft: HomeCommandDraft
    public let metadata: [String: String]

    public init(
        id: String,
        source: String,
        input: String,
        expectedDraft: HomeCommandDraft,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.source = source
        self.input = input
        self.expectedDraft = expectedDraft
        self.metadata = metadata
    }
}

public enum HomeAdapterTrainingTask: String, Sendable, Codable, Hashable {
    case draftGeneration
    case operationRouting
    case semanticNLU
    case slotExtraction
    case riskClassification
}

public struct HomeAdapterTaskTrainingExample: Sendable, Codable, Hashable {
    public let id: String
    public let source: String
    public let task: HomeAdapterTrainingTask
    public let input: String
    public let expectedOutputJSON: String
    public let metadata: [String: String]

    public init(
        id: String,
        source: String,
        task: HomeAdapterTrainingTask,
        input: String,
        expectedOutputJSON: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.source = source
        self.task = task
        self.input = input
        self.expectedOutputJSON = expectedOutputJSON
        self.metadata = metadata
    }
}

public struct HomeAdapterEvaluationCase: Sendable, Codable, Hashable {
    public let id: String
    public let input: String
    public let expectedDraft: HomeCommandDraft
    public let tags: [String]

    public init(
        id: String,
        input: String,
        expectedDraft: HomeCommandDraft,
        tags: [String] = []
    ) {
        self.id = id
        self.input = input
        self.expectedDraft = expectedDraft
        self.tags = tags
    }
}

public struct HomeAdapterEvaluationResult: Sendable, Codable, Hashable {
    public let totalCaseCount: Int
    public let validCaseCount: Int
    public let missingFieldCaseIDs: [String]
    public let holdoutCoverageTags: [String]

    public init(
        totalCaseCount: Int,
        validCaseCount: Int,
        missingFieldCaseIDs: [String],
        holdoutCoverageTags: [String]
    ) {
        self.totalCaseCount = totalCaseCount
        self.validCaseCount = validCaseCount
        self.missingFieldCaseIDs = missingFieldCaseIDs
        self.holdoutCoverageTags = holdoutCoverageTags
    }

    public var isPassing: Bool {
        totalCaseCount > 0 && validCaseCount == totalCaseCount && !holdoutCoverageTags.isEmpty
    }
}

public struct HomeAdapterCompatibilityManifest: Sendable, Codable, Hashable {
    public let runtimeVersion: String
    public let schemaVersion: String
    public let minimumDatasetCount: Int
    public let notes: [String]

    public init(
        runtimeVersion: String,
        schemaVersion: String,
        minimumDatasetCount: Int,
        notes: [String] = []
    ) {
        self.runtimeVersion = runtimeVersion
        self.schemaVersion = schemaVersion
        self.minimumDatasetCount = minimumDatasetCount
        self.notes = notes
    }

    public static let current = HomeAdapterCompatibilityManifest(
        runtimeVersion: "home-automation-foundation-model-adapter-v1",
        schemaVersion: "HomeCommandDraft.v1",
        minimumDatasetCount: 100,
        notes: [
            "Adapters specialize draft generation only.",
            "RAG, tools, safety validation, and parameter validation remain required."
        ]
    )
}

public enum HomeAdapterTrainingExporter {
    public static func makeTrainingExamples(
        limit: Int? = nil,
        failureCases: [HomeAdapterTrainingExample] = []
    ) -> [HomeAdapterTrainingExample] {
        var examples = generatedDatasetExamples()
        examples.append(contentsOf: bixbyExamples(limit: limit))
        examples.append(contentsOf: failureCases)

        guard let limit else { return examples }
        return Array(examples.prefix(limit))
    }

    public static func makeJSONL(
        limit: Int? = nil,
        failureCases: [HomeAdapterTrainingExample] = []
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try makeTrainingExamples(limit: limit, failureCases: failureCases)
            .map { example in
                let data = try encoder.encode(example)
                return String(data: data, encoding: .utf8) ?? ""
            }
            .joined(separator: "\n")
    }

    public static func makeTaskTrainingExamples(
        limit: Int? = nil,
        includeDrafts: Bool = true,
        includeNLU: Bool = true,
        failureCases: [HomeAdapterTrainingExample] = []
    ) throws -> [HomeAdapterTaskTrainingExample] {
        var records: [HomeAdapterTaskTrainingExample] = []
        if includeDrafts {
            records.append(contentsOf: try makeTrainingExamples(limit: limit, failureCases: failureCases).map(taskExample(from:)))
        }
        if includeNLU {
            records.append(contentsOf: try nluExamples(limit: limit))
        }
        guard let limit else { return records }
        return Array(records.prefix(limit))
    }

    public static func makeTaskJSONL(
        limit: Int? = nil,
        includeDrafts: Bool = true,
        includeNLU: Bool = true,
        failureCases: [HomeAdapterTrainingExample] = []
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try makeTaskTrainingExamples(
            limit: limit,
            includeDrafts: includeDrafts,
            includeNLU: includeNLU,
            failureCases: failureCases
        )
        .map { example in
            let data = try encoder.encode(example)
            return String(data: data, encoding: .utf8) ?? ""
        }
        .joined(separator: "\n")
    }

    public static func evaluateHoldout(_ cases: [HomeAdapterEvaluationCase]) -> HomeAdapterEvaluationResult {
        let invalidIDs = cases.compactMap { item -> String? in
            guard !item.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.expectedDraft.capability != nil,
                  item.expectedDraft.command != nil else {
                return item.id
            }
            return nil
        }
        let tags = Array(Set(cases.flatMap(\.tags))).sorted()
        return HomeAdapterEvaluationResult(
            totalCaseCount: cases.count,
            validCaseCount: cases.count - invalidIDs.count,
            missingFieldCaseIDs: invalidIDs,
            holdoutCoverageTags: tags
        )
    }

    private static func generatedDatasetExamples() -> [HomeAdapterTrainingExample] {
        HomeAutomationKnowledgeBase.generatedDatasetCommands().map { example in
            HomeAdapterTrainingExample(
                id: "generated.\(example.id)",
                source: "generatedDataset",
                input: example.text,
                expectedDraft: example.commandDraft(targetDeviceID: example.expected.targetDescription),
                metadata: [
                    "language": example.language,
                    "deviceType": example.deviceType,
                    "capability": example.capability,
                    "command": example.command,
                    "risk": example.riskLevel
                ]
            )
        }
    }

    private static func taskExample(from example: HomeAdapterTrainingExample) throws -> HomeAdapterTaskTrainingExample {
        HomeAdapterTaskTrainingExample(
            id: example.id,
            source: example.source,
            task: .draftGeneration,
            input: example.input,
            expectedOutputJSON: try encodedOutput(example.expectedDraft),
            metadata: example.metadata
        )
    }

    private static func nluExamples(limit: Int?) throws -> [HomeAdapterTaskTrainingExample] {
        let commands = limit.map { Array(HomeAutomationKnowledgeBase.generatedDatasetCommands().prefix($0)) } ??
            HomeAutomationKnowledgeBase.generatedDatasetCommands()
        return try commands.flatMap { example in
            try nluExamples(for: example)
        }
    }

    private static func nluExamples(for example: HomeGeneratedCommandExample) throws -> [HomeAdapterTaskTrainingExample] {
        let source = "generatedDataset"
        let metadata = [
            "language": example.language,
            "deviceType": example.deviceType,
            "capability": example.capability,
            "command": example.command,
            "risk": example.riskLevel
        ]

        return [
            HomeAdapterTaskTrainingExample(
                id: "nlu.operation.\(example.id)",
                source: source,
                task: .operationRouting,
                input: example.text,
                expectedOutputJSON: try encodedOutput(
                    HomeOperationRoutingResult(
                        operation: HomeOperationDetectionResult(
                            domain: commandDomain(for: example.expected.domain),
                            operation: example.automationIntent == .unsupported ? .unsupported : .executeDeviceCommand,
                            confidence: 1,
                            reason: "Dataset label"
                        ),
                        language: HomeLanguageDetectionResult(
                            languageCode: example.language,
                            isMixedLanguage: false,
                            confidence: 1,
                            unsupportedLanguageLikely: false
                        ),
                        domain: HomeDomainClassificationResult(
                            domain: commandDomain(for: example.expected.domain),
                            confidence: 1
                        )
                    )
                ),
                metadata: metadata
            ),
            HomeAdapterTaskTrainingExample(
                id: "nlu.semantic.\(example.id)",
                source: source,
                task: .semanticNLU,
                input: example.text,
                expectedOutputJSON: try encodedOutput(
                    HomeSemanticNLUResult(
                        intent: HomeIntentFamilyResult(topFamilies: [intentFamily(for: example.automationIntent)], confidence: 1),
                        deviceType: HomeDeviceTypeResult(deviceTypes: [example.deviceType], confidence: 1)
                    )
                ),
                metadata: metadata
            ),
            HomeAdapterTaskTrainingExample(
                id: "nlu.slots.\(example.id)",
                source: source,
                task: .slotExtraction,
                input: example.text,
                expectedOutputJSON: try encodedOutput(
                    HomeSlotExtractionResult(
                        rooms: example.room.isEmpty ? [] : [example.room],
                        deviceNicknames: example.deviceName.isEmpty ? [] : [example.deviceName],
                        values: example.parameters.map(\.resolvedParameter).map {
                            HomeExtractedSlot(
                                name: $0.name,
                                rawValue: $0.value ?? $0.numericValue.map { String($0) } ?? "",
                                numericValue: $0.numericValue,
                                unit: $0.unit,
                                confidence: $0.confidence
                            )
                        },
                        modes: example.parameters.compactMap(\.value),
                        confidence: 1
                    )
                ),
                metadata: metadata
            ),
            HomeAdapterTaskTrainingExample(
                id: "nlu.risk.\(example.id)",
                source: source,
                task: .riskClassification,
                input: example.text,
                expectedOutputJSON: try encodedOutput(
                    HomeRiskClassificationResult(
                        riskLevel: example.risk,
                        requiresConfirmation: example.expected.requiresConfirmation,
                        reason: "Dataset label",
                        confidence: 1
                    )
                ),
                metadata: metadata
            )
        ]
    }

    private static func commandDomain(for domainString: String) -> HomeAutomationCommandDomain {
        switch domainString {
        case "homeAutomation":
            return .homeAutomation
        case "appNavigation":
            return .appNavigation
        case "generalQuestion":
            return .generalQuestion
        default:
            return .unsupported
        }
    }

    private static func intentFamily(for intent: HomeAutomationIntent) -> HomeAutomationIntentFamily {
        switch intent {
        case .turnOn, .turnOff:
            return .power
        case .setValue, .increaseValue, .decreaseValue:
            return .brightness
        case .getStatus:
            return .statusQuery
        case .start, .stop, .pause, .resume:
            return .applianceCycle
        case .open, .close:
            return .openClose
        case .lock, .unlock:
            return .lockUnlock
        case .runRoutine:
            return .routine
        case .unsupported:
            return .unsupported
        }
    }

    private static func encodedOutput(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func bixbyExamples(limit: Int?) -> [HomeAdapterTrainingExample] {
        let commands = limit.map { Array(HomeBixbyCommandCatalog.commands.prefix($0)) } ?? HomeBixbyCommandCatalog.commands
        return commands.enumerated().map { index, command in
            HomeAdapterTrainingExample(
                id: "bixby.\(index)",
                source: "bixbyCatalog",
                input: HomeBixbyCommandCatalog.alternatives(for: command).first ?? command.hint,
                expectedDraft: HomeCommandDraft(
                    intent: command.method == "GET" ? .getStatus : .setValue,
                    targetDeviceID: "bedroom_light",
                    capability: command.capability,
                    command: command.method == "GET" ? "getStatus" : command.action,
                    parameters: command.enumeration.map {
                        [HomeResolvedParameter(name: "mode", value: $0, confidence: 1)]
                    } ?? [],
                    needsClarification: false,
                    requiresConfirmation: false,
                    confidence: 1
                ),
                metadata: [
                    "capability": command.capability,
                    "action": command.action,
                    "method": command.method,
                    "accessLevel": command.accessLevel
                ]
            )
        }
    }
}
