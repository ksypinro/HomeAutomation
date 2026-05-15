import Foundation
import HomeAutomationCore

public enum ContextScope: Sendable, Hashable, Codable, CustomStringConvertible {
    case root
    case operation
    case action(String)
    case condition(String)
    case backend(String)

    public var description: String {
        switch self {
        case .root:
            return "root"
        case .operation:
            return "operation"
        case .action(let id):
            return "action:\(id)"
        case .condition(let id):
            return "condition:\(id)"
        case .backend(let id):
            return "backend:\(id)"
        }
    }
}

public struct ScopedContextKey<Value: Sendable>: Sendable, Hashable {
    public let name: String
    public let scope: ContextScope

    public init(_ name: String, scope: ContextScope) {
        self.name = name
        self.scope = scope
    }

    public func scoped(to scope: ContextScope) -> ScopedContextKey<Value> {
        ScopedContextKey<Value>(name, scope: scope)
    }
}

public enum ScopedContextKeys {
    public static func operation(
        in scope: ContextScope = .operation
    ) -> ScopedContextKey<HomeOperationDetectionResult> {
        ScopedContextKey("operation", scope: scope)
    }

    public static func commandDraft(
        in scope: ContextScope
    ) -> ScopedContextKey<HomeCommandDraft> {
        ScopedContextKey("draft", scope: scope)
    }

    public static func automationRuleDraft(
        in scope: ContextScope = .root
    ) -> ScopedContextKey<HomeAutomationRuleDraft> {
        ScopedContextKey("automationDraft", scope: scope)
    }

    public static func automationPlan(
        in scope: ContextScope = .root
    ) -> ScopedContextKey<HomeAutomationCreationPlan> {
        ScopedContextKey("automationPlan", scope: scope)
    }

    public static func resolvedAction(
        in scope: ContextScope
    ) -> ScopedContextKey<HomeAutomationResolvedAction> {
        ScopedContextKey("automationResolvedAction", scope: scope)
    }

    public static func automationCondition(
        in scope: ContextScope
    ) -> ScopedContextKey<HomeAutomationCondition> {
        ScopedContextKey("automationCondition", scope: scope)
    }

    public static func validation(
        in scope: ContextScope = .root
    ) -> ScopedContextKey<AutomationValidationResult> {
        ScopedContextKey("automationValidation", scope: scope)
    }

    public static func smartThingsRule(
        in scope: ContextScope = .backend("smartthings")
    ) -> ScopedContextKey<SmartThingsRuleDocument> {
        ScopedContextKey("smartThingsRule", scope: scope)
    }
}
