import Foundation

public struct AgentRuntimeIdentity: Sendable, Codable, Hashable {
    public let agentID: String
    public let agentSessionID: String

    public init(agentID: String, agentSessionID: String) {
        self.agentID = agentID
        self.agentSessionID = agentSessionID
    }
}

public protocol ToolRuntimeIdentifiable: Sendable {
    var toolID: String { get }
    var toolSessionID: String { get }
}

public protocol AgentToolTraceArguments: Sendable {
    var agentID: String? { get }
    var agentSessionID: String? { get }
    var agentRunID: Int? { get }
}

public struct ToolTelemetryCallContext: Sendable, Hashable {
    public let startedAt: Date
    public let telemetryContext: HomeAutomationTelemetryContext
    public let toolCallID: String

    public init(
        startedAt: Date,
        telemetryContext: HomeAutomationTelemetryContext,
        toolCallID: String
    ) {
        self.startedAt = startedAt
        self.telemetryContext = telemetryContext
        self.toolCallID = toolCallID
    }
}
