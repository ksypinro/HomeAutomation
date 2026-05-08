import Foundation

public struct OrchestratorPipelineEvent: Sendable, Identifiable {
    public let id: String
    public let runID: UUID
    public let stage: String
    public let agentID: String?
    public let status: EventStatus
    public let detail: String
    public let timestamp: Date

    public enum EventStatus: String, Sendable {
        case pending
        case running
        case completed
        case failed
        case skipped
    }

    public init(
        runID: UUID,
        stage: String,
        agentID: String? = nil,
        status: EventStatus,
        detail: String = ""
    ) {
        self.id = UUID().uuidString
        self.runID = runID
        self.stage = stage
        self.agentID = agentID
        self.status = status
        self.detail = detail
        self.timestamp = Date()
    }
}

public actor AgentEventBus {
    private var events: [OrchestratorPipelineEvent] = []
    private var continuations: [AsyncStream<OrchestratorPipelineEvent>.Continuation] = []

    public init() {}

    public func publish(_ event: OrchestratorPipelineEvent) {
        events.append(event)
        for continuation in continuations {
            continuation.yield(event)
        }
    }

    public func stream() -> AsyncStream<OrchestratorPipelineEvent> {
        let replayEvents = events
        return AsyncStream { continuation in
            for event in replayEvents {
                continuation.yield(event)
            }
            addContinuation(continuation)
        }
    }

    public func reset() {
        events = []
        continuations = []
    }

    private func addContinuation(_ continuation: AsyncStream<OrchestratorPipelineEvent>.Continuation) {
        continuations.append(continuation)
    }
}
