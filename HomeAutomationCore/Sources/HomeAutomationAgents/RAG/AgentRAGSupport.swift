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

public enum AutomationRAGSubproblem: String, Sendable, Hashable, Codable, CaseIterable {
    case operationRouting
    case draftExtraction
    case conditionGrammar
    case compilerSchemaGrounding

    public var source: KnowledgeSource {
        switch self {
        case .operationRouting:
            return .automationPattern
        case .draftExtraction:
            return .automationRuleExample
        case .conditionGrammar:
            return .automationConditionOperator
        case .compilerSchemaGrounding:
            return .smartThingsRuleSchema
        }
    }

    var queryTerms: [String] {
        switch self {
        case .operationRouting:
            return ["operation routing", "automation creation", "schedule automation", "device trigger"]
        case .draftExtraction:
            return ["draft extraction", "actionDescriptions", "trigger", "condition"]
        case .conditionGrammar:
            return ["condition grammar", "and", "or", "not", "between", "changes"]
        case .compilerSchemaGrounding:
            return ["SmartThings schema", "every specific", "if then else", "command", "trigger"]
        }
    }

    var semanticWeight: Float {
        switch self {
        case .operationRouting:
            return 0.25
        case .draftExtraction:
            return 0.45
        case .conditionGrammar, .compilerSchemaGrounding:
            return 0.30
        }
    }

    func retrievalStrategy(topK: Int = 3) -> AgentRetrievalStrategy {
        AgentRetrievalStrategy(
            name: "automationDraft.hybrid.\(rawValue)",
            agentID: .automationDraft,
            purpose: "Retrieve SmartThings automation knowledge for the \(rawValue) draft extraction subproblem.",
            source: source,
            requiredTags: ["operation": HomeAutomationOperationKind.automationCreation.rawValue],
            topK: topK,
            minScore: 0,
            ranking: .hybrid(alpha: semanticWeight),
            fallbackBehavior: .skip
        )
    }
}

public struct AutomationRAGSubproblemQuery: Sendable, Hashable {
    public let subproblem: AutomationRAGSubproblem
    public let query: StructuredRetrievalQuery

    public init(subproblem: AutomationRAGSubproblem, query: StructuredRetrievalQuery) {
        self.subproblem = subproblem
        self.query = query
    }
}

public struct AutomationRAGContextResult: Sendable, Hashable {
    public let promptText: String
    public let reports: [KnowledgeRetrievalReport]
    public let chunks: [ScoredChunk]

    public init(
        promptText: String,
        reports: [KnowledgeRetrievalReport] = [],
        chunks: [ScoredChunk] = []
    ) {
        self.promptText = promptText
        self.reports = reports
        self.chunks = chunks
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

        let strategy = AgentRetrievalStrategy(
            name: "automationDraft.hybrid.allAutomationKnowledge",
            agentID: .automationDraft,
            purpose: "Retrieve broad SmartThings automation knowledge for draft extraction.",
            requiredTags: ["operation": HomeAutomationOperationKind.automationCreation.rawValue],
            topK: topK,
            minScore: 0,
            ranking: .hybrid(alpha: 0.35),
            fallbackBehavior: .skip
        )
        return strategy.makeQuery(
            rawText: rawText,
            semanticText: QueryReformulator.reformulate(
                rawText: rawText,
                hints: nil,
                automationConcepts: concepts,
                conditionOperators: conditionOperators,
                repeatHints: repeatHints
            ),
            keywordTerms: keywordTerms,
            operation: HomeAutomationOperationKind.automationCreation,
            automationConcepts: concepts,
            conditionOperators: conditionOperators,
            repeatHints: repeatHints
        )
    }

    public static func retrievalQueries(
        for input: AutomationDraftInput,
        draftOutput: AutomationDraftOutput?,
        topKPerSubproblem: Int = 3
    ) -> [AutomationRAGSubproblemQuery] {
        let decision = decision(for: input, draftOutput: draftOutput)
        guard decision.shouldRetrieve else { return [] }

        let reasons = Set(decision.reasons)
        var subproblems: [AutomationRAGSubproblem] = []
        if draftOutput == nil ||
            input.operation == nil ||
            (input.operation?.confidence ?? 1) < deterministicConfidenceThreshold {
            subproblems.append(.operationRouting)
        }
        if draftOutput == nil ||
            !reasons.isDisjoint(with: ["missingDeterministicDraft", "lowDraftConfidence", "unsupportedFragments", "deviceTrigger"]) {
            subproblems.append(.draftExtraction)
        }
        if !reasons.isDisjoint(with: ["deviceAttributeCondition", "schemaSensitiveOperator", "compoundCondition"]) {
            subproblems.append(.conditionGrammar)
        }
        if !reasons.isDisjoint(with: ["deviceTrigger", "deviceAttributeCondition", "schemaSensitiveOperator", "compoundCondition", "unsupportedFragments"]) {
            subproblems.append(.compilerSchemaGrounding)
        }
        if subproblems.isEmpty {
            subproblems.append(.draftExtraction)
        }

        return stableUnique(subproblems.map(\.rawValue))
            .compactMap { AutomationRAGSubproblem(rawValue: $0) }
            .map { subproblem in
                AutomationRAGSubproblemQuery(
                    subproblem: subproblem,
                    query: query(for: subproblem, input: input, draftOutput: draftOutput, topK: topKPerSubproblem)
                )
            }
    }

    private static func query(
        for subproblem: AutomationRAGSubproblem,
        input: AutomationDraftInput,
        draftOutput: AutomationDraftOutput?,
        topK: Int
    ) -> StructuredRetrievalQuery {
        let rawText = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let concepts = automationConcepts(for: input, draftOutput: draftOutput)
        let conditionOperators = operators(in: draftOutput?.trigger?.condition) +
            operators(in: draftOutput?.condition)
        let repeatHints = repeatHints(for: rawText, draftOutput: draftOutput)
        let keywordTerms = concepts + conditionOperators + repeatHints + subproblem.queryTerms + [
            "automationCreation",
            "SmartThings",
            "rule",
            "every",
            "if",
            "command"
        ]

        let strategy = subproblem.retrievalStrategy(topK: topK)
        return strategy.makeQuery(
            rawText: rawText,
            semanticText: QueryReformulator.reformulate(
                rawText: rawText,
                hints: nil,
                automationConcepts: concepts,
                conditionOperators: conditionOperators,
                repeatHints: repeatHints
            ),
            keywordTerms: keywordTerms,
            operation: HomeAutomationOperationKind.automationCreation,
            automationConcepts: concepts,
            conditionOperators: conditionOperators,
            repeatHints: repeatHints
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
        if condition.type == .changes {
            return true
        }
        return condition.children.contains { containsSchemaSensitiveOperator(in: $0) }
    }

    private static func containsCompoundCondition(in condition: AutomationConditionOutput?) -> Bool {
        guard let condition else { return false }
        if [.and, .or, .not, .changes].contains(condition.type) {
            return true
        }
        return condition.children.contains { containsCompoundCondition(in: $0) }
    }

    private static func operators(in condition: AutomationConditionOutput?) -> [String] {
        guard let condition else { return [] }
        var values: [String] = []
        switch condition.type {
        case .and, .or, .not, .changes:
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
    /// Deterministic confidence at or above which few-shot enrichment is
    /// skipped: the rule-based result already grounds the model prompt via the
    /// worker-session hint, so retrieval adds latency without signal.
    static let fewShotSkipConfidence = 0.78

    static func nluInput(
        _ input: String,
        task: String,
        contextRetriever: ContextRetriever?,
        deterministicConfidence: Double? = nil,
        minTokenCount: Int = 8
    ) async -> String {
        guard let contextRetriever else { return input }
        let tokenCount = input.split(whereSeparator: \.isWhitespace).count
        guard tokenCount >= minTokenCount else { return input }
        if let deterministicConfidence, deterministicConfidence >= fewShotSkipConfidence {
            return input
        }
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
        await automationContext(
            input,
            draftOutput: draftOutput,
            contextRetriever: contextRetriever
        ).promptText
    }

    static func automationContext(
        _ input: AutomationDraftInput,
        draftOutput: AutomationDraftOutput?,
        contextRetriever: ContextRetriever?
    ) async -> AutomationRAGContextResult {
        let commandText = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let contextRetriever else {
            return AutomationRAGContextResult(promptText: commandText)
        }

        let queries = AutomationRAGPolicy.retrievalQueries(for: input, draftOutput: draftOutput)
        guard !queries.isEmpty else {
            return AutomationRAGContextResult(promptText: commandText)
        }

        let retrievals = await retrieveAutomationSubproblems(queries, contextRetriever: contextRetriever)
        let chunks = stableUnique(retrievals.flatMap(\.chunks)) { $0.chunk.id }
        let reports = retrievals.map { retrieval in
            KnowledgeRetrievalReport.make(
                agentID: .automationDraft,
                source: retrieval.subproblem.source.rawValue,
                strategy: retrieval.query.strategy.name,
                query: retrieval.query.rawText,
                results: retrieval.chunks.map { Double($0.score) },
                minScore: Double(retrieval.query.minScore),
                sourceIDs: retrieval.chunks.map { $0.chunk.id },
                filterHints: retrieval.subproblem.retrievalStrategy(topK: retrieval.query.topK).reportHints(extra: [
                    "subproblem": [retrieval.subproblem.rawValue],
                    "automationConcepts": retrieval.query.automationConcepts,
                    "conditionOperators": retrieval.query.conditionOperators,
                    "repeatHints": retrieval.query.repeatHints
                ].filter { !$0.value.isEmpty }),
                reformulatedQuery: retrieval.query.semanticText == retrieval.query.rawText ? nil : retrieval.query.semanticText
            )
        }
        guard !chunks.isEmpty else {
            return AutomationRAGContextResult(promptText: commandText, reports: reports)
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

        let promptText = """
        Relevant SmartThings automation knowledge:
        \(context)

        User automation command:
        \(commandText)
        """

        return AutomationRAGContextResult(promptText: promptText, reports: reports, chunks: chunks)
    }

    private struct AutomationSubproblemRetrieval: Sendable {
        let index: Int
        let subproblem: AutomationRAGSubproblem
        let query: StructuredRetrievalQuery
        let chunks: [ScoredChunk]
    }

    private static func retrieveAutomationSubproblems(
        _ queries: [AutomationRAGSubproblemQuery],
        contextRetriever: ContextRetriever
    ) async -> [AutomationSubproblemRetrieval] {
        await withTaskGroup(of: AutomationSubproblemRetrieval.self) { group in
            for (index, subproblemQuery) in queries.enumerated() {
                group.addTask {
                    let chunks = await contextRetriever.retrieve(subproblemQuery.query)
                    return AutomationSubproblemRetrieval(
                        index: index,
                        subproblem: subproblemQuery.subproblem,
                        query: subproblemQuery.query,
                        chunks: chunks
                    )
                }
            }

            var retrievals: [AutomationSubproblemRetrieval] = []
            for await retrieval in group {
                retrievals.append(retrieval)
            }
            return retrievals.sorted { $0.index < $1.index }
        }
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
