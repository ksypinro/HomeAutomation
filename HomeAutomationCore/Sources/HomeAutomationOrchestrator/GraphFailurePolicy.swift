import Foundation
import HomeAutomationAgents
import HomeAutomationCore

struct GraphRetryController: Sendable {
    func shouldRetry(
        result: AgentRunResult,
        policy: OrchestratorPolicyEngine,
        attemptCount: Int
    ) -> Bool {
        guard case .retryableFailure(let failure) = result else {
            return false
        }
        return policy.shouldRetry(failure: failure, attemptCount: attemptCount)
    }
}

struct GraphSafetyGateHandler: Sendable {
    func isSafetyGate(
        node: GraphNode,
        agentID: AgentID,
        manifest: AgentManifest,
        policy: OrchestratorPolicyEngine
    ) -> Bool {
        node.executionPolicy == .safetyGate ||
            manifest.safetyRole != .none ||
            policy.isMandatorySafetyGate(agentID)
    }

    func failClosed(
        for agentID: AgentID,
        reason: String,
        context: ResolutionContext,
        contextStore: ResolutionContextStore,
        policy: OrchestratorPolicyEngine
    ) async -> AgentRunResult {
        let result = policy.failClosedResult(for: agentID, reason: reason, context: context)
        if case .success(let patch) = result {
            await contextStore.apply(patch)
        }
        return result
    }
}

extension GraphScheduler {
    func record(result: AgentRunResult, breaker: AgentCircuitBreaker, registry: CircuitBreakerRegistry) async {
        switch result {
        case .success, .clarification, .unsupported:
            await breaker.recordSuccess()
        case .retryableFailure, .terminalFailure:
            await breaker.recordFailure()
        }
        await registry.persist()
    }

    func shouldStopAfterContextResolution(_ context: ResolutionContext, after agentID: AgentID) -> Bool {
        guard let resolution = context.resolution else { return false }
        switch resolution {
        case .needsClarification, .unsupported, .requiresConfirmation, .executed:
            return true
        case .automationDrafted, .automationRequiresConfirmation:
            return true
        case .readyToExecute:
            return agentID == .ruleFallback || agentID == .bixbyFallback
        }
    }
}
