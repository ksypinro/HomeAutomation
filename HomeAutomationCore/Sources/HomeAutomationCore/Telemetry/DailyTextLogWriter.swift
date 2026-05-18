import Foundation

public actor DailyTextLogWriter {
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
            "home-automation-\(dateKey).txt",
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
        let timestamp = isoFormatter.string(from: event.timestamp)
        let tags = [
            tag("RUN", shortRunID(event.runID)),
            tag("INV", event.agentInvocationID),
            tag("OP", event.operation),
            tag("GRAPH", event.graphID),
            tag("ACTION", event.actionID),
            tag("COND", event.conditionID),
            tag("AGENT", event.agentID),
            tag("STAGE", event.stage),
            tag("EVENT", event.eventType)
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return "\(timestamp) \(tags) \(json)"
    }

    private static func tag(_ name: String, _ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return "[\(name):\(sanitizeTag(value))]"
    }

    private static func sanitizeTag(_ value: String) -> String {
        value
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func shortRunID(_ value: String?) -> String? {
        guard let value else { return nil }
        return String(value.prefix(8))
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

