import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public actor AgentInvocationActor {
    public let invocationID: String

    public init(invocationID: String) {
        self.invocationID = invocationID
    }

    public func run(
        agent: any AnyHomeAgent,
        context: ResolutionContext,
        telemetryContext: HomeAutomationTelemetryContext
    ) async -> AgentRunResult {
        await HomeAutomationTelemetryScope.$current.withValue(telemetryContext) {
            await agent.run(context: context)
        }
    }

    public func runOperation(
        _ operation: @Sendable @escaping () async -> AgentRunResult,
        telemetryContext: HomeAutomationTelemetryContext
    ) async -> AgentRunResult {
        await HomeAutomationTelemetryScope.$current.withValue(telemetryContext) {
            await operation()
        }
    }

    public func runValue<Value: Sendable>(
        _ operation: @Sendable @escaping () async -> Value,
        telemetryContext: HomeAutomationTelemetryContext
    ) async -> Value {
        await HomeAutomationTelemetryScope.$current.withValue(telemetryContext) {
            await operation()
        }
    }
}

public struct DetachedAgentExecutor: Sendable {
    public init() {}

    public func runDetached(
        agent: any AnyHomeAgent,
        context: ResolutionContext,
        telemetryContext: HomeAutomationTelemetryContext,
        priority: TaskPriority = .userInitiated
    ) async -> AgentRunResult {
        let invocationActor = AgentInvocationActor(
            invocationID: telemetryContext.agentInvocationID ?? UUID().uuidString
        )
        return await runDetached(
            telemetryContext: telemetryContext,
            priority: priority
        ) {
            await invocationActor.run(
                agent: agent,
                context: context,
                telemetryContext: telemetryContext
            )
        }
    }

    public func runDetached(
        telemetryContext: HomeAutomationTelemetryContext,
        priority: TaskPriority = .userInitiated,
        operation: @Sendable @escaping () async -> AgentRunResult
    ) async -> AgentRunResult {
        let invocationActor = AgentInvocationActor(
            invocationID: telemetryContext.agentInvocationID ?? UUID().uuidString
        )
        let task = Task.detached(priority: priority) {
            await invocationActor.runOperation(
                operation,
                telemetryContext: telemetryContext
            )
        }

        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    public func runDetachedValue<Value: Sendable>(
        telemetryContext: HomeAutomationTelemetryContext,
        priority: TaskPriority = .userInitiated,
        operation: @Sendable @escaping () async -> Value
    ) async -> Value {
        let invocationActor = AgentInvocationActor(
            invocationID: telemetryContext.agentInvocationID ?? UUID().uuidString
        )
        let task = Task.detached(priority: priority) {
            await invocationActor.runValue(
                operation,
                telemetryContext: telemetryContext
            )
        }

        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
