import Foundation
import FoundationModels
import HomeAutomationCore
import os

/// Optional Foundation Models tool that exposes the deterministic operation detector
/// as semantic analysis. The model may call this tool when it wants a structured
/// rule-based reading of the command, but the model remains responsible for the
/// final operation classification.
public struct OperationSemanticAnalyzerTool: Tool, ToolRuntimeIdentifiable {
    public let name = "analyzeOperationSemantics"
    public var toolID: String { name }
    public let toolSessionID = UUID().uuidString
    public let description = """
        Runs deterministic semantic analysis for a smart-home command and returns \
        the suggested operation, domain, confidence, and reason. Use this tool only \
        when extra semantic grounding would help; do not blindly copy the output.
        """

    private let commandText: String
    private let analyze: @Sendable (String) -> HomeOperationDetectionResult

    public init(
        commandText: String,
        analyze: @escaping @Sendable (String) -> HomeOperationDetectionResult
    ) {
        self.commandText = commandText
        self.analyze = analyze
    }

    @Generable
    public struct Arguments: AgentToolTraceArguments {
        @Guide(description: "Optional command text to analyze. Leave empty to analyze the current user command.")
        public let text: String?
        @Guide(description: "Tracing only: caller agent ID. Pass the value provided in tool trace instructions.")
        public let agentID: String?
        @Guide(description: "Tracing only: caller agent session ID. Pass the value provided in tool trace instructions.")
        public let agentSessionID: String?
        @Guide(description: "Tracing only: caller agent run ID. Pass the value provided in tool trace instructions.")
        public let agentRunID: Int?

        public init(
            text: String? = nil,
            agentID: String? = nil,
            agentSessionID: String? = nil,
            agentRunID: Int? = nil
        ) {
            self.text = text
            self.agentID = agentID
            self.agentSessionID = agentSessionID
            self.agentRunID = agentRunID
        }
    }

    public func call(arguments: Arguments) async throws -> String {
        let callContext = await agentStartToolTelemetry(toolID: toolID, toolSessionID: toolSessionID, arguments: arguments)

        let text = arguments.text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? commandText
        let result = analyze(text)
        let output = """
        semanticAnalysis:
        command: \(text)
        domain: \(result.domain)
        operation: \(result.operation.rawValue)
        confidence: \(result.confidence)
        reason: \(result.reason)
        """
        await HomeAutomationTelemetry.shared.finishToolCall(
            callContext,
            output: output,
            durationMs: Date().timeIntervalSince(callContext.startedAt) * 1_000
        )
        return output
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
