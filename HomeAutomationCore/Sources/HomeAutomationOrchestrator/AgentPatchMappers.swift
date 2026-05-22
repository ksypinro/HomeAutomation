import Foundation
import HomeAutomationAgents
import HomeAutomationCore

extension DefaultAgentRegistryFactory {
    internal static func patch(_ agentID: AgentID, _ values: [String: any Sendable]) -> ResolutionContextPatch {
        ResolutionContextPatch(
            agentID: agentID,
            updates: values.mapValues { AnySendableValue($0) }
        )
    }

    internal static func knowledgePatch(
        _ agentID: AgentID,
        _ output: KnowledgeRetrievalAgentOutput
    ) -> ResolutionContextPatch {
        patch(
            agentID,
            [
                ResolutionContextPatchKey.knowledgeSnippets.rawValue: output.snippets,
                ResolutionContextPatchKey.retrievalReports.rawValue: output.reports
            ]
        )
    }

    internal static func scopedPatch(
        _ agentID: AgentID,
        scope: ContextScope,
        _ values: [String: any Sendable]
    ) -> ResolutionContextPatch {
        ResolutionContextPatch(
            agentID: agentID,
            scopedUpdates: [
                scope: values.mapValues { AnySendableValue($0) }
            ]
        )
    }

    internal static func capabilityResolutionPatch(
        _ output: HomeCapabilityDecision,
        _ context: ResolutionContext
    ) -> ResolutionContextPatch {
        var transition: GraphTransitionRequest?
        if output.confidence < 0.45 {
            transition = .routeToClarification(
                question: "Which capability or command should I use for this device?",
                reason: "Capability resolution confidence \(output.confidence) is below the clarification threshold."
            )
        } else if output.confidence < 0.7, let alternative = output.alternatives.dropFirst().first {
            transition = .retryWithAlternateCapability(
                capability: alternative.capability,
                command: alternative.command,
                reason: "Capability resolution confidence \(output.confidence) is medium and an alternative is available."
            )
        }
        return ResolutionContextPatch(
            agentID: .capabilityResolution,
            updates: [ResolutionContextPatchKey.capabilityDecision.rawValue: AnySendableValue(output)],
            transitionRequest: transition
        )
    }
}
