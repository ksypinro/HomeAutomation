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

    public init(
        isEnabled: Bool = true,
        logDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Logs", isDirectory: true),
        payloadMode: HomeAutomationTelemetryPayloadMode = .cappedPayload,
        maxPayloadCharacters: Int = 8_000
    ) {
        self.isEnabled = isEnabled
        self.logDirectoryURL = logDirectoryURL
        self.payloadMode = payloadMode
        self.maxPayloadCharacters = max(0, maxPayloadCharacters)
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

        return HomeAutomationTelemetryConfiguration(
            isEnabled: enabled,
            logDirectoryURL: directory,
            payloadMode: mode,
            maxPayloadCharacters: maxCharacters
        )
    }
}

public struct HomeAutomationTelemetryContext: Sendable, Codable, Hashable {
    public let runID: String?
    public let operation: String?
    public let graphID: String?
    public let stage: String?
    public let graphNodeID: String?
    public let agentID: String?
    public let agentInvocationID: String?
    public let actionID: String?
    public let conditionID: String?
    public let attempt: Int?
    public let runtimeMode: String?

    public init(
        runID: String? = nil,
        operation: String? = nil,
        graphID: String? = nil,
        stage: String? = nil,
        graphNodeID: String? = nil,
        agentID: String? = nil,
        agentInvocationID: String? = nil,
        actionID: String? = nil,
        conditionID: String? = nil,
        attempt: Int? = nil,
        runtimeMode: String? = nil
    ) {
        self.runID = runID
        self.operation = operation
        self.graphID = graphID
        self.stage = stage
        self.graphNodeID = graphNodeID
        self.agentID = agentID
        self.agentInvocationID = agentInvocationID
        self.actionID = actionID
        self.conditionID = conditionID
        self.attempt = attempt
        self.runtimeMode = runtimeMode
    }

    public func merging(
        runID: String? = nil,
        operation: String? = nil,
        graphID: String? = nil,
        stage: String? = nil,
        graphNodeID: String? = nil,
        agentID: String? = nil,
        agentInvocationID: String? = nil,
        actionID: String? = nil,
        conditionID: String? = nil,
        attempt: Int? = nil,
        runtimeMode: String? = nil
    ) -> HomeAutomationTelemetryContext {
        HomeAutomationTelemetryContext(
            runID: runID ?? self.runID,
            operation: operation ?? self.operation,
            graphID: graphID ?? self.graphID,
            stage: stage ?? self.stage,
            graphNodeID: graphNodeID ?? self.graphNodeID,
            agentID: agentID ?? self.agentID,
            agentInvocationID: agentInvocationID ?? self.agentInvocationID,
            actionID: actionID ?? self.actionID,
            conditionID: conditionID ?? self.conditionID,
            attempt: attempt ?? self.attempt,
            runtimeMode: runtimeMode ?? self.runtimeMode
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
        self.actionID = context?.actionID
        self.conditionID = context?.conditionID
        self.attempt = context?.attempt
        self.runtimeMode = context?.runtimeMode
        self.status = status
        self.durationMs = durationMs
        self.payload = payload
    }
}

public actor HomeAutomationTelemetry {
    public static let shared = HomeAutomationTelemetry()

    private let configuration: HomeAutomationTelemetryConfiguration
    private let writer: DailyTextLogWriter
    private let jsonlWriter: DailyJSONLLogWriter
    private let redactor: TelemetryRedactor

    public init(configuration: HomeAutomationTelemetryConfiguration = .environment()) {
        self.configuration = configuration
        self.writer = DailyTextLogWriter(directoryURL: configuration.logDirectoryURL)
        self.jsonlWriter = DailyJSONLLogWriter(directoryURL: configuration.logDirectoryURL)
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
        let event = HomeAutomationTelemetryEvent(
            eventType: eventType,
            context: context,
            status: status,
            durationMs: durationMs,
            payload: redactor.redact(payload)
        )
        await writer.append(event)
        await jsonlWriter.append(event)
    }

    public func logAgentInput(_ input: String, inputType: String) async {
        await log(
            "agent.input",
            payload: [
                "inputType": inputType,
                "input": input
            ]
        )
    }

    public func logAgentOutput(_ output: String, outputType: String, durationMs: Double? = nil) async {
        await log(
            "agent.output",
            status: "completed",
            durationMs: durationMs,
            payload: [
                "outputType": outputType,
                "output": output
            ]
        )
    }

    public func logToolInput(toolName: String, arguments: String) async {
        let context = HomeAutomationTelemetryScope.current?.merging(stage: toolName)
        await log(
            "tool.input",
            context: context,
            payload: [
                "toolName": toolName,
                "arguments": arguments
            ]
        )
    }

    public func logToolOutput(toolName: String, output: String, durationMs: Double? = nil) async {
        let context = HomeAutomationTelemetryScope.current?.merging(stage: toolName)
        await log(
            "tool.output",
            context: context,
            status: "completed",
            durationMs: durationMs,
            payload: [
                "toolName": toolName,
                "output": output,
                "outputCharacterCount": String(output.count)
            ]
        )
    }
}
