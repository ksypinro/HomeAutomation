import Foundation
import HomeAutomationCore
import Testing

@Suite
struct ObservabilityV2Tests {
    @Test
    func typedTelemetryEmitsSchemaV2EventsToInMemorySink() async throws {
        let sink = InMemoryTelemetrySink()
        let telemetry = HomeAutomationTelemetry(
            configuration: HomeAutomationTelemetryConfiguration(isEnabled: true),
            sinks: [sink]
        )
        let context = HomeAutomationTelemetryContext(
            traceID: "trace-1",
            spanID: "span-1",
            parentSpanID: "parent-1",
            spanKind: .agentAttempt,
            runID: "run-1",
            graphID: "direct-command-graph",
            stage: "draftGeneration",
            agentID: "draftGeneration",
            agentInvocationID: "invocation-1"
        )

        await telemetry.log(
            "agent.attempt.completed",
            context: context,
            status: .completed,
            spanKind: .agentAttempt,
            startedAt: Date(),
            durationMs: 12,
            payload: TelemetryPayload(values: [
                "modelCallCount": .int(1),
                "fallbackUsed": .bool(false)
            ])
        )

        let events = await sink.events()
        let event = try #require(events.first)
        #expect(event.schemaVersion == 2)
        #expect(event.traceID == "trace-1")
        #expect(event.spanID == "span-1")
        #expect(event.parentSpanID == "parent-1")
        #expect(event.spanKind == .agentAttempt)
        #expect(event.status == .completed)
        #expect(event.payload["modelCallCount"] == .int(1))
    }

    @Test
    func telemetrySinkFanOutAndFlushAreNonFatal() async {
        let first = InMemoryTelemetrySink()
        let second = InMemoryTelemetrySink()
        let telemetry = HomeAutomationTelemetry(
            configuration: HomeAutomationTelemetryConfiguration(isEnabled: true),
            sinks: [first, second]
        )

        await telemetry.log("test.event", status: .completed)
        await telemetry.flush()

        #expect(await first.events().count == 1)
        #expect(await second.events().count == 1)
        #expect(await telemetry.sinkStats().map(\.appendedCount).reduce(0, +) == 2)
    }

    @Test
    func foundationModelRespondCallSitesUseRecorder() throws {
        let packageRoot = try packageRootURL()
        let sources = packageRoot.appendingPathComponent("Sources", isDirectory: true)
        let files = FileManager.default.enumerator(
            at: sources,
            includingPropertiesForKeys: nil
        )?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []

        let offenders = try files.compactMap { file -> String? in
            let source = try String(contentsOf: file, encoding: .utf8)
            guard source.contains(".respond(") || source.contains("respond(") else { return nil }
            guard !source.contains("FoundationModelCallRecorder.record") else { return nil }
            return file.path.replacingOccurrences(of: packageRoot.path + "/", with: "")
        }

        #expect(offenders.isEmpty, "FoundationModel call sites missing recorder: \(offenders.joined(separator: ", "))")
    }

    private func packageRootURL() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let candidate = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
