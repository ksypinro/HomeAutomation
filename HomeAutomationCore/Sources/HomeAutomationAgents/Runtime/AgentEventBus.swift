import Foundation
import HomeAutomationCore
import OSLog

/// A pipeline event generated during the orchestration process.
/// 
/// Events are published when agents start, complete, fail, or skip execution,
/// allowing external observers (like UI) to track the orchestrator's progress in real-time.
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

/// An actor responsible for distributing orchestrator pipeline events to subscribers.
/// 
/// `AgentEventBus` allows components to publish events without blocking, and provides
/// an `AsyncStream` for consumers to observe the real-time execution of the orchestrator.
public actor AgentEventBus {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "AgentEventBus")
    private var events: [OrchestratorPipelineEvent] = []
    private var continuations: [UUID: AsyncStream<OrchestratorPipelineEvent>.Continuation] = [:]
    private var isFinished = false

    public init() {}

    /// Publishes a new event to the bus and delivers it to all active continuations.
    ///
    /// - Parameter event: The `OrchestratorPipelineEvent` to broadcast.
    public func publish(_ event: OrchestratorPipelineEvent) async {
        guard !isFinished else { return }
        logger.debug("Publishing event for runID: \(event.runID, privacy: .public), stage: \(event.stage, privacy: .public), status: \(event.status.rawValue, privacy: .public)")
        await HomeAutomationTelemetry.shared.log(
            "pipeline.event",
            context: HomeAutomationTelemetryContext(
                runID: event.runID.uuidString,
                stage: event.stage,
                agentID: event.agentID
            ),
            status: event.status.rawValue,
            payload: [
                "eventID": event.id,
                "detail": event.detail
            ]
        )
        events.append(event)
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    /// Creates an asynchronous stream that replays all historical events and yields future ones.
    ///
    /// - Returns: An `AsyncStream` emitting `OrchestratorPipelineEvent`s.
    public func stream() -> AsyncStream<OrchestratorPipelineEvent> {
        logger.debug("Creating new event stream. Replaying \(self.events.count, privacy: .public) historical events.")
        let replayEvents = events
        return AsyncStream { continuation in
            for event in replayEvents {
                continuation.yield(event)
            }
            if isFinished {
                continuation.finish()
                return
            }
            let id = UUID()
            self.continuations[id] = continuation
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeContinuation(id: id) }
            }
        }
    }
    
    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    /// Resets the event history and terminates active continuations.
    public func reset() {
        logger.debug("Resetting event bus. Clearing \(self.events.count, privacy: .public) events and \(self.continuations.count, privacy: .public) active continuations.")
        events = []
        continuations = [:]
        isFinished = false
    }

    /// Finishes active event streams after all previously published events have been yielded.
    public func finish() {
        isFinished = true
        logger.debug("Finishing \(self.continuations.count, privacy: .public) active event stream(s).")
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }
}
