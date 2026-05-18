import Foundation
import HomeAutomationAgents
import HomeAutomationCore

private struct AutomationRuntimeAgentInputError: LocalizedError, Sendable {
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

public struct AutomationDraftExtractionAgent: HomeAgent {
    public typealias Input = AutomationDraftInput
    public typealias Output = AutomationDraftExtractionOutput

    public let id = AgentID.automationDraft
    public let capabilities: Set<AgentCapability> = [.automationDrafting]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let draftAgent: AutomationDraftAgent

    public init(draftAgent: AutomationDraftAgent = AutomationDraftAgent()) {
        self.draftAgent = draftAgent
    }

    public func run(
        _ input: AutomationDraftInput,
        context: ResolutionContext
    ) async throws -> AutomationDraftExtractionOutput {
        let output = try await draftAgent.runWithDiagnostics(input, context: context)
        return try AutomationDraftExtractionOutput(
            ruleDraft: output.draft.makeRuleDraft(),
            retrievalReports: output.retrievalReports
        )
    }
}

public struct AutomationConditionOperandResolutionAgent: HomeAgent {
    public typealias Input = HomeAutomationRuleDraft
    public typealias Output = AutomationConditionResolutionOutput

    public let id = AgentID.automationConditionOperandResolution
    public let capabilities: Set<AgentCapability> = [.automationConditionOperandResolution]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let resolver: AutomationConditionOperandResolver

    public init(resolver: AutomationConditionOperandResolver) {
        self.resolver = resolver
    }

    public func run(
        _ input: HomeAutomationRuleDraft,
        context: ResolutionContext
    ) async throws -> AutomationConditionResolutionOutput {
        await resolver.resolveDraft(input)
    }
}

public struct AutomationActionResolutionAgent: HomeAgent {
    public typealias Input = [String]
    public typealias Output = AutomationActionResolutionAggregate

    public let id = AgentID.automationActionResolution
    public let capabilities: Set<AgentCapability> = [.automationActionResolution]
    public let timeoutNanoseconds: UInt64 = 240_000_000_000
    private let resolverProvider: @Sendable () -> AutomationActionResolver?

    public init(resolverProvider: @escaping @Sendable () -> AutomationActionResolver?) {
        self.resolverProvider = resolverProvider
    }

    public func run(
        _ input: [String],
        context: ResolutionContext
    ) async throws -> AutomationActionResolutionAggregate {
        guard let resolver = resolverProvider() else {
            throw AutomationRuntimeAgentInputError(
                agentID: .automationActionResolution,
                message: "Automation action resolver is unavailable"
            )
        }
        let bridge = context.scopedValue(for: AutomationRuntimeContextKeys.pipelineEventBridge)
        let results = await resolver.resolveAll(
            input,
            eventBus: bridge?.eventBus ?? AgentEventBus(),
            runID: bridge?.runID ?? UUID()
        )
        return AutomationActionResolutionAggregate(
            actionDescriptions: input,
            results: results
        )
    }
}

public struct SmartThingsCompilationAgent: HomeAgent {
    public typealias Input = SmartThingsCompilationInput
    public typealias Output = SmartThingsCompilationOutput

    public let id = AgentID.smartThingsCompilation
    public let capabilities: Set<AgentCapability> = [.smartThingsCompilation]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let compiler: SmartThingsRuleCompiler

    public init(compiler: SmartThingsRuleCompiler = SmartThingsRuleCompiler()) {
        self.compiler = compiler
    }

    public func run(
        _ input: SmartThingsCompilationInput,
        context: ResolutionContext
    ) async throws -> SmartThingsCompilationOutput {
        let initialPlan = HomeAutomationCreationPlan(
            name: input.ruleDraft.name,
            ruleDraft: input.ruleDraft,
            resolvedActions: input.resolvedActions,
            smartThingsRuleJSON: nil,
            requiresConfirmation: input.requiresConfirmation || input.validation?.requiresConfirmation == true,
            unsupportedCompilationReason: input.validation?.unsupportedCompilationReason
        )

        do {
            let document = try compiler.compile(initialPlan)
            let compiledPlan = HomeAutomationCreationPlan(
                name: initialPlan.name,
                ruleDraft: initialPlan.ruleDraft,
                resolvedActions: initialPlan.resolvedActions,
                smartThingsRuleJSON: document.jsonString,
                requiresConfirmation: initialPlan.requiresConfirmation,
                unsupportedCompilationReason: initialPlan.unsupportedCompilationReason
            )
            return SmartThingsCompilationOutput(
                plan: compiledPlan,
                document: document,
                detail: "compiled"
            )
        } catch {
            let failedPlan = HomeAutomationCreationPlan(
                name: initialPlan.name,
                ruleDraft: initialPlan.ruleDraft,
                resolvedActions: initialPlan.resolvedActions,
                smartThingsRuleJSON: nil,
                requiresConfirmation: initialPlan.requiresConfirmation,
                unsupportedCompilationReason: initialPlan.unsupportedCompilationReason ?? error.localizedDescription
            )
            return SmartThingsCompilationOutput(
                plan: failedPlan,
                document: nil,
                detail: error.localizedDescription
            )
        }
    }
}

public struct SmartThingsRuleCreationAgent: HomeAgent {
    public typealias Input = SmartThingsRuleCreationInput
    public typealias Output = SmartThingsRuleCreationOutput

    public let id = AgentID.smartThingsRuleCreation
    public let capabilities: Set<AgentCapability> = [.smartThingsRuleCreation]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let creator: (any SmartThingsRuleCreating)?

    public init(creator: (any SmartThingsRuleCreating)? = nil) {
        self.creator = creator
    }

    public func run(
        _ input: SmartThingsRuleCreationInput,
        context: ResolutionContext
    ) async throws -> SmartThingsRuleCreationOutput {
        guard input.options.mode == .create else {
            return SmartThingsRuleCreationOutput(
                plan: input.plan,
                receipt: nil,
                detail: "dry-run"
            )
        }

        guard input.validation?.isValid != false else {
            return skipped(
                input: input,
                status: .skipped,
                message: input.validation?.blockingMessage ?? "Automation validation blocked SmartThings rule creation."
            )
        }

        guard let document = input.document else {
            return skipped(
                input: input,
                status: .skipped,
                message: input.plan.unsupportedCompilationReason ?? "SmartThings rule JSON is unavailable."
            )
        }

        if input.plan.requiresConfirmation && !input.options.confirmsHighRiskAutomation {
            return skipped(
                input: input,
                status: .confirmationRequired,
                message: "Explicit confirmation is required before creating this high-risk automation."
            )
        }

        guard let locationID = input.options.locationID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !locationID.isEmpty else {
            return skipped(
                input: input,
                status: .skipped,
                message: "SmartThings location ID is required before creating a rule."
            )
        }

        guard let creator else {
            return skipped(
                input: input,
                status: .skipped,
                message: "SmartThings rule creator backend is not configured."
            )
        }

        do {
            let receipt = try await creator.createRule(
                SmartThingsRuleCreationRequest(
                    document: document,
                    locationID: locationID,
                    plan: input.plan
                )
            )
            return SmartThingsRuleCreationOutput(
                plan: plan(input.plan, receipt: receipt, requiresConfirmation: false),
                receipt: receipt,
                detail: receipt.message
            )
        } catch {
            let receipt = SmartThingsRuleCreationReceipt(
                status: .failed,
                locationID: locationID,
                message: error.localizedDescription
            )
            return SmartThingsRuleCreationOutput(
                plan: plan(
                    input.plan,
                    receipt: receipt,
                    requiresConfirmation: remainingConfirmationRequired(for: input, status: .failed)
                ),
                receipt: receipt,
                detail: receipt.message
            )
        }
    }

    private func skipped(
        input: SmartThingsRuleCreationInput,
        status: SmartThingsRuleCreationStatus,
        message: String
    ) -> SmartThingsRuleCreationOutput {
        let receipt = SmartThingsRuleCreationReceipt(
            status: status,
            locationID: input.options.locationID,
            message: message
        )
        return SmartThingsRuleCreationOutput(
            plan: plan(
                input.plan,
                receipt: receipt,
                requiresConfirmation: remainingConfirmationRequired(for: input, status: status)
            ),
            receipt: receipt,
            detail: message
        )
    }

    private func plan(
        _ plan: HomeAutomationCreationPlan,
        receipt: SmartThingsRuleCreationReceipt,
        requiresConfirmation: Bool? = nil
    ) -> HomeAutomationCreationPlan {
        HomeAutomationCreationPlan(
            name: plan.name,
            ruleDraft: plan.ruleDraft,
            resolvedActions: plan.resolvedActions,
            smartThingsRuleJSON: plan.smartThingsRuleJSON,
            requiresConfirmation: requiresConfirmation ?? plan.requiresConfirmation,
            unsupportedCompilationReason: plan.unsupportedCompilationReason,
            backendResponse: receipt
        )
    }

    private func remainingConfirmationRequired(
        for input: SmartThingsRuleCreationInput,
        status: SmartThingsRuleCreationStatus
    ) -> Bool {
        if status == .confirmationRequired {
            return true
        }
        if input.options.mode == .create && input.options.confirmsHighRiskAutomation {
            return false
        }
        return input.plan.requiresConfirmation
    }
}

public struct AutomationResultAssemblyAgent: HomeAgent {
    public typealias Input = ResolutionContext
    public typealias Output = HomeAutomationResolverResult

    public let id = AgentID.automationResultAssembly
    public let capabilities: Set<AgentCapability> = [.automationResultAssembly]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000

    public init() {}

    public func run(
        _ input: ResolutionContext,
        context: ResolutionContext
    ) async throws -> HomeAutomationResolverResult {
        guard let ruleDraft = input.scopedValue(for: ScopedContextKeys.automationRuleDraft()) else {
            throw AutomationRuntimeAgentInputError(
                agentID: .automationResultAssembly,
                message: "Missing automation draft"
            )
        }

        let operation = input.operation ?? HomeOperationDetectionResult(
            domain: .homeAutomation,
            operation: .automationCreation,
            confidence: ruleDraft.confidence,
            reason: "Automation creation graph"
        )
        let state = HomeResolutionState.forOperation(text: input.request.text, operation: operation)
        let aggregate = input.scopedValue(for: AutomationRuntimeContextKeys.actionResolutionAggregate)
        let validation = input.scopedValue(for: ScopedContextKeys.validation())
        let compilation = input.scopedValue(for: AutomationRuntimeContextKeys.smartThingsCompilation)
        let creation = input.scopedValue(for: AutomationRuntimeContextKeys.smartThingsRuleCreation)

        if let blocking = aggregate?.firstBlockingResolution {
            return Self.blockingActionResult(
                state: state,
                aggregate: aggregate,
                resolution: blocking
            )
        }

        if validation?.status == .needsClarification {
            let question = validation?.clarificationQuestion ??
                validation?.blockingMessage ??
                "I need more information before creating this automation."
            return HomeAutomationResolverResult(
                state: state,
                retrievedCandidates: aggregate?.retrievedCandidates ?? [],
                aggregation: HomeCandidateAggregationResult(
                    finalCandidateIDs: aggregate?.selectedCandidateIDs ?? [],
                    needsClarification: true,
                    clarificationQuestion: question,
                    confidence: 0
                ),
                hydratedCandidates: aggregate?.hydratedCandidates ?? [],
                draft: aggregate?.firstDraft,
                resolution: .needsClarification(question)
            )
        }

        if validation?.status == .unsupported {
            return HomeAutomationResolverResult(
                state: state,
                retrievedCandidates: aggregate?.retrievedCandidates ?? [],
                aggregation: HomeCandidateAggregationResult(
                    finalCandidateIDs: aggregate?.selectedCandidateIDs ?? [],
                    needsClarification: false,
                    confidence: operation.confidence
                ),
                hydratedCandidates: aggregate?.hydratedCandidates ?? [],
                draft: aggregate?.firstDraft,
                resolution: .unsupported(validation?.blockingMessage ?? "Automation is not valid.")
            )
        }

        let plan = creation?.plan ?? compilation?.plan ?? HomeAutomationCreationPlan(
            name: ruleDraft.name,
            ruleDraft: ruleDraft,
            resolvedActions: aggregate?.resolvedActions ?? [],
            smartThingsRuleJSON: nil,
            requiresConfirmation: aggregate?.requiresConfirmation == true || validation?.requiresConfirmation == true,
            unsupportedCompilationReason: validation?.unsupportedCompilationReason
        )
        let resolution: HomeCommandResolution = plan.requiresConfirmation
            ? .automationRequiresConfirmation(plan)
            : .automationDrafted(plan)

        return HomeAutomationResolverResult(
            state: state,
            retrievedCandidates: aggregate?.retrievedCandidates ?? [],
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: aggregate?.selectedCandidateIDs ?? [],
                needsClarification: false,
                confidence: aggregate?.resolvedActions.map(\.confidence).min() ?? ruleDraft.confidence
            ),
            hydratedCandidates: aggregate?.hydratedCandidates ?? [],
            draft: aggregate?.firstDraft,
            resolution: resolution
        )
    }

    private static func blockingActionResult(
        state: HomeResolutionState,
        aggregate: AutomationActionResolutionAggregate?,
        resolution: HomeCommandResolution
    ) -> HomeAutomationResolverResult {
        let outputResolution: HomeCommandResolution
        let needsClarification: Bool
        switch resolution {
        case .needsClarification(let question):
            outputResolution = .needsClarification(question)
            needsClarification = true
        case .unsupported(let reason):
            outputResolution = .unsupported(reason)
            needsClarification = false
        default:
            outputResolution = .unsupported("Automation action could not be resolved.")
            needsClarification = false
        }

        return HomeAutomationResolverResult(
            state: state,
            retrievedCandidates: aggregate?.retrievedCandidates ?? [],
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: aggregate?.selectedCandidateIDs ?? [],
                needsClarification: needsClarification,
                confidence: 0
            ),
            hydratedCandidates: aggregate?.hydratedCandidates ?? [],
            draft: aggregate?.firstDraft,
            resolution: outputResolution
        )
    }


}
