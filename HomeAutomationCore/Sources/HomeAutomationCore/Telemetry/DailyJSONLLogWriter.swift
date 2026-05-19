import Foundation

public actor DailyJSONLLogWriter {
    private let directoryURL: URL
    private var currentDateKey: String?
    private var fileHandle: FileHandle?

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    deinit {
        try? fileHandle?.close()
    }

    public func append(_ event: HomeAutomationTelemetryEvent) async {
        do {
            let line = try Self.render(event)
            let handle = try fileHandle(for: event.timestamp)
            if let data = (line + "\n").data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } catch {
            // Telemetry must never break command resolution.
        }
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
            "home-automation-\(dateKey).jsonl",
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

    private static func render(_ event: HomeAutomationTelemetryEvent) throws -> String {
        var object: [String: Any] = [
            "schemaVersion": event.schemaVersion,
            "timestamp": isoFormatter.string(from: event.timestamp),
            "eventType": event.eventType,
            "payload": event.payload
        ]
        set(&object, "runID", event.runID)
        set(&object, "operation", event.operation)
        set(&object, "graphID", event.graphID)
        set(&object, "stage", event.stage)
        set(&object, "graphNodeID", event.graphNodeID)
        set(&object, "agentID", event.agentID)
        set(&object, "agentInvocationID", event.agentInvocationID)
        set(&object, "actionID", event.actionID)
        set(&object, "conditionID", event.conditionID)
        set(&object, "attempt", event.attempt)
        set(&object, "runtimeMode", event.runtimeMode)
        set(&object, "status", event.status)
        set(&object, "durationMs", event.durationMs)

        promoteList("selectedCandidateIDs", from: event.payload, into: &object)
        promoteString("selectedCapability", from: event.payload, into: &object)
        promoteString("selectedCommand", from: event.payload, into: &object)
        promoteString("targetDeviceID", from: event.payload, into: &object)
        promoteString("validationResult", from: event.payload, into: &object)
        promoteString("finalOutcome", from: event.payload, into: &object)
        promoteString("toolName", from: event.payload, into: &object)
        promoteString("modelCallID", from: event.payload, into: &object)

        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func set(_ object: inout [String: Any], _ key: String, _ value: String?) {
        guard let value else { return }
        object[key] = value
    }

    private static func set(_ object: inout [String: Any], _ key: String, _ value: Int?) {
        guard let value else { return }
        object[key] = value
    }

    private static func set(_ object: inout [String: Any], _ key: String, _ value: Double?) {
        guard let value else { return }
        object[key] = value
    }

    private static func promoteString(_ key: String, from payload: [String: String], into object: inout [String: Any]) {
        guard let value = payload[key], !value.isEmpty else { return }
        object[key] = value
    }

    private static func promoteList(_ key: String, from payload: [String: String], into object: inout [String: Any]) {
        guard let value = payload[key], !value.isEmpty else { return }
        object[key] = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func fileDateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static var isoFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

