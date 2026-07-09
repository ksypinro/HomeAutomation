import Foundation
import FoundationModels
import HomeAutomationCore

@Generable
public enum AutomationTriggerKindHint: String, Sendable, Hashable, Codable {
    case schedule
    case device
    case unknown
}

public struct AutomationTriggerComponent: Sendable, Hashable, Codable {
    public let id: String
    public let rawText: String
    public let kindHint: AutomationTriggerKindHint

    public init(id: String, rawText: String, kindHint: AutomationTriggerKindHint) {
        self.id = id
        self.rawText = rawText
        self.kindHint = kindHint
    }
}

public struct AutomationActionComponent: Sendable, Hashable, Codable {
    public let id: String
    public let rawText: String
    public let order: Int

    public init(id: String, rawText: String, order: Int) {
        self.id = id
        self.rawText = rawText
        self.order = order
    }
}

public struct AutomationConditionComponent: Sendable, Hashable, Codable {
    public let id: String
    public let rawText: String
    public let order: Int

    public init(id: String, rawText: String, order: Int) {
        self.id = id
        self.rawText = rawText
        self.order = order
    }
}

public indirect enum AutomationConditionTreeDescriptor: Sendable, Hashable, Codable {
    case leaf(String)
    case and([AutomationConditionTreeDescriptor])
    case or([AutomationConditionTreeDescriptor])
    case not(AutomationConditionTreeDescriptor)

    public var leafIDs: [String] {
        switch self {
        case .leaf(let id):
            return [id]
        case .and(let children), .or(let children):
            return children.flatMap(\.leafIDs)
        case .not(let child):
            return child.leafIDs
        }
    }
}

public struct AutomationComponentPlan: Sendable, Hashable, Codable {
    public let trigger: AutomationTriggerComponent?
    public let actions: [AutomationActionComponent]
    public let conditions: [AutomationConditionComponent]
    public let conditionTree: AutomationConditionTreeDescriptor?
    public let unsupportedFragments: [String]
    public let confidence: Double

    public init(
        trigger: AutomationTriggerComponent?,
        actions: [AutomationActionComponent],
        conditions: [AutomationConditionComponent],
        conditionTree: AutomationConditionTreeDescriptor?,
        unsupportedFragments: [String] = [],
        confidence: Double
    ) {
        self.trigger = trigger
        self.actions = actions
        self.conditions = conditions
        self.conditionTree = conditionTree
        self.unsupportedFragments = unsupportedFragments
        self.confidence = confidence
    }
}

public struct AutomationTriggerResolutionInput: Sendable, Hashable {
    public let component: AutomationTriggerComponent
    public let fullUserText: String
    public let timezoneIdentifier: String?

    public init(
        component: AutomationTriggerComponent,
        fullUserText: String,
        timezoneIdentifier: String? = nil
    ) {
        self.component = component
        self.fullUserText = fullUserText
        self.timezoneIdentifier = timezoneIdentifier
    }
}

public struct AutomationTriggerResolutionOutput: Sendable, Hashable {
    public let id: String
    public let trigger: HomeAutomationTrigger?
    public let confidence: Double
    public let unsupportedFragments: [String]

    public init(
        id: String,
        trigger: HomeAutomationTrigger?,
        confidence: Double,
        unsupportedFragments: [String] = []
    ) {
        self.id = id
        self.trigger = trigger
        self.confidence = confidence
        self.unsupportedFragments = unsupportedFragments
    }
}

public struct AutomationConditionClauseResolutionInput: Sendable, Hashable {
    public let component: AutomationConditionComponent
    public let fullUserText: String
    public let availableDevices: [HomeCandidateRecord]
    public let triggerPolicy: HomeAutomationConditionTriggerPolicy

    public init(
        component: AutomationConditionComponent,
        fullUserText: String,
        availableDevices: [HomeCandidateRecord],
        triggerPolicy: HomeAutomationConditionTriggerPolicy = .never
    ) {
        self.component = component
        self.fullUserText = fullUserText
        self.availableDevices = availableDevices
        self.triggerPolicy = triggerPolicy
    }
}

public struct AutomationConditionClauseResolutionResult: Sendable, Hashable {
    public let id: String
    public let rawText: String
    public let condition: HomeAutomationCondition?
    public let records: [AutomationConditionOperandResolutionRecord]
    public let confidence: Double

    public init(
        id: String,
        rawText: String,
        condition: HomeAutomationCondition?,
        records: [AutomationConditionOperandResolutionRecord],
        confidence: Double
    ) {
        self.id = id
        self.rawText = rawText
        self.condition = condition
        self.records = records
        self.confidence = confidence
    }
}

public struct AutomationResolvedComponentSet: Sendable {
    public let trigger: HomeAutomationTrigger?
    public let actionResults: [AutomationActionResolutionResult]
    public let conditionResults: [AutomationConditionClauseResolutionResult]
    public let conditionTree: AutomationConditionTreeDescriptor?
    public let unsupportedFragments: [String]
    public let speculativeCompilation: SpeculativeCompilationResult?

    public init(
        trigger: HomeAutomationTrigger?,
        actionResults: [AutomationActionResolutionResult],
        conditionResults: [AutomationConditionClauseResolutionResult],
        conditionTree: AutomationConditionTreeDescriptor?,
        unsupportedFragments: [String] = [],
        speculativeCompilation: SpeculativeCompilationResult? = nil
    ) {
        self.trigger = trigger
        self.actionResults = actionResults
        self.conditionResults = conditionResults
        self.conditionTree = conditionTree
        self.unsupportedFragments = unsupportedFragments
        self.speculativeCompilation = speculativeCompilation
    }
}

public struct SpeculativeCompilationResult: Sendable {
    public let ruleDraft: HomeAutomationRuleDraft
    public let smartThingsRuleJSON: String?
    public let compilationDetail: String

    public init(
        ruleDraft: HomeAutomationRuleDraft,
        smartThingsRuleJSON: String?,
        compilationDetail: String
    ) {
        self.ruleDraft = ruleDraft
        self.smartThingsRuleJSON = smartThingsRuleJSON
        self.compilationDetail = compilationDetail
    }
}

public struct AutomationDraftAssemblyInput: Sendable {
    public let componentPlan: AutomationComponentPlan
    public let resolvedComponents: AutomationResolvedComponentSet

    public init(
        componentPlan: AutomationComponentPlan,
        resolvedComponents: AutomationResolvedComponentSet
    ) {
        self.componentPlan = componentPlan
        self.resolvedComponents = resolvedComponents
    }
}
