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
}
