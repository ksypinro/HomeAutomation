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

public struct ContextArtifactKey<Value: Sendable>: Sendable, Hashable {
    public let name: String
    public let scope: ContextScope
    public let valueTypeName: String
    public let debugDescription: String?

    public init(
        _ name: String,
        scope: ContextScope,
        debugDescription: String? = nil
    ) {
        self.name = name
        self.scope = scope
        self.valueTypeName = String(reflecting: Value.self)
        self.debugDescription = debugDescription
    }

    public var descriptor: ContextArtifactDescriptor {
        ContextArtifactDescriptor(
            name: name,
            scope: scope,
            valueTypeName: valueTypeName,
            debugDescription: debugDescription
        )
    }

    public func scoped(to scope: ContextScope) -> ContextArtifactKey<Value> {
        ContextArtifactKey<Value>(
            name,
            scope: scope,
            debugDescription: debugDescription
        )
    }
}

public struct ContextArtifactDescriptor: Sendable, Hashable, Codable, CustomStringConvertible {
    public let name: String
    public let scope: ContextScope
    public let valueTypeName: String
    public let debugDescription: String?

    public init(
        name: String,
        scope: ContextScope,
        valueTypeName: String,
        debugDescription: String? = nil
    ) {
        self.name = name
        self.scope = scope
        self.valueTypeName = valueTypeName
        self.debugDescription = debugDescription
    }

    public var storageKey: String {
        "\(scope.description).\(name)"
    }

    public var description: String {
        "\(storageKey)<\(valueTypeName)>"
    }
}

public enum ContextArtifactRequirement: String, Sendable, Hashable, Codable {
    case required
    case optional
}

public struct ContextArtifactContract: Sendable, Hashable, Codable {
    public let descriptor: ContextArtifactDescriptor
    public let requirement: ContextArtifactRequirement

    public init(
        descriptor: ContextArtifactDescriptor,
        requirement: ContextArtifactRequirement = .required
    ) {
        self.descriptor = descriptor
        self.requirement = requirement
    }

    public static func required<Value: Sendable>(
        _ key: ContextArtifactKey<Value>
    ) -> ContextArtifactContract {
        ContextArtifactContract(descriptor: key.descriptor, requirement: .required)
    }

    public static func optional<Value: Sendable>(
        _ key: ContextArtifactKey<Value>
    ) -> ContextArtifactContract {
        ContextArtifactContract(descriptor: key.descriptor, requirement: .optional)
    }
}

public enum ContextArtifactError: LocalizedError, Sendable, Hashable {
    case missing(key: ContextArtifactDescriptor)
    case typeMismatch(key: ContextArtifactDescriptor, actualTypeName: String)

    public var errorDescription: String? {
        switch self {
        case .missing(let key):
            return "Missing context artifact \(key.storageKey). Expected \(key.valueTypeName)."
        case .typeMismatch(let key, let actualTypeName):
            return "Context artifact \(key.storageKey) has type \(actualTypeName), expected \(key.valueTypeName)."
        }
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

    public static func smartThingsRuleCreation(
        in scope: ContextScope = .backend("smartthings")
    ) -> ScopedContextKey<SmartThingsRuleCreationReceipt> {
        ScopedContextKey("smartThingsRuleCreation", scope: scope)
    }
}

public enum ContextArtifactKeys {
    public static func automationRuleDraft(
        in scope: ContextScope = .root
    ) -> ContextArtifactKey<HomeAutomationRuleDraft> {
        ContextArtifactKey(
            "automationDraft",
            scope: scope,
            debugDescription: "Automation rule draft extracted from the user request."
        )
    }

    public static func automationComponentPlan(
        in scope: ContextScope = .root
    ) -> ContextArtifactKey<AutomationComponentPlan> {
        ContextArtifactKey(
            "automationComponentPlan",
            scope: scope,
            debugDescription: "Segmented automation trigger, action, and condition components."
        )
    }

    public static func automationResolvedComponents(
        in scope: ContextScope = .root
    ) -> ContextArtifactKey<AutomationResolvedComponentSet> {
        ContextArtifactKey(
            "automationResolvedComponents",
            scope: scope,
            debugDescription: "Resolved automation trigger, action, and condition component outputs."
        )
    }

    public static func automationPlan(
        in scope: ContextScope = .root
    ) -> ContextArtifactKey<HomeAutomationCreationPlan> {
        ContextArtifactKey(
            "automationPlan",
            scope: scope,
            debugDescription: "Compiled automation creation plan."
        )
    }

    public static func resolvedAction(
        in scope: ContextScope
    ) -> ContextArtifactKey<HomeAutomationResolvedAction> {
        ContextArtifactKey(
            "automationResolvedAction",
            scope: scope,
            debugDescription: "Resolved automation action for an action subgraph scope."
        )
    }

    public static func commandDraft(
        in scope: ContextScope
    ) -> ContextArtifactKey<HomeCommandDraft> {
        ContextArtifactKey(
            "draft",
            scope: scope,
            debugDescription: "Direct-command draft resolved inside a scoped graph."
        )
    }

    public static func nluPolicyOverride(
        in scope: ContextScope = .root
    ) -> ContextArtifactKey<NLUModelCallMode> {
        ContextArtifactKey(
            "nluPolicyOverride",
            scope: scope,
            debugDescription: "Per-run override of the NLU model-call mode (e.g. threshold gating inside automation action subgraphs)."
        )
    }

    public static func validation(
        in scope: ContextScope = .root
    ) -> ContextArtifactKey<AutomationValidationResult> {
        ContextArtifactKey(
            "automationValidation",
            scope: scope,
            debugDescription: "Automation validation result."
        )
    }

    public static func smartThingsRule(
        in scope: ContextScope = .backend("smartthings")
    ) -> ContextArtifactKey<SmartThingsRuleDocument> {
        ContextArtifactKey(
            "smartThingsRule",
            scope: scope,
            debugDescription: "SmartThings rule document produced by compilation."
        )
    }

    public static func smartThingsRuleCreation(
        in scope: ContextScope = .backend("smartthings")
    ) -> ContextArtifactKey<SmartThingsRuleCreationReceipt> {
        ContextArtifactKey(
            "smartThingsRuleCreation",
            scope: scope,
            debugDescription: "SmartThings rule creation receipt."
        )
    }
}
