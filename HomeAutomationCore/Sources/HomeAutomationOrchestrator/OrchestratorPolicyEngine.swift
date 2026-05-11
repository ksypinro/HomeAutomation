import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import OSLog

/// Encapsulates routing, fallback, and retry rules for the orchestrator pipeline.
public struct OrchestratorPolicyEngine: Sendable {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "OrchestratorPolicyEngine")
    private let isModelAvailable: @Sendable () -> Bool
    private let modelAvailabilityStatusProvider: @Sendable () -> String?

    public init(
        isModelAvailable: @escaping @Sendable () -> Bool,
        modelAvailabilityStatus: @escaping @Sendable () -> String? = { nil }
    ) {
        self.isModelAvailable = isModelAvailable
        self.modelAvailabilityStatusProvider = modelAvailabilityStatus
    }

    /// Determines whether the pipeline should attempt Foundation Model-based resolution.
    public func shouldUseModels() -> Bool {
        let available = isModelAvailable()
        logger.debug("Policy evaluated shouldUseModels: \(available, privacy: .public)")
        return available
    }

    /// Provides a human-readable reason for model availability status.
    public func modelAvailabilityStatus() -> String {
        modelAvailabilityStatusProvider() ?? (isModelAvailable() ? "available" : "unavailable")
    }

    /// Determines if a failed agent should be retried based on its failure type and attempt count.
    public func shouldRetry(failure: AgentFailure, attemptCount: Int) -> Bool {
        let retry = failure.isRetryable && attemptCount < maxRetries(for: failure.agentID)
        if !retry {
            logger.debug("Policy rejecting retry for agent \(failure.agentID.rawValue, privacy: .public). Attempt: \(attemptCount, privacy: .public)")
        }
        return retry
    }

    /// Evaluates whether an agent's run result should prematurely terminate the pipeline.
    public func isTerminalExit(_ result: AgentRunResult) -> Bool {
        switch result {
        case .clarification, .unsupported, .terminalFailure:
            return true
        case .success, .retryableFailure:
            return false
        }
    }

    /// Determines if the current context has produced a fully verified and executable plan.
    public func canExecute(context: ResolutionContext) -> Bool {
        guard context.request.executeLowRiskCommands else { return false }
        guard let resolution = context.resolution else { return false }
        if case .readyToExecute(let plan) = resolution {
            return !plan.requiresConfirmation && plan.steps.contains { $0.type == "command" }
        }
        return false
    }

    /// Defines which agents are critical safety validators that must never be skipped.
    public func isMandatorySafetyGate(_ agentID: AgentID) -> Bool {
        [.safetyValidation, .parameterValidation, .confirmationPolicy, .executionPlanning, .mockExecution].contains(agentID)
    }

    public func failClosedResult(for agentID: AgentID, reason: String) -> AgentRunResult {
        failClosedResult(
            for: agentID,
            reason: reason,
            context: ResolutionContext(
                request: CommandRequest(text: "", executeLowRiskCommands: false)
            )
        )
    }

    /// Generates a fallback resolution when a mandatory safety gate fails closed.
    public func failClosedResult(for agentID: AgentID, reason: String, context: ResolutionContext) -> AgentRunResult {
        logger.warning("Failing closed for mandatory gate: \(agentID.rawValue, privacy: .public) due to: \(reason, privacy: .public)")
        let resolution: HomeCommandResolution
        switch agentID {
        case .safetyValidation:
            if let draft = context.draft {
                resolution = .requiresConfirmation(draft)
            } else {
                resolution = .unsupported("Safety validation blocked: \(reason)")
            }
        case .parameterValidation:
            resolution = .needsClarification("Some command values are invalid or missing.")
        case .confirmationPolicy:
            if let draft = context.draft {
                resolution = .requiresConfirmation(draft)
            } else {
                resolution = .needsClarification("I need confirmation before this command can be executed safely.")
            }
        case .executionPlanning:
            resolution = .unsupported("Execution planning blocked: \(reason)")
        case .mockExecution:
            if let plan = context.executionPlan {
                resolution = .readyToExecute(plan)
            } else {
                resolution = .unsupported("Execution blocked: \(reason)")
            }
        default:
            return .clarification("I need confirmation or more information before this command can be executed safely.")
        }

        return .success(
            ResolutionContextPatch(
                agentID: agentID,
                updates: [ResolutionContextPatchKey.resolution: AnySendableValue(resolution)]
            )
        )
    }

    private func legacyFailClosedResult(for agentID: AgentID, reason: String) -> AgentRunResult {
        if agentID == .executionPlanning {
            return .terminalFailure(
                AgentFailure(
                    agentID: agentID,
                    reason: "Execution planning blocked: \(reason)",
                    isRetryable: false
                )
            )
        }
        return .clarification("I need confirmation or more information before this command can be executed safely.")
    }

    private func maxRetries(for agentID: AgentID) -> Int {
        switch agentID {
        case .draftGeneration:
            return 3
        case .language, .domain, .intentFamily, .deviceType, .slotExtraction, .riskClassification:
            return 1
        case .candidateRetrieval, .candidateRanking, .ruleFallback:
            return 1
        default:
            return 0
        }
    }
}
