import Foundation

/// Structured agent failure stored in the context trace.
public struct AgentFailure: Sendable, Codable {
    public let agentID: AgentID
    public let reason: String
    public let isRetryable: Bool
    public let timestamp: Date

    public init(agentID: AgentID, reason: String, isRetryable: Bool) {
        self.agentID = agentID
        self.reason = reason
        self.isRetryable = isRetryable
        self.timestamp = Date()
    }
}

/// One trace entry per agent execution.
public struct AgentTraceEntry: Sendable, Codable {
    public let agentID: AgentID
    public let startedAt: Date
    public let endedAt: Date
    public let result: TraceResult
    public let durationSeconds: Double

    public enum TraceResult: String, Sendable, Codable {
        case success
        case clarification
        case unsupported
        case retryableFailure
        case terminalFailure
        case timeout
        case skipped
    }

    public init(agentID: AgentID, startedAt: Date, endedAt: Date, result: TraceResult) {
        self.agentID = agentID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.result = result
        self.durationSeconds = endedAt.timeIntervalSince(startedAt)
    }
}
