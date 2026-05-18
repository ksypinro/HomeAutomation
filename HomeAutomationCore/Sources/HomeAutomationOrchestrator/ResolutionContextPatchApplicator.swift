import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public typealias PatchApplicator = @Sendable (AnySendableValue, inout ResolutionContext) -> Void

public enum ResolutionContextPatchApplicators {
    public static let registry: [String: PatchApplicator] = [
        ResolutionContextPatchKey.resolverResult.rawValue: { value, ctx in
            if let result = value.get(HomeAutomationResolverResult.self) {
                ctx.resolutionState = result.state
                ctx.retrievedCandidates = result.retrievedCandidates
                ctx.aggregation = result.aggregation
                ctx.selectedCandidateIDs = result.aggregation.finalCandidateIDs
                ctx.hydratedCandidates = result.hydratedCandidates
                ctx.draft = result.draft
                ctx.resolution = result.resolution
            }
        },
        ResolutionContextPatchKey.operation.rawValue: { value, ctx in
            if let v = value.get(HomeOperationDetectionResult.self) { ctx.operation = v }
        },
        ResolutionContextPatchKey.language.rawValue: { value, ctx in
            if let v = value.get(HomeLanguageDetectionResult.self) { ctx.language = v }
        },
        ResolutionContextPatchKey.domain.rawValue: { value, ctx in
            if let v = value.get(HomeDomainClassificationResult.self) { ctx.domain = v }
        },
        ResolutionContextPatchKey.intent.rawValue: { value, ctx in
            if let v = value.get(HomeIntentFamilyResult.self) { ctx.intent = v }
        },
        ResolutionContextPatchKey.deviceType.rawValue: { value, ctx in
            if let v = value.get(HomeDeviceTypeResult.self) { ctx.deviceType = v }
        },
        ResolutionContextPatchKey.slots.rawValue: { value, ctx in
            if let v = value.get(HomeSlotExtractionResult.self) { ctx.slots = v }
        },
        ResolutionContextPatchKey.risk.rawValue: { value, ctx in
            if let v = value.get(HomeRiskClassificationResult.self) { ctx.risk = v }
        },
        ResolutionContextPatchKey.resolutionState.rawValue: { value, ctx in
            if let v = value.get(HomeResolutionState.self) { ctx.resolutionState = v }
        },
        ResolutionContextPatchKey.retrievedCandidates.rawValue: { value, ctx in
            if let v = value.get([HomeCandidateRecord].self) { ctx.retrievedCandidates = v }
        },
        ResolutionContextPatchKey.selectedCandidateIDs.rawValue: { value, ctx in
            if let v = value.get([String].self) { ctx.selectedCandidateIDs = v }
        },
        ResolutionContextPatchKey.aggregation.rawValue: { value, ctx in
            if let v = value.get(HomeCandidateAggregationResult.self) {
                ctx.aggregation = v
                ctx.selectedCandidateIDs = v.finalCandidateIDs
            }
        },
        ResolutionContextPatchKey.hydratedCandidates.rawValue: { value, ctx in
            if let v = value.get([HomeCandidateRecord].self) { ctx.hydratedCandidates = v }
        },
        ResolutionContextPatchKey.knowledgeSnippets.rawValue: { value, ctx in
            if let v = value.get([KnowledgeSnippet].self) { ctx.knowledgeSnippets.append(contentsOf: v) }
        },
        ResolutionContextPatchKey.retrievalReports.rawValue: { value, ctx in
            if let v = value.get([KnowledgeRetrievalReport].self) { ctx.retrievalReports.append(contentsOf: v) }
        },
        ResolutionContextPatchKey.instructionPackage.rawValue: { value, ctx in
            if let v = value.get(HomeModelInstructionPackage.self) { ctx.instructionPackage = v }
        },
        ResolutionContextPatchKey.draft.rawValue: { value, ctx in
            if let v = value.get(HomeCommandDraft.self) { ctx.draft = v }
        },
        ResolutionContextPatchKey.executionPlan.rawValue: { value, ctx in
            if let v = value.get(HomeAutomationExecutionPlan.self) { ctx.executionPlan = v }
        },
        ResolutionContextPatchKey.resolution.rawValue: { value, ctx in
            if let v = value.get(HomeCommandResolution.self) { ctx.resolution = v }
        }
    ]
}
