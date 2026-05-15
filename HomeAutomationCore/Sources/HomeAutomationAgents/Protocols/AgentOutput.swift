import Foundation

/// Describes which fields of ResolutionContext should be updated.
public struct ResolutionContextPatch: Sendable {
    public let agentID: AgentID
    public let updates: [String: AnySendableValue]
    public let scopedUpdates: [ContextScope: [String: AnySendableValue]]
    public let timestamp: Date

    public init(
        agentID: AgentID,
        updates: [String: AnySendableValue] = [:],
        scopedUpdates: [ContextScope: [String: AnySendableValue]] = [:]
    ) {
        self.agentID = agentID
        self.updates = updates
        self.scopedUpdates = scopedUpdates
        self.timestamp = Date()
    }
}

/// Type-erased sendable value wrapper.
public struct AnySendableValue: Sendable {
    private let value: any Sendable

    public init<V: Sendable>(_ value: V) {
        self.value = value
    }

    public func get<V>(_ type: V.Type) -> V? {
        value as? V
    }
}

/// Result of any agent run. The scheduler uses this to decide retry and fallback behavior.
public enum AgentRunResult: Sendable {
    case success(ResolutionContextPatch)
    case clarification(String)
    case unsupported(String)
    case retryableFailure(AgentFailure)
    case terminalFailure(AgentFailure)
}
