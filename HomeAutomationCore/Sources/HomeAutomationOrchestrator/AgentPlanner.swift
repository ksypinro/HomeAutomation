import Foundation
import HomeAutomationAgents

public struct AgentTask: Sendable {
    public let agentID: AgentID

    public init(_ id: AgentID) {
        self.agentID = id
    }
}

public enum AgentPhase: Sendable {
    case parallel([AgentTask])
    case sequential(AgentTask)
}

public struct AgentExecutionPlan: Sendable {
    public let phases: [AgentPhase]
    public let isFallbackOnly: Bool

    public init(phases: [AgentPhase], isFallbackOnly: Bool = false) {
        self.phases = phases
        self.isFallbackOnly = isFallbackOnly
    }
}

public struct AgentPlanner: Sendable {
    private let policy: OrchestratorPolicyEngine

    public init(policy: OrchestratorPolicyEngine) {
        self.policy = policy
    }

    public func plan(for text: String, context: ResolutionContext) -> AgentExecutionPlan {
        guard policy.shouldUseModels() else {
            return AgentExecutionPlan(
                phases: [
                    .sequential(AgentTask(.ruleFallback)),
                    .sequential(AgentTask(.bixbyFallback)),
                    .sequential(AgentTask(.unsupportedCommand))
                ],
                isFallbackOnly: true
            )
        }

        return AgentExecutionPlan(phases: [
            .parallel([
                AgentTask(.language),
                AgentTask(.domain),
                AgentTask(.intentFamily),
                AgentTask(.deviceType),
                AgentTask(.slotExtraction),
                AgentTask(.riskClassification)
            ]),
            .parallel([
                AgentTask(.capabilityKnowledge),
                AgentTask(.bixbyKnowledge),
                AgentTask(.commandExample),
                AgentTask(.candidateRetrieval)
            ]),
            .sequential(AgentTask(.candidateRanking)),
            .sequential(AgentTask(.candidateHydration)),
            .sequential(AgentTask(.instructionComposer)),
            .sequential(AgentTask(.draftGeneration)),
            .sequential(AgentTask(.safetyValidation)),
            .sequential(AgentTask(.parameterValidation)),
            .sequential(AgentTask(.confirmationPolicy)),
            .sequential(AgentTask(.executionPlanning))
        ])
    }
}
