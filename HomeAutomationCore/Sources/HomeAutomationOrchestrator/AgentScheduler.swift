import Foundation
import HomeAutomationAgents

public struct AgentScheduler: Sendable {
    private let registry: AgentRegistry
    private let contextStore: ResolutionContextStore
    private let eventBus: AgentEventBus
    private let policy: OrchestratorPolicyEngine
    private let circuitBreakers: CircuitBreakerRegistry
    private let runID: UUID

    public init(
        registry: AgentRegistry,
        contextStore: ResolutionContextStore,
        eventBus: AgentEventBus,
        policy: OrchestratorPolicyEngine,
        circuitBreakers: CircuitBreakerRegistry = CircuitBreakerRegistry(),
        runID: UUID
    ) {
        self.registry = registry
        self.contextStore = contextStore
        self.eventBus = eventBus
        self.policy = policy
        self.circuitBreakers = circuitBreakers
        self.runID = runID
    }

    public func execute(_ plan: AgentExecutionPlan) async -> AgentRunResult? {
        for phase in plan.phases {
            switch phase {
            case .sequential(let task):
                let context = await contextStore.snapshot()
                if let exit = await runAgent(task, context: context) {
                    return exit
                }
            case .parallel(let tasks):
                let context = await contextStore.snapshot()
                let exit = await withTaskGroup(of: AgentRunResult?.self) { group in
                    for task in tasks {
                        group.addTask {
                            await self.runAgent(task, context: context)
                        }
                    }

                    var firstExit: AgentRunResult?
                    for await result in group {
                        if firstExit == nil, let result {
                            firstExit = result
                        }
                    }
                    return firstExit
                }
                if let exit {
                    return exit
                }
            }
        }
        return nil
    }

    @discardableResult
    private func runAgent(_ task: AgentTask, context: ResolutionContext) async -> AgentRunResult? {
        guard let agent = registry.agent(for: task.agentID) else {
            await eventBus.publish(
                OrchestratorPipelineEvent(
                    runID: runID,
                    stage: task.agentID.rawValue,
                    agentID: task.agentID.rawValue,
                    status: .skipped,
                    detail: "Agent unavailable"
                )
            )
            if policy.isMandatorySafetyGate(task.agentID) {
                return await failClosed(for: task.agentID, reason: "agent unavailable", context: context)
            }
            return nil
        }

        let breaker = await circuitBreakers.breaker(for: task.agentID)
        guard await breaker.shouldAllow() else {
            let now = Date()
            await contextStore.appendTrace(
                AgentTraceEntry(
                    agentID: task.agentID,
                    startedAt: now,
                    endedAt: now,
                    result: .skipped
                )
            )
            await eventBus.publish(
                OrchestratorPipelineEvent(
                    runID: runID,
                    stage: task.agentID.rawValue,
                    agentID: task.agentID.rawValue,
                    status: .skipped,
                    detail: "Circuit breaker open"
                )
            )
            if policy.isMandatorySafetyGate(task.agentID) {
                return await failClosed(for: task.agentID, reason: "circuit breaker open", context: context)
            }
            return nil
        }

        await eventBus.publish(
            OrchestratorPipelineEvent(
                runID: runID,
                stage: task.agentID.rawValue,
                agentID: task.agentID.rawValue,
                status: .running
            )
        )

        let start = Date()
        let result = await agent.run(context: context)
        let end = Date()

        await record(result: result, breaker: breaker)

        await contextStore.appendTrace(
            AgentTraceEntry(
                agentID: task.agentID,
                startedAt: start,
                endedAt: end,
                result: traceResult(for: result)
            )
        )

        if case .success(let patch) = result {
            await contextStore.apply(patch)
        } else if case .retryableFailure(let failure) = result {
            await contextStore.appendError(failure)
        } else if case .terminalFailure(let failure) = result {
            await contextStore.appendError(failure)
        }

        await eventBus.publish(
            OrchestratorPipelineEvent(
                runID: runID,
                stage: task.agentID.rawValue,
                agentID: task.agentID.rawValue,
                status: eventStatus(for: result),
                detail: detail(for: result)
            )
        )

        if policy.isMandatorySafetyGate(task.agentID) {
            switch result {
            case .success:
                break
            default:
                return await failClosed(for: task.agentID, reason: "mandatory gate failed", context: await contextStore.snapshot())
            }
        }

        if policy.isTerminalExit(result) {
            return result
        }

        if shouldStopAfterContextResolution(await contextStore.snapshot(), after: task.agentID) {
            return result
        }

        return nil
    }

    private func record(result: AgentRunResult, breaker: AgentCircuitBreaker) async {
        switch result {
        case .success, .clarification, .unsupported:
            await breaker.recordSuccess()
        case .retryableFailure, .terminalFailure:
            await breaker.recordFailure()
        }
    }

    private func failClosed(for agentID: AgentID, reason: String, context: ResolutionContext) async -> AgentRunResult {
        let result = policy.failClosedResult(for: agentID, reason: reason, context: context)
        if case .success(let patch) = result {
            await contextStore.apply(patch)
        }
        return result
    }

    private func shouldStopAfterContextResolution(_ context: ResolutionContext, after agentID: AgentID) -> Bool {
        guard let resolution = context.resolution else { return false }
        switch resolution {
        case .needsClarification, .unsupported, .requiresConfirmation, .executed:
            return true
        case .readyToExecute:
            return agentID == .ruleFallback || agentID == .bixbyFallback
        }
    }

    private func traceResult(for result: AgentRunResult) -> AgentTraceEntry.TraceResult {
        switch result {
        case .success:
            return .success
        case .clarification:
            return .clarification
        case .unsupported:
            return .unsupported
        case .retryableFailure:
            return .retryableFailure
        case .terminalFailure:
            return .terminalFailure
        }
    }

    private func eventStatus(for result: AgentRunResult) -> OrchestratorPipelineEvent.EventStatus {
        switch result {
        case .success:
            return .completed
        case .clarification, .unsupported, .retryableFailure, .terminalFailure:
            return .failed
        }
    }

    private func detail(for result: AgentRunResult) -> String {
        switch result {
        case .success:
            return ""
        case .clarification(let value), .unsupported(let value):
            return value
        case .retryableFailure(let failure), .terminalFailure(let failure):
            return failure.reason
        }
    }
}
