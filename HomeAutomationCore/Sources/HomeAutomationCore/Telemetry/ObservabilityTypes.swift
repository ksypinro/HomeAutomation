import Foundation

public enum TelemetrySpanKind: String, Sendable, Codable, Hashable {
    case run
    case graph
    case graphNode
    case agentAttempt
    case modelCall
    case toolCall
    case automationComponent
    case evaluationCase
    case event
}

public enum TelemetryStatus: String, Sendable, Codable, Hashable {
    case running
    case completed
    case failed
    case skipped
    case cancelled
}

public enum TelemetryPrivacy: String, Sendable, Codable, Hashable {
    case `public`
    case internalID
    case deviceName
    case userCommand
    case modelPrompt
    case modelOutput
    case secret
    case location
}

public enum TelemetryValue: Sendable, Codable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([TelemetryValue])
    case object([String: TelemetryValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([TelemetryValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: TelemetryValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public var stringValue: String {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return String(value)
        case .array(let value):
            return value.map(\.stringValue).joined(separator: ",")
        case .object(let value):
            let pairs = value.keys.sorted().map { key in "\(key)=\(value[key]?.stringValue ?? "")" }
            return pairs.joined(separator: ",")
        case .null:
            return ""
        }
    }
}

public struct TelemetryPayload: Sendable, Codable, Hashable {
    public var values: [String: TelemetryValue]
    public var privacy: [String: TelemetryPrivacy]

    public init(
        values: [String: TelemetryValue] = [:],
        privacy: [String: TelemetryPrivacy] = [:]
    ) {
        self.values = values
        self.privacy = privacy
    }

    public init(strings: [String: String], privacy: [String: TelemetryPrivacy] = [:]) {
        self.values = strings.mapValues(TelemetryValue.string)
        self.privacy = privacy
    }

    public var stringValues: [String: String] {
        values.mapValues(\.stringValue)
    }
}

public struct TelemetryTraceContext: Sendable, Codable, Hashable {
    public let traceID: String
    public let spanID: String
    public let parentSpanID: String?

    public init(
        traceID: String = UUID().uuidString,
        spanID: String = Self.makeSpanID(),
        parentSpanID: String? = nil
    ) {
        self.traceID = traceID
        self.spanID = spanID
        self.parentSpanID = parentSpanID
    }

    public func child() -> TelemetryTraceContext {
        TelemetryTraceContext(
            traceID: traceID,
            spanID: Self.makeSpanID(),
            parentSpanID: spanID
        )
    }

    public static func makeSpanID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

public struct ObservabilityEvent: Sendable, Codable, Hashable {
    public let schemaVersion: Int
    public let timestamp: Date
    public let eventType: String
    public let traceID: String?
    public let spanID: String?
    public let parentSpanID: String?
    public let spanKind: TelemetrySpanKind
    public let runID: String?
    public let operation: String?
    public let graphID: String?
    public let stage: String?
    public let graphNodeID: String?
    public let agentID: String?
    public let agentInvocationID: String?
    public let componentKind: String?
    public let componentID: String?
    public let actionID: String?
    public let conditionID: String?
    public let attempt: Int?
    public let runtimeMode: String?
    public let status: TelemetryStatus?
    public let startedAt: Date?
    public let completedAt: Date?
    public let durationMs: Double?
    public let payload: [String: TelemetryValue]
    public let payloadPrivacy: [String: TelemetryPrivacy]

    public init(
        eventType: String,
        traceID: String? = nil,
        spanID: String? = nil,
        parentSpanID: String? = nil,
        spanKind: TelemetrySpanKind = .event,
        runID: String? = nil,
        operation: String? = nil,
        graphID: String? = nil,
        stage: String? = nil,
        graphNodeID: String? = nil,
        agentID: String? = nil,
        agentInvocationID: String? = nil,
        componentKind: String? = nil,
        componentID: String? = nil,
        actionID: String? = nil,
        conditionID: String? = nil,
        attempt: Int? = nil,
        runtimeMode: String? = nil,
        status: TelemetryStatus? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        durationMs: Double? = nil,
        payload: TelemetryPayload = TelemetryPayload()
    ) {
        self.schemaVersion = 2
        self.timestamp = Date()
        self.eventType = eventType
        self.traceID = traceID
        self.spanID = spanID
        self.parentSpanID = parentSpanID
        self.spanKind = spanKind
        self.runID = runID
        self.operation = operation
        self.graphID = graphID
        self.stage = stage
        self.graphNodeID = graphNodeID
        self.agentID = agentID
        self.agentInvocationID = agentInvocationID
        self.componentKind = componentKind
        self.componentID = componentID
        self.actionID = actionID
        self.conditionID = conditionID
        self.attempt = attempt
        self.runtimeMode = runtimeMode
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMs = durationMs
        self.payload = payload.values
        self.payloadPrivacy = payload.privacy
    }

    public var stringPayload: [String: String] {
        payload.mapValues(\.stringValue)
    }
}

public struct TelemetrySinkStats: Sendable, Codable, Hashable {
    public var appendedCount: Int
    public var droppedCount: Int
    public var writeFailureCount: Int

    public init(appendedCount: Int = 0, droppedCount: Int = 0, writeFailureCount: Int = 0) {
        self.appendedCount = appendedCount
        self.droppedCount = droppedCount
        self.writeFailureCount = writeFailureCount
    }
}

public protocol TelemetrySink: Sendable {
    func append(_ event: ObservabilityEvent) async
    func flush() async
    func stats() async -> TelemetrySinkStats
}

