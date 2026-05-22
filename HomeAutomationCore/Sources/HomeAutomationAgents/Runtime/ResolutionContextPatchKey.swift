import Foundation

/// String constants used as dictionary keys when agents patch the `ResolutionContext`.
public enum ResolutionContextPatchKey: String, CaseIterable, Sendable {
    case resolverResult
    case operation
    case language
    case domain
    case intent
    case deviceType
    case slots
    case risk
    case resolutionState
    case retrievedCandidates
    case selectedCandidateIDs
    case aggregation
    case hydratedCandidates
    case capabilityDecision
    case knowledgeSnippets
    case retrievalReports
    case instructionPackage
    case draft
    case executionPlan
    case resolution
    case automationComponentPlan
    case automationResolvedComponents
    case automationDraft
    case automationResolvedActions
    case automationConditionOperandResolutionRecords
    case automationValidation
    case smartThingsRule
    case automationPlan
}
