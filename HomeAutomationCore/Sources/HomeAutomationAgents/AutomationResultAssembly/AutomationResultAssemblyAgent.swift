import Foundation
import HomeAutomationCore

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
