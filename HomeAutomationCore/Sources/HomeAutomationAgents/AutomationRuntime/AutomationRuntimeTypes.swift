import Foundation
import HomeAutomationCore

struct AutomationRuntimeAgentInputError: LocalizedError, Sendable {
    let agentID: AgentID
    let message: String

    var errorDescription: String? {
        "\(agentID.rawValue): \(message)"
    }
}

public enum AutomationRuntimeContextKeys {
    public static let pipelineEventBridge = ScopedContextKey<AutomationPipelineEventBridge>(
        "automationPipelineEventBridge",
        scope: .root
    )

    public static let actionResolutionAggregate = ScopedContextKey<AutomationActionResolutionAggregate>(
        "automationActionResolutionAggregate",
        scope: .root
    )

    public static let conditionOperandResolutionRecords = ScopedContextKey<[AutomationConditionOperandResolutionRecord]>(
        ResolutionContextPatchKey.automationConditionOperandResolutionRecords.rawValue,
        scope: .root
    )

    public static let componentPlan = ScopedContextKey<AutomationComponentPlan>(
        ResolutionContextPatchKey.automationComponentPlan.rawValue,
        scope: .root
    )

    public static let resolvedComponentSet = ScopedContextKey<AutomationResolvedComponentSet>(
        ResolutionContextPatchKey.automationResolvedComponents.rawValue,
        scope: .root
    )

    public static let speculativeCompilation = ScopedContextKey<SpeculativeCompilationResult>(
        "speculativeCompilation",
        scope: .root
    )

    public static let smartThingsCompilation = ScopedContextKey<SmartThingsCompilationOutput>(
        "smartThingsCompilation",
        scope: .backend("smartthings")
    )

    public static let smartThingsRuleCreation = ScopedContextKey<SmartThingsRuleCreationOutput>(
        "smartThingsRuleCreationOutput",
        scope: .backend("smartthings")
    )

    public static func conditionOperandResolution(
        in scope: ContextScope
    ) -> ScopedContextKey<AutomationConditionOperandResolutionRecord> {
        ScopedContextKey("automationConditionOperandResolution", scope: scope)
    }
}

public struct AutomationPipelineEventBridge: Sendable {
    public let eventBus: AgentEventBus
    public let runID: UUID

    public init(eventBus: AgentEventBus, runID: UUID) {
        self.eventBus = eventBus
        self.runID = runID
    }
}

public struct AutomationActionResolutionAggregate: Sendable {
    public let actionDescriptions: [String]
    public let results: [AutomationActionResolutionResult]

    public init(
        actionDescriptions: [String],
        results: [AutomationActionResolutionResult]
    ) {
        self.actionDescriptions = actionDescriptions
        self.results = results
    }

    public var resolvedActions: [HomeAutomationResolvedAction] {
        results.compactMap(\.resolvedAction)
    }

    public var retrievedCandidates: [HomeCandidateRecord] {
        Self.stableUniqueDevices(results.flatMap(\.retrievedCandidates))
    }

    public var hydratedCandidates: [HomeCandidateRecord] {
        Self.stableUniqueDevices(results.flatMap(\.hydratedCandidates))
    }

    public var selectedCandidateIDs: [String] {
        Self.stableUnique(results.flatMap(\.selectedCandidateIDs))
    }

    public var firstDraft: HomeCommandDraft? {
        results.compactMap(\.draft).first
    }

    public var subgraphRuns: [HomeAutomationSubgraphRunSummary] {
        results.compactMap(\.subgraphRun)
    }

    public var requiresConfirmation: Bool {
        results.contains(where: \.requiresConfirmation)
    }

    public var firstBlockingResolution: HomeCommandResolution? {
        for result in results {
            if result.needsClarification || result.isUnsupported || !result.isResolved {
                return result.resolution
            }
        }
        return nil
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private static func stableUniqueDevices(_ devices: [HomeCandidateRecord]) -> [HomeCandidateRecord] {
        var seen = Set<String>()
        var result: [HomeCandidateRecord] = []
        for device in devices where !seen.contains(device.id) {
            seen.insert(device.id)
            result.append(device)
        }
        return result
    }
}

public struct SmartThingsCompilationInput: Sendable {
    public let ruleDraft: HomeAutomationRuleDraft
    public let resolvedActions: [HomeAutomationResolvedAction]
    public let requiresConfirmation: Bool
    public let validation: AutomationValidationResult?

    public init(
        ruleDraft: HomeAutomationRuleDraft,
        resolvedActions: [HomeAutomationResolvedAction],
        requiresConfirmation: Bool,
        validation: AutomationValidationResult?
    ) {
        self.ruleDraft = ruleDraft
        self.resolvedActions = resolvedActions
        self.requiresConfirmation = requiresConfirmation
        self.validation = validation
    }
}

public struct SmartThingsCompilationOutput: Sendable {
    public let plan: HomeAutomationCreationPlan
    public let document: SmartThingsRuleDocument?
    public let detail: String

    public init(
        plan: HomeAutomationCreationPlan,
        document: SmartThingsRuleDocument?,
        detail: String
    ) {
        self.plan = plan
        self.document = document
        self.detail = detail
    }
}

public struct SmartThingsRuleCreationInput: Sendable {
    public let plan: HomeAutomationCreationPlan
    public let document: SmartThingsRuleDocument?
    public let validation: AutomationValidationResult?
    public let options: SmartThingsRuleCreationOptions

    public init(
        plan: HomeAutomationCreationPlan,
        document: SmartThingsRuleDocument?,
        validation: AutomationValidationResult?,
        options: SmartThingsRuleCreationOptions
    ) {
        self.plan = plan
        self.document = document
        self.validation = validation
        self.options = options
    }
}

public struct SmartThingsRuleCreationOutput: Sendable {
    public let plan: HomeAutomationCreationPlan
    public let receipt: SmartThingsRuleCreationReceipt?
    public let detail: String

    public init(
        plan: HomeAutomationCreationPlan,
        receipt: SmartThingsRuleCreationReceipt?,
        detail: String
    ) {
        self.plan = plan
        self.receipt = receipt
        self.detail = detail
    }
}

public struct AutomationDraftExtractionOutput: Sendable, Hashable {
    public let ruleDraft: HomeAutomationRuleDraft
    public let retrievalReports: [KnowledgeRetrievalReport]

    public init(
        ruleDraft: HomeAutomationRuleDraft,
        retrievalReports: [KnowledgeRetrievalReport] = []
    ) {
        self.ruleDraft = ruleDraft
        self.retrievalReports = retrievalReports
    }
}
