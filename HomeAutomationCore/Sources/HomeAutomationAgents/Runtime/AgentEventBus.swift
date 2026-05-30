import Foundation
import HomeAutomationCore
import OSLog

/// A pipeline event generated during the orchestration process.
/// 
/// Events are published when agents start, complete, fail, or skip execution,
/// allowing external observers (like UI) to track the orchestrator's progress in real-time.
public struct OrchestratorPipelineEvent: Sendable, Identifiable {
    public let id: String
    public let sequence: Int?
    public let runID: UUID
    public let stage: String
    public let agentID: String?
    public let traceID: String?
    public let spanID: String?
    public let parentSpanID: String?
    public let componentKind: String?
    public let componentID: String?
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
        sequence: Int? = nil,
        traceID: String? = HomeAutomationTelemetryScope.current?.traceID,
        spanID: String? = HomeAutomationTelemetryScope.current?.spanID,
        parentSpanID: String? = HomeAutomationTelemetryScope.current?.parentSpanID,
        componentKind: String? = HomeAutomationTelemetryScope.current?.componentKind,
        componentID: String? = HomeAutomationTelemetryScope.current?.componentID,
        status: EventStatus,
        detail: String = ""
    ) {
        self.id = UUID().uuidString
        self.sequence = sequence
        self.runID = runID
        self.stage = stage
        self.agentID = agentID
        self.traceID = traceID
        self.spanID = spanID
        self.parentSpanID = parentSpanID
        self.componentKind = componentKind
        self.componentID = componentID
        self.status = status
        self.detail = detail
        self.timestamp = Date()
    }

    public func assigningSequence(_ sequence: Int) -> OrchestratorPipelineEvent {
        OrchestratorPipelineEvent(
            runID: runID,
            stage: stage,
            agentID: agentID,
            sequence: sequence,
            traceID: traceID,
            spanID: spanID,
            parentSpanID: parentSpanID,
            componentKind: componentKind,
            componentID: componentID,
            status: status,
            detail: detail
        )
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
    private let replayLimit: Int
    private var nextSequence = 1

    public init(replayLimit: Int = 1_000) {
        self.replayLimit = max(1, replayLimit)
    }

    /// Publishes a new event to the bus and delivers it to all active continuations.
    ///
    /// - Parameter event: The `OrchestratorPipelineEvent` to broadcast.
    public func publish(_ event: OrchestratorPipelineEvent) async {
        guard !isFinished else { return }
        let sequenced = event.sequence == nil ? event.assigningSequence(nextSequence) : event
        nextSequence = max(nextSequence + 1, (sequenced.sequence ?? nextSequence) + 1)
        logger.debug("Publishing event for runID: \(sequenced.runID, privacy: .public), stage: \(sequenced.stage, privacy: .public), status: \(sequenced.status.rawValue, privacy: .public)")
        await HomeAutomationTelemetry.shared.log(
            "pipeline.event",
            context: HomeAutomationTelemetryContext(
                traceID: sequenced.traceID,
                spanID: sequenced.spanID,
                parentSpanID: sequenced.parentSpanID,
                spanKind: .event,
                runID: sequenced.runID.uuidString,
                stage: sequenced.stage,
                agentID: sequenced.agentID,
                componentKind: sequenced.componentKind,
                componentID: sequenced.componentID
            ),
            status: sequenced.status.rawValue,
            payload: [
                "eventID": sequenced.id,
                "sequence": String(sequenced.sequence ?? 0),
                "detail": sequenced.detail
            ]
        )
        events.append(sequenced)
        if events.count > replayLimit {
            events.removeFirst(events.count - replayLimit)
        }
        for continuation in continuations.values {
            continuation.yield(sequenced)
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
        nextSequence = 1
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
