import Foundation
import HomeAutomationCore

public struct EvaluationTraceCaptureOutput<Value: Sendable>: Sendable {
    public let value: Value
    public let events: [ObservabilityEvent]
    public let normalizedTrace: NormalizedTrace

    public init(value: Value, events: [ObservabilityEvent], normalizedTrace: NormalizedTrace) {
        self.value = value
        self.events = events
        self.normalizedTrace = normalizedTrace
    }
}

public struct EvaluationTraceCapture: Sendable {
    private let normalizer: TraceNormalizer

    public init(normalizer: TraceNormalizer = TraceNormalizer()) {
        self.normalizer = normalizer
    }

    public func capture<Value: Sendable>(
        caseID: String,
        operation: @Sendable () async throws -> Value
    ) async throws -> EvaluationTraceCaptureOutput<Value> {
        let sink = InMemoryTelemetrySink()
        let value = try await HomeAutomationTelemetry.shared.withTemporarySink(sink) {
            try await operation()
        }
        await HomeAutomationTelemetry.shared.flush()
        let events = await sink.events()
        return EvaluationTraceCaptureOutput(
            value: value,
            events: events,
            normalizedTrace: normalizer.normalize(events, caseID: caseID)
        )
    }

    public func writeActualTrace(
        _ events: [ObservabilityEvent],
        caseID: String,
        to directoryURL: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let url = directoryURL.appendingPathComponent("\(caseID).jsonl")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let lines = try events.map { event -> String in
            let data = try encoder.encode(event)
            return String(data: data, encoding: .utf8) ?? "{}"
        }.joined(separator: "\n")
        try lines.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
