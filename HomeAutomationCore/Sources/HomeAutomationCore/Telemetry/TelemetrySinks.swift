import Foundation

public typealias JSONLTelemetrySink = DailyJSONLLogWriter
public typealias TextTelemetrySink = DailyTextLogWriter

public actor InMemoryTelemetrySink: TelemetrySink {
    private var storedEvents: [ObservabilityEvent] = []
    private var sinkStats = TelemetrySinkStats()

    public init() {}

    public func append(_ event: ObservabilityEvent) async {
        storedEvents.append(event)
        sinkStats.appendedCount += 1
    }

    public func flush() async {}

    public func stats() async -> TelemetrySinkStats {
        sinkStats
    }

    public func events() async -> [ObservabilityEvent] {
        storedEvents
    }

    public func reset() async {
        storedEvents.removeAll()
        sinkStats = TelemetrySinkStats()
    }
}

public actor OpenTelemetryJSONSink: TelemetrySink {
    private let directoryURL: URL
    private var currentDateKey: String?
    private var fileHandle: FileHandle?
    private var sinkStats = TelemetrySinkStats()

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    deinit {
        try? fileHandle?.close()
    }

    public func append(_ event: ObservabilityEvent) async {
        do {
            let line = try Self.render(event)
            let handle = try fileHandle(for: event.timestamp)
            if let data = (line + "\n").data(using: .utf8) {
                try handle.write(contentsOf: data)
                sinkStats.appendedCount += 1
            }
        } catch {
            sinkStats.writeFailureCount += 1
        }
    }

    public func flush() async {
        try? fileHandle?.synchronize()
    }

    public func stats() async -> TelemetrySinkStats {
        sinkStats
    }

    private func fileHandle(for date: Date) throws -> FileHandle {
        let dateKey = Self.fileDateKey(for: date)
        if let fileHandle, currentDateKey == dateKey {
            return fileHandle
        }

        try fileHandle?.close()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let fileURL = directoryURL.appendingPathComponent(
            "home-automation-\(dateKey).otel.json",
            isDirectory: false
        )
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        currentDateKey = dateKey
        fileHandle = handle
        return handle
    }

    private static func render(_ event: ObservabilityEvent) throws -> String {
        var object: [String: Any] = [
            "resourceSpans": [
                [
                    "resource": [
                        "attributes": [
                            attribute("service.name", "HomeAutomation"),
                            attribute("telemetry.schema_version", String(event.schemaVersion))
                        ]
                    ],
                    "scopeSpans": [
                        [
                            "scope": ["name": "HomeAutomationTelemetry"],
                            "spans": [spanObject(event)]
                        ]
                    ]
                ]
            ]
        ]
        object["runID"] = event.runID
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func spanObject(_ event: ObservabilityEvent) -> [String: Any] {
        var attributes: [[String: Any]] = [
            attribute("event.type", event.eventType),
            attribute("span.kind", event.spanKind.rawValue)
        ]
        if let value = event.runID { attributes.append(attribute("run.id", value)) }
        if let value = event.operation { attributes.append(attribute("operation", value)) }
        if let value = event.graphID { attributes.append(attribute("graph.id", value)) }
        if let value = event.stage { attributes.append(attribute("stage", value)) }
        if let value = event.graphNodeID { attributes.append(attribute("graph.node.id", value)) }
        if let value = event.agentID { attributes.append(attribute("agent.id", value)) }
        if let value = event.agentInvocationID { attributes.append(attribute("agent.invocation.id", value)) }
        if let value = event.componentKind { attributes.append(attribute("component.kind", value)) }
        if let value = event.componentID { attributes.append(attribute("component.id", value)) }
        if let value = event.status?.rawValue { attributes.append(attribute("status", value)) }

        for key in event.payload.keys.sorted() {
            attributes.append(attribute("payload.\(key)", event.payload[key]?.stringValue ?? ""))
        }

        return [
            "traceId": event.traceID ?? "",
            "spanId": event.spanID ?? "",
            "parentSpanId": event.parentSpanID ?? "",
            "name": event.stage ?? event.eventType,
            "kind": event.spanKind.rawValue,
            "startTimeUnixNano": unixNanos(event.startedAt ?? event.timestamp),
            "endTimeUnixNano": unixNanos(event.completedAt ?? event.timestamp),
            "attributes": attributes
        ]
    }

    private static func attribute(_ key: String, _ value: String) -> [String: Any] {
        [
            "key": key,
            "value": ["stringValue": value]
        ]
    }

    private static func unixNanos(_ date: Date) -> String {
        String(Int64(date.timeIntervalSince1970 * 1_000_000_000))
    }

    private static func fileDateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

