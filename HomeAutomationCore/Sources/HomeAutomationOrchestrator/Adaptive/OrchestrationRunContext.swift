import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public struct OrchestrationRunContext: Sendable {
    public let request: CommandRequest
    public let preparedRequest: PreparedOrchestrationRequest
    public let runID: UUID
    public let traceID: String
    public let spanID: String
    public let eventBus: AgentEventBus
    public let contextStore: ResolutionContextStore
    public let usageLedger: FoundationModelUsageLedger
    public let selectedArm: FoundationModelCallArm
    public let executingArm: FoundationModelCallArm

    public init(
        request: CommandRequest,
        preparedRequest: PreparedOrchestrationRequest,
        runID: UUID,
        traceID: String,
        spanID: String,
        eventBus: AgentEventBus,
        contextStore: ResolutionContextStore,
        usageLedger: FoundationModelUsageLedger,
        selectedArm: FoundationModelCallArm,
        executingArm: FoundationModelCallArm
    ) {
        self.request = request
        self.preparedRequest = preparedRequest
        self.runID = runID
        self.traceID = traceID
        self.spanID = spanID
        self.eventBus = eventBus
        self.contextStore = contextStore
        self.usageLedger = usageLedger
        self.selectedArm = selectedArm
        self.executingArm = executingArm
    }

    public static func make(
        request: CommandRequest,
        preparedRequest: PreparedOrchestrationRequest,
        contextStore: ResolutionContextStore,
        selectedArm: FoundationModelCallArm,
        executingArm: FoundationModelCallArm
    ) -> OrchestrationRunContext {
        let runID = UUID()
        return OrchestrationRunContext(
            request: request,
            preparedRequest: preparedRequest,
            runID: runID,
            traceID: runID.uuidString,
            spanID: TelemetryTraceContext.makeSpanID(),
            eventBus: AgentEventBus(),
            contextStore: contextStore,
            usageLedger: FoundationModelUsageLedger(runID: runID.uuidString),
            selectedArm: selectedArm,
            executingArm: executingArm
        )
    }

    public func publishInputEvent(detail: String) async {
        await eventBus.publish(OrchestratorPipelineEvent(
            runID: runID,
            stage: "input",
            status: .completed,
            detail: detail
        ))
    }

    public func publishOutcomeEvent(result: HomeAutomationResolverResult) async {
        await eventBus.publish(OrchestratorPipelineEvent(
            runID: runID,
            stage: "outcome",
            status: .completed,
            detail: result.resolution.displaySummary
        ))
    }

    public func setAutomationActionStrategy() async {
        await contextStore.setScopedValue(
            AutomationActionResolutionStrategy(executingArm: executingArm),
            for: AutomationRuntimeContextKeys.actionResolutionStrategy
        )
    }
}
