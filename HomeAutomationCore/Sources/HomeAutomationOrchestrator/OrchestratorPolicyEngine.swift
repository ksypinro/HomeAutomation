import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public struct OrchestratorPolicyEngine: Sendable {
    private let isModelAvailable: @Sendable () -> Bool

    public init(isModelAvailable: @escaping @Sendable () -> Bool) {
        self.isModelAvailable = isModelAvailable
    }

    public func shouldUseModels() -> Bool {
        isModelAvailable()
    }

    public func shouldRetry(failure: AgentFailure, attemptCount: Int) -> Bool {
        failure.isRetryable && attemptCount < maxRetries(for: failure.agentID)
    }

    public func isTerminalExit(_ result: AgentRunResult) -> Bool {
        switch result {
        case .clarification, .unsupported, .terminalFailure:
            return true
        case .success, .retryableFailure:
            return false
        }
    }

    public func canExecute(context: ResolutionContext) -> Bool {
        guard context.request.executeLowRiskCommands else { return false }
        guard let resolution = context.resolution else { return false }
        if case .readyToExecute(let plan) = resolution {
            return !plan.requiresConfirmation && plan.steps.contains { $0.type == "command" }
        }
        return false
    }

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

    public func failClosedResult(for agentID: AgentID, reason: String, context: ResolutionContext) -> AgentRunResult {
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
