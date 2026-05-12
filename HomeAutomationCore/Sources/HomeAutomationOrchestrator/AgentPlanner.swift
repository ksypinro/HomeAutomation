import Foundation
import HomeAutomationAgents
import OSLog

/// Represents a single unit of work assigned to a specific agent.
public struct AgentTask: Sendable {
    public let agentID: AgentID

    public init(_ id: AgentID) {
        self.agentID = id
    }
}

/// Defines how a group of tasks should be executed.
public enum AgentPhase: Sendable {
    /// Tasks that can run concurrently.
    case parallel([AgentTask])
    /// A task that must run sequentially.
    case sequential(AgentTask)
}

/// A structured plan of execution phases for resolving a command.
public struct AgentExecutionPlan: Sendable {
    public let phases: [AgentPhase]
    public let isFallbackOnly: Bool

    public init(phases: [AgentPhase], isFallbackOnly: Bool = false) {
        self.phases = phases
        self.isFallbackOnly = isFallbackOnly
    }
}

/// The component responsible for constructing an `AgentExecutionPlan` dynamically based
/// on the user's input, the current context, and orchestrator policies.
public struct AgentPlanner: Sendable {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "AgentPlanner")
    private let policy: OrchestratorPolicyEngine

    public init(policy: OrchestratorPolicyEngine) {
        self.policy = policy
    }

    /// Generates an execution plan for a given user command.
    ///
    /// - Parameters:
    ///   - text: The raw user input command.
    ///   - context: The current `ResolutionContext` (useful for dynamic replanning).
    /// - Returns: A comprehensive `AgentExecutionPlan`.
    public func plan(for text: String, context: ResolutionContext) -> AgentExecutionPlan {
        logger.debug("Generating plan for text: '\(text, privacy: .private)'")
        
        guard policy.shouldUseModels() else {
            logger.warning("Models unavailable. Planning fallback-only execution.")
            return AgentExecutionPlan(
                phases: [
                    .sequential(AgentTask(.ruleFallback)),
                    .sequential(AgentTask(.bixbyFallback)),
                    .sequential(AgentTask(.unsupportedCommand))
                ],
                isFallbackOnly: true
            )
        }

        logger.debug("Models available. Planning full execution pipeline.")
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
            .sequential(AgentTask(.retrievalJudge)),
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
