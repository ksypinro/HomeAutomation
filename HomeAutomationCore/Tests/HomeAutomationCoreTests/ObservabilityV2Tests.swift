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
            agentInvocationID: "invocation-1",
            agentSessionID: "agent-session-1",
            agentRunID: 4,
            toolID: "findDeviceCandidates",
            toolSessionID: "tool-session-1",
            toolCallID: "tool-call-1"
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
        #expect(event.agentSessionID == "agent-session-1")
        #expect(event.agentRunID == 4)
        #expect(event.toolID == "findDeviceCandidates")
        #expect(event.toolSessionID == "tool-session-1")
        #expect(event.toolCallID == "tool-call-1")
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
    func agentInputOutputAndToolTelemetryIncludeTraceIdentity() async throws {
        struct ToolTrace: AgentToolTraceArguments {
            let agentID: String?
            let agentSessionID: String?
            let agentRunID: Int?
        }

        let sink = InMemoryTelemetrySink()
        let telemetry = HomeAutomationTelemetry(
            configuration: HomeAutomationTelemetryConfiguration(isEnabled: true),
            sinks: [sink]
        )
        let context = HomeAutomationTelemetryContext(
            traceID: "trace-2",
            spanID: "span-2",
            spanKind: .agentAttempt,
            runID: "run-2",
            agentID: "draftGeneration",
            agentInvocationID: "invocation-2",
            agentSessionID: "agent-session-2",
            agentRunID: 7
        )

        await HomeAutomationTelemetryScope.$current.withValue(context) {
            await telemetry.logAgentInput("input", inputType: "InputType")
            await telemetry.logAgentOutput("output", outputType: "OutputType")
            let call = await telemetry.startToolCall(
                toolID: "findDeviceCandidates",
                toolSessionID: "tool-session-2",
                arguments: "args",
                agentTrace: ToolTrace(
                    agentID: "draftGeneration",
                    agentSessionID: "agent-session-2",
                    agentRunID: 7
                )
            )
            await telemetry.finishToolCall(call, output: "tool-output")
        }

        let events = await sink.events()
        let agentInput = try #require(events.first { $0.eventType == "agent.input" })
        let agentOutput = try #require(events.first { $0.eventType == "agent.output" })
        let toolInput = try #require(events.first { $0.eventType == "tool.input" })
        let toolOutput = try #require(events.first { $0.eventType == "tool.output" })

        #expect(agentInput.agentID == "draftGeneration")
        #expect(agentInput.agentSessionID == "agent-session-2")
        #expect(agentInput.agentRunID == 7)
        #expect(agentInput.payload["agentSessionID"] == .string("agent-session-2"))
        #expect(agentInput.payload["agentRunID"] == .string("7"))
        #expect(agentOutput.agentSessionID == "agent-session-2")
        #expect(agentOutput.agentRunID == 7)

        #expect(toolInput.toolID == "findDeviceCandidates")
        #expect(toolInput.toolSessionID == "tool-session-2")
        #expect(toolInput.toolCallID != nil)
        #expect(toolInput.agentID == "draftGeneration")
        #expect(toolInput.agentSessionID == "agent-session-2")
        #expect(toolInput.agentRunID == 7)
        #expect(toolOutput.toolCallID == toolInput.toolCallID)
        #expect(toolOutput.spanID == toolInput.spanID)
    }

    @Test
    func foundationModelRespondCallSitesUseRecorder() throws {
        let packageRoot = try packageRootURL()
        let sources = packageRoot.appendingPathComponent("Sources", isDirectory: true)
        let files = try swiftFiles(under: sources)

        let offenders = try files.compactMap { file -> String? in
            let source = try String(contentsOf: file, encoding: .utf8)
            guard source.contains(".respond(") || source.contains("respond(") else { return nil }
            guard !source.contains("FoundationModelCallRecorder.record") else { return nil }
            return file.path.replacingOccurrences(of: packageRoot.path + "/", with: "")
        }

        #expect(offenders.isEmpty, "FoundationModel call sites missing recorder: \(offenders.joined(separator: ", "))")
    }

    @Test
    func productionToolArgumentsExposeAgentTraceFields() throws {
        let packageRoot = try packageRootURL()
        let sources = packageRoot.appendingPathComponent("Sources/HomeAutomationAgents", isDirectory: true)
        let toolFiles = try swiftFiles(under: sources).filter { file in
            let source = try String(contentsOf: file, encoding: .utf8)
            return source.contains(": Tool")
        }

        let offenders = try toolFiles.compactMap { file -> String? in
            let source = try String(contentsOf: file, encoding: .utf8)
            guard source.contains("struct Arguments") else { return nil }
            let hasRuntimeIdentity = source.contains("toolSessionID") && source.contains("toolID")
            let hasTraceFields = source.contains("agentID: String?") &&
                source.contains("agentSessionID: String?") &&
                source.contains("agentRunID: Int?")
            let hasTraceProtocol = source.contains("AgentToolTraceArguments")
            guard hasRuntimeIdentity && hasTraceFields && hasTraceProtocol else {
                return file.path.replacingOccurrences(of: packageRoot.path + "/", with: "")
            }
            return nil
        }

        #expect(offenders.isEmpty, "Tool tracing fields missing: \(offenders.joined(separator: ", "))")
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

    private func swiftFiles(under directory: URL) throws -> [URL] {
        try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
    }
}
