import Foundation
import HomeAutomationCore
import HomeAutomationRAG

public struct AutomationRAGEvaluationCase: Sendable, Hashable, Codable {
    public let id: String
    public let command: String
    public let operation: HomeAutomationOperationKind
    public let shouldRetrieve: Bool
    public let expectedSubproblems: [AutomationRAGSubproblem]
    public let expectedSources: [KnowledgeSource]
    public let expectedConcepts: [String]
    public let expectedConditionOperators: [String]
    public let expectedRepeatHints: [String]

    public init(
        id: String,
        command: String,
        operation: HomeAutomationOperationKind = .automationCreation,
        shouldRetrieve: Bool,
        expectedSubproblems: [AutomationRAGSubproblem] = [],
        expectedSources: [KnowledgeSource] = [],
        expectedConcepts: [String] = [],
        expectedConditionOperators: [String] = [],
        expectedRepeatHints: [String] = []
    ) {
        self.id = id
        self.command = command
        self.operation = operation
        self.shouldRetrieve = shouldRetrieve
        self.expectedSubproblems = expectedSubproblems
        self.expectedSources = expectedSources
        self.expectedConcepts = expectedConcepts
        self.expectedConditionOperators = expectedConditionOperators
        self.expectedRepeatHints = expectedRepeatHints
    }
}

public enum AutomationRAGEvaluationCorpus {
    public static let cases: [AutomationRAGEvaluationCase] = [
        AutomationRAGEvaluationCase(
            id: "simple-daily-schedule",
            command: "Turn on AC every day at 7 AM",
            shouldRetrieve: false
        ),
        AutomationRAGEvaluationCase(
            id: "compound-device-condition",
            command: "Turn on AC every day at 7 AM if bedroom window is closed and motion is detected",
            shouldRetrieve: true,
            expectedSubproblems: [.conditionGrammar, .compilerSchemaGrounding],
            expectedSources: [.automationConditionOperator, .smartThingsRuleSchema],
            expectedConcepts: ["compoundCondition", "deviceAttribute"],
            expectedConditionOperators: ["and", "equals"],
            expectedRepeatHints: ["everyDay"]
        ),
        AutomationRAGEvaluationCase(
            id: "device-trigger",
            command: "When front door opens, turn on hallway light",
            shouldRetrieve: true,
            expectedSubproblems: [.draftExtraction, .conditionGrammar, .compilerSchemaGrounding],
            expectedSources: [.automationRuleExample, .automationConditionOperator, .smartThingsRuleSchema],
            expectedConcepts: ["deviceTrigger", "deviceAttribute"],
            expectedConditionOperators: ["equals"]
        ),
        AutomationRAGEvaluationCase(
            id: "unsupported-weekday",
            command: "Turn on AC every Monday at 7 AM",
            shouldRetrieve: true,
            expectedSubproblems: [.draftExtraction, .compilerSchemaGrounding],
            expectedSources: [.automationRuleExample, .smartThingsRuleSchema],
            expectedConcepts: ["unsupportedFragment"],
            expectedRepeatHints: ["monday"]
        ),
        AutomationRAGEvaluationCase(
            id: "between-condition",
            command: "Turn on bedroom lamp every day at 7 AM if bedroom lamp level is between 20 and 80",
            shouldRetrieve: true,
            expectedSubproblems: [.conditionGrammar, .compilerSchemaGrounding],
            expectedSources: [.automationConditionOperator, .smartThingsRuleSchema],
            expectedConcepts: ["deviceAttribute"],
            expectedConditionOperators: ["between"],
            expectedRepeatHints: ["everyDay"]
        )
    ]
}
