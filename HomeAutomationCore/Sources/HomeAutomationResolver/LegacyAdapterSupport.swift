import Foundation
import HomeAutomationCore

public struct LegacyAdapterTrainingExample: Sendable, Codable, Equatable {
    public let prompt: String
    public let intent: String
    public let deviceType: String
    public let capability: String
    public let command: String
    public let requiresConfirmation: Bool
}

public enum LegacyAdapterTrainingExporter {
    public static func makeTrainingExamples(limit: Int? = nil) -> [LegacyAdapterTrainingExample] {
        let commands = HomeAutomationKnowledgeBase.generatedDatasetCommands()
        let selected = limit.map { Array(commands.prefix($0)) } ?? commands
        return selected.map { example in
            LegacyAdapterTrainingExample(
                prompt: example.text,
                intent: example.intent,
                deviceType: example.deviceType,
                capability: example.capability,
                command: example.command,
                requiresConfirmation: example.expected.requiresConfirmation
            )
        }
    }

    public static func makeJSONL(limit: Int? = nil) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return makeTrainingExamples(limit: limit).compactMap { example in
            guard let data = try? encoder.encode(example) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        .joined(separator: "\n")
    }
}

public struct LegacyAdapterCompatibility: Sendable, Codable, Equatable {
    public let adapterName: String
    public let expectedSystemModelVersion: String
    public let installedSystemModelVersion: String

    public var isCompatible: Bool {
        expectedSystemModelVersion == installedSystemModelVersion
    }

    public init(
        adapterName: String,
        expectedSystemModelVersion: String,
        installedSystemModelVersion: String
    ) {
        self.adapterName = adapterName
        self.expectedSystemModelVersion = expectedSystemModelVersion
        self.installedSystemModelVersion = installedSystemModelVersion
    }
}

public enum LegacyDeploymentChecklist {
    public static let items = [
        "Verify SystemLanguageModel.default.isAvailable before live FM resolution.",
        "Provide HOME_AUTOMATION_ADAPTER_FILE or HOME_AUTOMATION_ADAPTER_NAME for adapter-backed runs.",
        "Version-match adapters to the installed system model before enabling them.",
        "Keep rule-based fallback enabled for lights, locks, temperature, status, and routines.",
        "Review metrics JSON for candidate strategy, false-execution tracking, and confirmation outcomes."
    ]
}
