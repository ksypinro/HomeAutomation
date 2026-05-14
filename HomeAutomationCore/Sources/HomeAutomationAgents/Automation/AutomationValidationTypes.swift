import Foundation
import HomeAutomationCore

public struct AutomationValidationInput: Sendable, Hashable, Codable {
    public let ruleDraft: HomeAutomationRuleDraft
    public let resolvedActions: [HomeAutomationResolvedAction]

    public init(
        ruleDraft: HomeAutomationRuleDraft,
        resolvedActions: [HomeAutomationResolvedAction]
    ) {
        self.ruleDraft = ruleDraft
        self.resolvedActions = resolvedActions
    }
}
