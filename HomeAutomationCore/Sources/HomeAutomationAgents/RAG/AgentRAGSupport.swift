import Foundation
import HomeAutomationCore
import HomeAutomationRAG

public struct AutomationRAGPolicyDecision: Sendable, Hashable {
    public let shouldRetrieve: Bool
    public let reasons: [String]

    public init(shouldRetrieve: Bool, reasons: [String]) {
        self.shouldRetrieve = shouldRetrieve
        self.reasons = reasons
    }
}

public enum AutomationRAGPolicy {
    public static let deterministicConfidenceThreshold: Double = 0.88

    public static func shouldRetrieve(
        for input: AutomationDraftInput,
        draftOutput: AutomationDraftOutput?
    ) -> Bool {
        decision(for: input, draftOutput: draftOutput).shouldRetrieve
    }

    public static func decision(
        for input: AutomationDraftInput,
        draftOutput: AutomationDraftOutput?
    ) -> AutomationRAGPolicyDecision {
        guard input.operation?.operation != .executeDeviceCommand else {
            return AutomationRAGPolicyDecision(shouldRetrieve: false, reasons: [])
        }
        guard let draftOutput else {
            return AutomationRAGPolicyDecision(shouldRetrieve: true, reasons: ["missingDeterministicDraft"])
        }

        var reasons: [String] = []
        if draftOutput.confidence < deterministicConfidenceThreshold {
            reasons.append("lowDraftConfidence")
        }
        if !draftOutput.unsupportedFragments.isEmpty {
            reasons.append("unsupportedFragments")
        }
        if draftOutput.trigger?.type == .device {
            reasons.append("deviceTrigger")
        }
        if containsDeviceAttribute(in: draftOutput.trigger?.condition) ||
            containsDeviceAttribute(in: draftOutput.condition) {
            reasons.append("deviceAttributeCondition")
        }
        if containsSchemaSensitiveOperator(in: draftOutput.trigger?.condition) ||
            containsSchemaSensitiveOperator(in: draftOutput.condition) {
            reasons.append("schemaSensitiveOperator")
        }
        if containsCompoundCondition(in: draftOutput.trigger?.condition) ||
            containsCompoundCondition(in: draftOutput.condition) {
            reasons.append("compoundCondition")
        }

        let uniqueReasons = stableUnique(reasons)
        return AutomationRAGPolicyDecision(
            shouldRetrieve: !uniqueReasons.isEmpty,
            reasons: uniqueReasons
        )
    }

    public static func retrievalQuery(
        for input: AutomationDraftInput,
        draftOutput: AutomationDraftOutput?,
        topK: Int = 6
    ) -> StructuredRetrievalQuery {
        let rawText = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let concepts = automationConcepts(for: input, draftOutput: draftOutput)
        let conditionOperators = operators(in: draftOutput?.trigger?.condition) +
            operators(in: draftOutput?.condition)
        let repeatHints = repeatHints(for: rawText, draftOutput: draftOutput)
        let keywordTerms = concepts + conditionOperators + repeatHints + [
            "automationCreation",
            "SmartThings",
            "rule",
            "every",
            "if",
            "command"
        ]

        return StructuredRetrievalQuery(
            rawText: rawText,
            semanticText: QueryReformulator.reformulate(
                rawText: rawText,
                hints: nil,
                automationConcepts: concepts,
                conditionOperators: conditionOperators,
                repeatHints: repeatHints
            ),
            keywordTerms: keywordTerms,
            metadataFilter: MetadataFilter(
                requiredTags: ["operation": HomeAutomationOperationKind.automationCreation.rawValue]
            ),
            operation: .automationCreation,
            automationConcepts: concepts,
            conditionOperators: conditionOperators,
            repeatHints: repeatHints,
            strategy: .hybrid(alpha: 0.35),
            minScore: 0,
            topK: topK
        )
    }

    private static func automationConcepts(
        for input: AutomationDraftInput,
        draftOutput: AutomationDraftOutput?
    ) -> [String] {
        var concepts = ["automationCreation"]
        if let operation = input.operation?.operation {
            concepts.append(operation.rawValue)
        }
        if let trigger = draftOutput?.trigger {
            switch trigger.type {
            case .schedule:
                concepts.append(contentsOf: ["schedule", "scheduleTrigger"])
            case .device:
                concepts.append(contentsOf: ["deviceTrigger", "triggerPolicy"])
            }
        }
        if let actionCount = draftOutput?.actionDescriptions.count, actionCount > 1 {
            concepts.append("multipleActions")
        }
        if containsDeviceAttribute(in: draftOutput?.trigger?.condition) ||
            containsDeviceAttribute(in: draftOutput?.condition) {
            concepts.append(contentsOf: ["deviceAttribute", "comparisonCondition"])
        }
        if containsCompoundCondition(in: draftOutput?.trigger?.condition) ||
            containsCompoundCondition(in: draftOutput?.condition) {
            concepts.append(contentsOf: ["compoundCondition", "conditionTree"])
        }
        if draftOutput?.unsupportedFragments.isEmpty == false {
            concepts.append("unsupportedFragment")
        }
        return stableUnique(concepts)
    }

    private static func repeatHints(
        for rawText: String,
        draftOutput: AutomationDraftOutput?
    ) -> [String] {
        var hints: [String] = []
        if let repeatRule = draftOutput?.trigger?.repeatRule {
            hints.append(repeatRule)
        }
        let normalized = rawText
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let phraseHints = [
            "every day",
            "everyday",
            "daily",
            "weekdays",
            "weekends",
            "monday",
            "tuesday",
            "wednesday",
            "thursday",
            "friday",
            "saturday",
            "sunday",
            "minutes",
            "hours"
        ]
        hints.append(contentsOf: phraseHints.filter { normalized.contains($0) })
        return stableUnique(hints)
    }

    private static func containsDeviceAttribute(in condition: AutomationConditionOutput?) -> Bool {
        guard let condition else { return false }
        if condition.left?.type == .deviceAttribute || condition.right?.type == .deviceAttribute {
            return true
        }
        return condition.children.contains { containsDeviceAttribute(in: $0) }
    }

    private static func containsSchemaSensitiveOperator(in condition: AutomationConditionOutput?) -> Bool {
        guard let condition else { return false }
        if let operatorName = condition.operatorName,
           [.between, .changes].contains(operatorName) {
            return true
        }
        return condition.children.contains { containsSchemaSensitiveOperator(in: $0) }
    }

    private static func containsCompoundCondition(in condition: AutomationConditionOutput?) -> Bool {
        guard let condition else { return false }
        if [.and, .or, .not].contains(condition.type) {
            return true
        }
        return condition.children.contains { containsCompoundCondition(in: $0) }
    }

    private static func operators(in condition: AutomationConditionOutput?) -> [String] {
        guard let condition else { return [] }
        var values: [String] = []
        switch condition.type {
        case .and, .or, .not:
            values.append(condition.type.rawValue)
        case .comparison:
            if let operatorName = condition.operatorName {
                values.append(operatorName.rawValue)
            }
        }
        for child in condition.children {
            values.append(contentsOf: operators(in: child))
        }
        return stableUnique(values)
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }
}

enum AgentRAGSupport {
    static func nluInput(
        _ input: String,
        task: String,
        contextRetriever: ContextRetriever?
    ) async -> String {
        guard let contextRetriever else { return input }
        let examples = await contextRetriever.retrieve(
            query: input,
            topK: 3,
            filter: MetadataFilter(source: .nlDataset)
        )
        guard !examples.isEmpty else { return input }

        let fewShot = examples
            .map { $0.chunk.content }
            .joined(separator: "\n")

        return """
        Relevant prior smart-home examples for \(task):
        \(fewShot)

        User command:
        \(input)
        """
    }

    static func automationInput(
        _ input: AutomationDraftInput,
        draftOutput: AutomationDraftOutput?,
        contextRetriever: ContextRetriever?
    ) async -> String {
        let commandText = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let contextRetriever,
              AutomationRAGPolicy.shouldRetrieve(for: input, draftOutput: draftOutput) else {
            return commandText
        }

        let query = AutomationRAGPolicy.retrievalQuery(for: input, draftOutput: draftOutput)
        let chunks = await contextRetriever.retrieve(query)
        guard !chunks.isEmpty else {
            return commandText
        }

        let context = chunks.map { scored in
            let metadata = scored.chunk.metadata
                .keys
                .sorted()
                .map { "\($0)=\(scored.chunk.metadata[$0] ?? "")" }
                .joined(separator: ", ")
            return """
            [\(scored.chunk.source.rawValue)] \(scored.chunk.id) score=\(String(format: "%.3f", scored.score))
            \(scored.chunk.content)
            metadata: \(metadata)
            """
        }
        .joined(separator: "\n\n")

        return """
        Relevant SmartThings automation knowledge:
        \(context)

        User automation command:
        \(commandText)
        """
    }

    static func stableUnique<T>(
        _ values: [T],
        by key: (T) -> String
    ) -> [T] {
        var seen = Set<String>()
        var result: [T] = []
        for value in values {
            let id = key(value)
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            result.append(value)
        }
        return result
    }
}
