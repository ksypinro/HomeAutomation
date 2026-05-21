import Foundation

/// Describes which fields of ResolutionContext should be updated.
public struct ResolutionContextPatch: Sendable {
    public let agentID: AgentID
    public var updates: [String: AnySendableValue]
    public var scopedUpdates: [ContextScope: [String: AnySendableValue]]
    public var transitionRequest: GraphTransitionRequest?
    public let timestamp: Date

    public init(
        agentID: AgentID,
        updates: [String: AnySendableValue] = [:],
        scopedUpdates: [ContextScope: [String: AnySendableValue]] = [:],
        transitionRequest: GraphTransitionRequest? = nil
    ) {
        self.agentID = agentID
        self.updates = updates
        self.scopedUpdates = scopedUpdates
        self.transitionRequest = transitionRequest
        self.timestamp = Date()
    }

    public mutating func setArtifact<Value: Sendable>(
        _ value: Value,
        for key: ContextArtifactKey<Value>
    ) {
        scopedUpdates[key.scope, default: [:]][key.name] = AnySendableValue(value)
    }

    public func settingArtifact<Value: Sendable>(
        _ value: Value,
        for key: ContextArtifactKey<Value>
    ) -> ResolutionContextPatch {
        var copy = self
        copy.setArtifact(value, for: key)
        return copy
    }
}

/// Type-erased sendable value wrapper.
public struct AnySendableValue: Sendable {
    private let value: any Sendable
    public let typeName: String
    public let debugDescription: String

    public init<V: Sendable>(_ value: V) {
        self.value = value
        self.typeName = String(reflecting: V.self)
        self.debugDescription = String(describing: value)
    }

    public func get<V>(_ type: V.Type) -> V? {
        value as? V
    }

    public func isSemanticallySame(as other: AnySendableValue) -> Bool {
        typeName == other.typeName && debugDescription == other.debugDescription
    }
}

public enum GraphTransitionRequest: Sendable, Hashable, Codable {
    case routeToClarification(question: String, reason: String)
    case routeToUnsupported(reason: String)
    case routeToFallback(reason: String)
    case insertConfirmationBeforeExecution(reason: String)
    case retryWithAlternateCapability(capability: String, command: String?, reason: String)

    public var kind: String {
        switch self {
        case .routeToClarification:
            return "routeToClarification"
        case .routeToUnsupported:
            return "routeToUnsupported"
        case .routeToFallback:
            return "routeToFallback"
        case .insertConfirmationBeforeExecution:
            return "insertConfirmationBeforeExecution"
        case .retryWithAlternateCapability:
            return "retryWithAlternateCapability"
        }
    }

    public var reason: String {
        switch self {
        case .routeToClarification(_, let reason),
             .routeToUnsupported(let reason),
             .routeToFallback(let reason),
             .insertConfirmationBeforeExecution(let reason),
             .retryWithAlternateCapability(_, _, let reason):
            return reason
        }
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
