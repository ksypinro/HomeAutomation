import Foundation

public struct HomeAutomationCreationPlan: Sendable, Hashable, Codable {
    public let name: String
    public let ruleDraft: HomeAutomationRuleDraft
    public let resolvedActions: [HomeAutomationResolvedAction]
    public let smartThingsRuleJSON: String?
    public let requiresConfirmation: Bool
    public let unsupportedCompilationReason: String?

    public init(
        name: String,
        ruleDraft: HomeAutomationRuleDraft,
        resolvedActions: [HomeAutomationResolvedAction],
        smartThingsRuleJSON: String?,
        requiresConfirmation: Bool,
        unsupportedCompilationReason: String?
    ) {
        self.name = name
        self.ruleDraft = ruleDraft
        self.resolvedActions = resolvedActions
        self.smartThingsRuleJSON = smartThingsRuleJSON
        self.requiresConfirmation = requiresConfirmation
        self.unsupportedCompilationReason = unsupportedCompilationReason
    }
}
