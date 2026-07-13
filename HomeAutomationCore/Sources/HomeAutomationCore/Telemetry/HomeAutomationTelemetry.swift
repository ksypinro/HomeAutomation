import Foundation

public enum HomeAutomationTelemetryPayloadMode: String, Sendable, Codable {
    case metadataOnly
    case cappedPayload
    case fullPayload
}

public struct HomeAutomationTelemetryConfiguration: Sendable {
    public let isEnabled: Bool
    public let logDirectoryURL: URL
    public let payloadMode: HomeAutomationTelemetryPayloadMode
    public let maxPayloadCharacters: Int
    public let openTelemetryJSONEnabled: Bool

    public init(
        isEnabled: Bool = true,
        logDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Logs", isDirectory: true),
        payloadMode: HomeAutomationTelemetryPayloadMode = .cappedPayload,
        maxPayloadCharacters: Int = 8_000,
        openTelemetryJSONEnabled: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.logDirectoryURL = logDirectoryURL
        self.payloadMode = payloadMode
        self.maxPayloadCharacters = max(0, maxPayloadCharacters)
        self.openTelemetryJSONEnabled = openTelemetryJSONEnabled
    }

    public static func environment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> HomeAutomationTelemetryConfiguration {
        let enabled = environment["HOME_AUTOMATION_LOGGING_ENABLED"]
            .map { value in
                !["0", "false", "no", "off"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            } ?? true
        let directory = environment["HOME_AUTOMATION_LOG_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Logs", isDirectory: true)
        let mode = environment["HOME_AUTOMATION_LOG_PAYLOAD_MODE"]
            .flatMap(HomeAutomationTelemetryPayloadMode.init(rawValue:)) ?? .cappedPayload
        let maxCharacters = environment["HOME_AUTOMATION_LOG_MAX_PAYLOAD_CHARS"]
            .flatMap(Int.init) ?? 8_000
        let otelEnabled = environment["HOME_AUTOMATION_OTEL_JSON_ENABLED"]
            .map { value in
                ["1", "true", "yes", "on"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            } ?? false

        return HomeAutomationTelemetryConfiguration(
            isEnabled: enabled,
            logDirectoryURL: directory,
            payloadMode: mode,
            maxPayloadCharacters: maxCharacters,
            openTelemetryJSONEnabled: otelEnabled
        )
    }
}

public struct HomeAutomationTelemetryContext: Sendable, Codable, Hashable {
    public let traceID: String?
    public let spanID: String?
    public let parentSpanID: String?
    public let spanKind: TelemetrySpanKind?
    public let runID: String?
    public let operation: String?
    public let graphID: String?
    public let stage: String?
    public let graphNodeID: String?
    public let agentID: String?
    public let agentInvocationID: String?
    public let agentSessionID: String?
    public let agentRunID: Int?
    public let toolID: String?
    public let toolSessionID: String?
    public let toolCallID: String?
    public let componentKind: String?
    public let componentID: String?
    public let actionID: String?
    public let conditionID: String?
    public let attempt: Int?
    public let runtimeMode: String?
    public let foundationModelArm: FoundationModelCallArm?
    public let foundationModelJobID: String?
    public let foundationModelJobKind: FoundationModelJobKind?
    public let foundationModelEscalationChain: [FoundationModelEscalationStep]

    public init(
        traceID: String? = nil,
        spanID: String? = nil,
        parentSpanID: String? = nil,
        spanKind: TelemetrySpanKind? = nil,
        runID: String? = nil,
        operation: String? = nil,
        graphID: String? = nil,
        stage: String? = nil,
        graphNodeID: String? = nil,
        agentID: String? = nil,
        agentInvocationID: String? = nil,
        agentSessionID: String? = nil,
        agentRunID: Int? = nil,
        toolID: String? = nil,
        toolSessionID: String? = nil,
        toolCallID: String? = nil,
        componentKind: String? = nil,
        componentID: String? = nil,
        actionID: String? = nil,
        conditionID: String? = nil,
        attempt: Int? = nil,
        runtimeMode: String? = nil,
        foundationModelArm: FoundationModelCallArm? = nil,
        foundationModelJobID: String? = nil,
        foundationModelJobKind: FoundationModelJobKind? = nil,
        foundationModelEscalationChain: [FoundationModelEscalationStep] = []
    ) {
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
        self.agentSessionID = agentSessionID
        self.agentRunID = agentRunID
        self.toolID = toolID
        self.toolSessionID = toolSessionID
        self.toolCallID = toolCallID
        self.componentKind = componentKind
        self.componentID = componentID
        self.actionID = actionID
        self.conditionID = conditionID
        self.attempt = attempt
        self.runtimeMode = runtimeMode
        self.foundationModelArm = foundationModelArm
        self.foundationModelJobID = foundationModelJobID
        self.foundationModelJobKind = foundationModelJobKind
        self.foundationModelEscalationChain = foundationModelEscalationChain
    }

    public func merging(
        traceID: String? = nil,
        spanID: String? = nil,
        parentSpanID: String? = nil,
        spanKind: TelemetrySpanKind? = nil,
        runID: String? = nil,
        operation: String? = nil,
        graphID: String? = nil,
        stage: String? = nil,
        graphNodeID: String? = nil,
        agentID: String? = nil,
        agentInvocationID: String? = nil,
        agentSessionID: String? = nil,
        agentRunID: Int? = nil,
        toolID: String? = nil,
        toolSessionID: String? = nil,
        toolCallID: String? = nil,
        componentKind: String? = nil,
        componentID: String? = nil,
        actionID: String? = nil,
        conditionID: String? = nil,
        attempt: Int? = nil,
        runtimeMode: String? = nil,
        foundationModelArm: FoundationModelCallArm? = nil,
        foundationModelJobID: String? = nil,
        foundationModelJobKind: FoundationModelJobKind? = nil,
        foundationModelEscalationChain: [FoundationModelEscalationStep]? = nil
    ) -> HomeAutomationTelemetryContext {
        HomeAutomationTelemetryContext(
            traceID: traceID ?? self.traceID,
            spanID: spanID ?? self.spanID,
            parentSpanID: parentSpanID ?? self.parentSpanID,
            spanKind: spanKind ?? self.spanKind,
            runID: runID ?? self.runID,
            operation: operation ?? self.operation,
            graphID: graphID ?? self.graphID,
            stage: stage ?? self.stage,
            graphNodeID: graphNodeID ?? self.graphNodeID,
            agentID: agentID ?? self.agentID,
            agentInvocationID: agentInvocationID ?? self.agentInvocationID,
            agentSessionID: agentSessionID ?? self.agentSessionID,
            agentRunID: agentRunID ?? self.agentRunID,
            toolID: toolID ?? self.toolID,
            toolSessionID: toolSessionID ?? self.toolSessionID,
            toolCallID: toolCallID ?? self.toolCallID,
            componentKind: componentKind ?? self.componentKind,
            componentID: componentID ?? self.componentID,
            actionID: actionID ?? self.actionID,
            conditionID: conditionID ?? self.conditionID,
            attempt: attempt ?? self.attempt,
            runtimeMode: runtimeMode ?? self.runtimeMode,
            foundationModelArm: foundationModelArm ?? self.foundationModelArm,
            foundationModelJobID: foundationModelJobID ?? self.foundationModelJobID,
            foundationModelJobKind: foundationModelJobKind ?? self.foundationModelJobKind,
            foundationModelEscalationChain: foundationModelEscalationChain ?? self.foundationModelEscalationChain
        )
    }
}

public enum HomeAutomationTelemetryScope {
    @TaskLocal public static var current: HomeAutomationTelemetryContext?
}

public struct HomeAutomationTelemetryEvent: Sendable, Codable {
    public let schemaVersion: Int
    public let timestamp: Date
    public let eventType: String
    public let runID: String?
    public let operation: String?
    public let graphID: String?
    public let stage: String?
    public let graphNodeID: String?
    public let agentID: String?
    public let agentInvocationID: String?
    public let agentSessionID: String?
    public let agentRunID: Int?
    public let toolID: String?
    public let toolSessionID: String?
    public let toolCallID: String?
    public let actionID: String?
    public let conditionID: String?
    public let attempt: Int?
    public let runtimeMode: String?
    public let status: String?
    public let durationMs: Double?
    public let payload: [String: String]

    public init(
        eventType: String,
        context: HomeAutomationTelemetryContext? = HomeAutomationTelemetryScope.current,
        status: String? = nil,
        durationMs: Double? = nil,
        payload: [String: String] = [:]
    ) {
        self.schemaVersion = 1
        self.timestamp = Date()
        self.eventType = eventType
        self.runID = context?.runID
        self.operation = context?.operation
        self.graphID = context?.graphID
        self.stage = context?.stage
        self.graphNodeID = context?.graphNodeID
        self.agentID = context?.agentID
        self.agentInvocationID = context?.agentInvocationID
        self.agentSessionID = context?.agentSessionID
        self.agentRunID = context?.agentRunID
        self.toolID = context?.toolID
        self.toolSessionID = context?.toolSessionID
        self.toolCallID = context?.toolCallID
        self.actionID = context?.actionID
        self.conditionID = context?.conditionID
        self.attempt = context?.attempt
        self.runtimeMode = context?.runtimeMode
        self.status = status
        self.durationMs = durationMs
        self.payload = payload
    }

    public var observabilityEvent: ObservabilityEvent {
        ObservabilityEvent(
            eventType: eventType,
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            spanKind: .event,
            runID: runID,
            operation: operation,
            graphID: graphID,
            stage: stage,
            graphNodeID: graphNodeID,
            agentID: agentID,
            agentInvocationID: agentInvocationID,
            agentSessionID: agentSessionID,
            agentRunID: agentRunID,
            toolID: toolID,
            toolSessionID: toolSessionID,
            toolCallID: toolCallID,
            actionID: actionID,
            conditionID: conditionID,
            attempt: attempt,
            runtimeMode: runtimeMode,
            status: status.flatMap(TelemetryStatus.init(rawValue:)),
            completedAt: timestamp,
            durationMs: durationMs,
            payload: TelemetryPayload(strings: payload)
        )
    }
}

public actor HomeAutomationTelemetry {
    public static let shared = HomeAutomationTelemetry()

    private let configuration: HomeAutomationTelemetryConfiguration
    private let sinks: [any TelemetrySink]
    private var temporarySinks: [UUID: any TelemetrySink] = [:]
    private let redactor: TelemetryRedactor

    public init(
        configuration: HomeAutomationTelemetryConfiguration = .environment(),
        sinks: [any TelemetrySink]? = nil
    ) {
        self.configuration = configuration
        if let sinks {
            self.sinks = sinks
        } else {
            var defaultSinks: [any TelemetrySink] = [
                DailyTextLogWriter(directoryURL: configuration.logDirectoryURL),
                DailyJSONLLogWriter(directoryURL: configuration.logDirectoryURL)
            ]
            if configuration.openTelemetryJSONEnabled {
                defaultSinks.append(OpenTelemetryJSONSink(directoryURL: configuration.logDirectoryURL))
            }
            self.sinks = defaultSinks
        }
        self.redactor = TelemetryRedactor(
            mode: configuration.payloadMode,
            maxPayloadCharacters: configuration.maxPayloadCharacters
        )
    }

    public func log(
        _ eventType: String,
        context: HomeAutomationTelemetryContext? = HomeAutomationTelemetryScope.current,
        status: String? = nil,
        durationMs: Double? = nil,
        payload: [String: String] = [:]
    ) async {
        guard configuration.isEnabled else { return }
        let telemetryPayload = redactor.redact(TelemetryPayload(strings: payload))
        let normalizedStatus = status.flatMap(TelemetryStatus.init(rawValue:))
        let event = ObservabilityEvent(
            eventType: eventType,
            traceID: context?.traceID,
            spanID: context?.spanID,
            parentSpanID: context?.parentSpanID,
            spanKind: context?.spanKind ?? .event,
            runID: context?.runID,
            operation: context?.operation,
            graphID: context?.graphID,
            stage: context?.stage,
            graphNodeID: context?.graphNodeID,
            agentID: context?.agentID,
            agentInvocationID: context?.agentInvocationID,
            agentSessionID: context?.agentSessionID,
            agentRunID: context?.agentRunID,
            toolID: context?.toolID,
            toolSessionID: context?.toolSessionID,
            toolCallID: context?.toolCallID,
            componentKind: context?.componentKind,
            componentID: context?.componentID,
            actionID: context?.actionID,
            conditionID: context?.conditionID,
            attempt: context?.attempt,
            runtimeMode: context?.runtimeMode,
            status: normalizedStatus,
            completedAt: Date(),
            durationMs: durationMs,
            payload: telemetryPayload
        )
        for sink in allSinks {
            await sink.append(event)
        }
    }

    public func log(
        _ eventType: String,
        context: HomeAutomationTelemetryContext? = HomeAutomationTelemetryScope.current,
        status: TelemetryStatus? = nil,
        spanKind: TelemetrySpanKind? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = Date(),
        durationMs: Double? = nil,
        payload: TelemetryPayload = TelemetryPayload()
    ) async {
        guard configuration.isEnabled else { return }
        let mergedContext = spanKind.map { context?.merging(spanKind: $0) } ?? context
        let event = ObservabilityEvent(
            eventType: eventType,
            traceID: mergedContext?.traceID,
            spanID: mergedContext?.spanID,
            parentSpanID: mergedContext?.parentSpanID,
            spanKind: mergedContext?.spanKind ?? spanKind ?? .event,
            runID: mergedContext?.runID,
            operation: mergedContext?.operation,
            graphID: mergedContext?.graphID,
            stage: mergedContext?.stage,
            graphNodeID: mergedContext?.graphNodeID,
            agentID: mergedContext?.agentID,
            agentInvocationID: mergedContext?.agentInvocationID,
            agentSessionID: mergedContext?.agentSessionID,
            agentRunID: mergedContext?.agentRunID,
            toolID: mergedContext?.toolID,
            toolSessionID: mergedContext?.toolSessionID,
            toolCallID: mergedContext?.toolCallID,
            componentKind: mergedContext?.componentKind,
            componentID: mergedContext?.componentID,
            actionID: mergedContext?.actionID,
            conditionID: mergedContext?.conditionID,
            attempt: mergedContext?.attempt,
            runtimeMode: mergedContext?.runtimeMode,
            status: status,
            startedAt: startedAt,
            completedAt: completedAt,
            durationMs: durationMs,
            payload: redactor.redact(payload)
        )
        for sink in allSinks {
            await sink.append(event)
        }
    }

    public func flush() async {
        for sink in allSinks {
            await sink.flush()
        }
    }

    public func sinkStats() async -> [TelemetrySinkStats] {
        var values: [TelemetrySinkStats] = []
        for sink in allSinks {
            values.append(await sink.stats())
        }
        return values
    }

    @discardableResult
    public func installTemporarySink(_ sink: any TelemetrySink) -> UUID {
        let id = UUID()
        temporarySinks[id] = sink
        return id
    }

    public func removeTemporarySink(_ id: UUID) {
        temporarySinks[id] = nil
    }

    public func withTemporarySink<Value: Sendable>(
        _ sink: any TelemetrySink,
        operation: @Sendable () async throws -> Value
    ) async rethrows -> Value {
        let id = installTemporarySink(sink)
        do {
            let value = try await operation()
            await sink.flush()
            removeTemporarySink(id)
            return value
        } catch {
            await sink.flush()
            removeTemporarySink(id)
            throw error
        }
    }

    private var allSinks: [any TelemetrySink] {
        sinks + Array(temporarySinks.values)
    }

    public func logAgentInput(_ input: String, inputType: String) async {
        let context = HomeAutomationTelemetryScope.current
        await log(
            "agent.input",
            context: context,
            payload: [
                "agentID": context?.agentID ?? "",
                "agentSessionID": context?.agentSessionID ?? "",
                "agentRunID": context?.agentRunID.map(String.init) ?? "",
                "inputType": inputType,
                "input": input
            ]
        )
    }

    public func logAgentOutput(_ output: String, outputType: String, durationMs: Double? = nil) async {
        let context = HomeAutomationTelemetryScope.current
        await log(
            "agent.output",
            context: context,
            status: "completed",
            durationMs: durationMs,
            payload: [
                "agentID": context?.agentID ?? "",
                "agentSessionID": context?.agentSessionID ?? "",
                "agentRunID": context?.agentRunID.map(String.init) ?? "",
                "outputType": outputType,
                "output": output
            ]
        )
    }

    public func startToolCall(
        toolID: String,
        toolSessionID: String? = nil,
        toolCallID: String = UUID().uuidString,
        arguments: String,
        agentTrace: (any AgentToolTraceArguments)? = nil
    ) async -> ToolTelemetryCallContext {
        let startedAt = Date()
        let parent = HomeAutomationTelemetryScope.current
        let effectiveAgentID = agentTrace?.agentID ?? parent?.agentID
        let effectiveAgentSessionID = agentTrace?.agentSessionID ?? parent?.agentSessionID
        let effectiveAgentRunID = agentTrace?.agentRunID ?? parent?.agentRunID
        let context = (parent ?? HomeAutomationTelemetryContext()).merging(
            spanID: TelemetryTraceContext.makeSpanID(),
            parentSpanID: parent?.spanID,
            spanKind: .toolCall,
            stage: toolID,
            agentID: effectiveAgentID,
            agentSessionID: effectiveAgentSessionID,
            agentRunID: effectiveAgentRunID,
            toolID: toolID,
            toolSessionID: toolSessionID,
            toolCallID: toolCallID
        )
        await log(
            "tool.input",
            context: context,
            status: .running,
            spanKind: .toolCall,
            startedAt: startedAt,
            completedAt: nil,
            payload: TelemetryPayload(values: [
                "toolID": .string(toolID),
                "toolName": .string(toolID),
                "toolSessionID": .string(toolSessionID ?? ""),
                "toolCallID": .string(toolCallID),
                "agentID": .string(effectiveAgentID ?? ""),
                "agentSessionID": .string(effectiveAgentSessionID ?? ""),
                "agentRunID": effectiveAgentRunID.map(TelemetryValue.int) ?? .null,
                "arguments": .string(arguments)
            ], privacy: [
                "toolSessionID": .internalID,
                "toolCallID": .internalID,
                "agentSessionID": .internalID
            ])
        )
        return ToolTelemetryCallContext(
            startedAt: startedAt,
            telemetryContext: context,
            toolCallID: toolCallID
        )
    }

    public func finishToolCall(
        _ callContext: ToolTelemetryCallContext,
        output: String,
        durationMs: Double? = nil
    ) async {
        let context = callContext.telemetryContext
        await log(
            "tool.output",
            context: context,
            status: .completed,
            spanKind: .toolCall,
            startedAt: callContext.startedAt,
            completedAt: Date(),
            durationMs: durationMs,
            payload: TelemetryPayload(values: [
                "toolID": .string(context.toolID ?? ""),
                "toolName": .string(context.toolID ?? ""),
                "toolSessionID": .string(context.toolSessionID ?? ""),
                "toolCallID": .string(callContext.toolCallID),
                "agentID": .string(context.agentID ?? ""),
                "agentSessionID": .string(context.agentSessionID ?? ""),
                "agentRunID": context.agentRunID.map(TelemetryValue.int) ?? .null,
                "output": .string(output),
                "outputCharacterCount": .int(output.count)
            ], privacy: [
                "toolSessionID": .internalID,
                "toolCallID": .internalID,
                "agentSessionID": .internalID
            ])
        )
    }

    public func logToolInput(toolName: String, arguments: String) async {
        _ = await startToolCall(toolID: toolName, arguments: arguments)
    }

    public func logToolOutput(toolName: String, output: String, durationMs: Double? = nil) async {
        let toolCallID = UUID().uuidString
        let callContext = ToolTelemetryCallContext(
            startedAt: Date(),
            telemetryContext: (HomeAutomationTelemetryScope.current ?? HomeAutomationTelemetryContext()).merging(
                spanID: TelemetryTraceContext.makeSpanID(),
                parentSpanID: HomeAutomationTelemetryScope.current?.spanID,
                spanKind: .toolCall,
                stage: toolName,
                toolID: toolName,
                toolCallID: toolCallID
            ),
            toolCallID: toolCallID
        )
        await finishToolCall(callContext, output: output, durationMs: durationMs)
    }
}
