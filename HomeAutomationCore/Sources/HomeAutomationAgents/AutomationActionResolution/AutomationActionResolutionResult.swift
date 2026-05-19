import Foundation
import HomeAutomationCore

/// Result of resolving a single automation action description through the direct-command pipeline.
public struct AutomationActionResolutionResult: Sendable {
    public let resolvedAction: HomeAutomationResolvedAction?
    public let retrievedCandidates: [HomeCandidateRecord]
    public let hydratedCandidates: [HomeCandidateRecord]
    public let selectedCandidateIDs: [String]
    public let draft: HomeCommandDraft?
    public let resolution: HomeCommandResolution
    public let aggregation: HomeCandidateAggregationResult
    public let subgraphRun: HomeAutomationSubgraphRunSummary?

    public init(
        resolvedAction: HomeAutomationResolvedAction?,
        retrievedCandidates: [HomeCandidateRecord],
        hydratedCandidates: [HomeCandidateRecord],
        selectedCandidateIDs: [String],
        draft: HomeCommandDraft?,
        resolution: HomeCommandResolution,
        aggregation: HomeCandidateAggregationResult,
        subgraphRun: HomeAutomationSubgraphRunSummary? = nil
    ) {
        self.resolvedAction = resolvedAction
        self.retrievedCandidates = retrievedCandidates
        self.hydratedCandidates = hydratedCandidates
        self.selectedCandidateIDs = selectedCandidateIDs
        self.draft = draft
        self.resolution = resolution
        self.aggregation = aggregation
        self.subgraphRun = subgraphRun
    }

    /// Whether the action resolved to a usable command draft.
    public var isResolved: Bool {
        resolvedAction != nil
    }

    /// Whether the action requires user clarification.
    public var needsClarification: Bool {
        if case .needsClarification = resolution { return true }
        return false
    }

    /// Whether the action is unsupported.
    public var isUnsupported: Bool {
        if case .unsupported = resolution { return true }
        return false
    }

    /// Whether the resolved action requires confirmation due to risk.
    public var requiresConfirmation: Bool {
        if case .requiresConfirmation = resolution { return true }
        if case .readyToExecute(let plan) = resolution, plan.requiresConfirmation { return true }
        return false
    }
}
