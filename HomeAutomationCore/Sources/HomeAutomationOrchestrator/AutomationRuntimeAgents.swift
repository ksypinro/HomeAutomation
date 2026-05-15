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
    public static let actionResolutionAggregate = ScopedContextKey<AutomationActionResolutionAggregate>(
        "automationActionResolutionAggregate",
        scope: .root
    )

    public static let conditionOperandResolutionRecords = ScopedContextKey<[AutomationConditionOperandResolutionRecord]>(
        ResolutionContextPatchKey.automationConditionOperandResolutionRecords,
        scope: .root
    )

    public static let smartThingsCompilation = ScopedContextKey<SmartThingsCompilationOutput>(
        "smartThingsCompilation",
        scope: .backend("smartthings")
    )

    public static func conditionOperandResolution(
        in scope: ContextScope
    ) -> ScopedContextKey<AutomationConditionOperandResolutionRecord> {
        ScopedContextKey("automationConditionOperandResolution", scope: scope)
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

public struct AutomationDraftExtractionAgent: HomeAgent {
    public typealias Input = AutomationDraftInput
    public typealias Output = HomeAutomationRuleDraft

    public let id = AgentID.automationDraft
    public let capabilities: Set<AgentCapability> = [.automationDrafting]
    public let timeoutNanoseconds: UInt64 = 2_000_000_000
    private let draftAgent: AutomationDraftAgent

    public init(draftAgent: AutomationDraftAgent = AutomationDraftAgent()) {
        self.draftAgent = draftAgent
    }

    public func run(
        _ input: AutomationDraftInput,
        context: ResolutionContext
    ) async throws -> HomeAutomationRuleDraft {
        let output = try await draftAgent.run(input, context: context)
        return try output.makeRuleDraft()
    }
}

public struct AutomationConditionOperandResolutionAgent: HomeAgent {
    public typealias Input = HomeAutomationRuleDraft
    public typealias Output = AutomationConditionResolutionOutput

    public let id = AgentID.automationConditionOperandResolution
    public let capabilities: Set<AgentCapability> = [.automationConditionOperandResolution]
    public let timeoutNanoseconds: UInt64 = 1_000_000_000
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
    public let timeoutNanoseconds: UInt64 = 8_000_000_000
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
        let results = await resolver.resolveAll(
            input,
            eventBus: AgentEventBus(),
            runID: UUID()
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
    public let timeoutNanoseconds: UInt64 = 1_000_000_000
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

public struct AutomationResultAssemblyAgent: HomeAgent {
    public typealias Input = ResolutionContext
    public typealias Output = HomeAutomationResolverResult

    public let id = AgentID.automationResultAssembly
    public let capabilities: Set<AgentCapability> = [.automationResultAssembly]
    public let timeoutNanoseconds: UInt64 = 1_000_000_000

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
        let state = Self.makeOperationState(for: input.request.text, operation: operation)
        let aggregate = input.scopedValue(for: AutomationRuntimeContextKeys.actionResolutionAggregate)
        let validation = input.scopedValue(for: ScopedContextKeys.validation())
        let compilation = input.scopedValue(for: AutomationRuntimeContextKeys.smartThingsCompilation)

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

        let plan = compilation?.plan ?? HomeAutomationCreationPlan(
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

    private static func makeOperationState(
        for text: String,
        operation: HomeOperationDetectionResult
    ) -> HomeResolutionState {
        HomeResolutionState(
            rawText: text,
            language: HomeLanguageDetectionResult(
                languageCode: "en",
                isMixedLanguage: false,
                confidence: 0.75,
                unsupportedLanguageLikely: false
            ),
            domain: HomeDomainClassificationResult(
                domain: operation.domain,
                confidence: operation.confidence
            ),
            intent: HomeIntentFamilyResult(
                topFamilies: operation.operation == .automationCreation ? [.createAutomation] : [.unsupported],
                confidence: operation.confidence
            ),
            deviceType: HomeDeviceTypeResult(deviceTypes: [], confidence: 0.4),
            slots: HomeSlotExtractionResult(
                rooms: [],
                deviceNicknames: [],
                values: [],
                modes: [],
                confidence: 0.4
            ),
            risk: HomeRiskClassificationResult(
                riskLevel: .low,
                requiresConfirmation: false,
                reason: operation.reason,
                confidence: operation.confidence
            )
        )
    }
}
