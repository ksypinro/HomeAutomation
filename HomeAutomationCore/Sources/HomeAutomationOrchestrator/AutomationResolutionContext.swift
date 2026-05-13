import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public enum AutomationValidationSeverity: String, Sendable, Hashable, Codable {
    case warning
    case error
}

public struct AutomationValidationIssue: Sendable, Hashable, Codable {
    public let code: String
    public let message: String
    public let severity: AutomationValidationSeverity

    public init(
        code: String,
        message: String,
        severity: AutomationValidationSeverity
    ) {
        self.code = code
        self.message = message
        self.severity = severity
    }
}

public struct AutomationValidationResult: Sendable, Hashable, Codable {
    public let issues: [AutomationValidationIssue]
    public let requiresConfirmation: Bool

    public init(
        issues: [AutomationValidationIssue] = [],
        requiresConfirmation: Bool = false
    ) {
        self.issues = issues
        self.requiresConfirmation = requiresConfirmation
    }

    public var isValid: Bool {
        !issues.contains { $0.severity == .error }
    }
}

public enum AutomationCreationResolution: Sendable, Hashable, Codable {
    case drafted(HomeAutomationCreationPlan)
    case requiresConfirmation(HomeAutomationCreationPlan)
    case needsClarification(String)
    case unsupported(String)
}

public struct AutomationResolutionContext: Sendable {
    public let request: CommandRequest
    public let operation: HomeOperationDetectionResult
    public var draft: HomeAutomationRuleDraft?
    public var resolvedActions: [HomeAutomationResolvedAction]
    public var validation: AutomationValidationResult?
    public var smartThingsRule: SmartThingsRuleDocument?
    public var resolution: AutomationCreationResolution?
    public var trace: [AgentTraceEntry]
    public var errors: [AgentFailure]

    public init(
        request: CommandRequest,
        operation: HomeOperationDetectionResult,
        draft: HomeAutomationRuleDraft? = nil,
        resolvedActions: [HomeAutomationResolvedAction] = [],
        validation: AutomationValidationResult? = nil,
        smartThingsRule: SmartThingsRuleDocument? = nil,
        resolution: AutomationCreationResolution? = nil,
        trace: [AgentTraceEntry] = [],
        errors: [AgentFailure] = []
    ) {
        self.request = request
        self.operation = operation
        self.draft = draft
        self.resolvedActions = resolvedActions
        self.validation = validation
        self.smartThingsRule = smartThingsRule
        self.resolution = resolution
        self.trace = trace
        self.errors = errors
    }
}
