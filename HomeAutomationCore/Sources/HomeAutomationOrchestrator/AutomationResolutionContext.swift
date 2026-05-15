import Foundation
import HomeAutomationAgents
import HomeAutomationCore

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
