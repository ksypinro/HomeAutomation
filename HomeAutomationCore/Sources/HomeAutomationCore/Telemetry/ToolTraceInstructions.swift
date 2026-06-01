import Foundation

public enum HomeAutomationToolTraceInstructions {
    public static func currentInstructionText(
        context: HomeAutomationTelemetryContext? = HomeAutomationTelemetryScope.current
    ) -> String? {
        guard let agentID = context?.agentID,
              let agentSessionID = context?.agentSessionID,
              let agentRunID = context?.agentRunID else {
            return nil
        }
        return """

        Tool tracing requirement:
        - Include agentID "\(agentID)" in every tool call argument object.
        - Include agentSessionID "\(agentSessionID)" in every tool call argument object.
        - Include agentRunID \(agentRunID) in every tool call argument object.
        These fields are for telemetry only and must not change the user-facing command resolution.
        """
    }

    public static func append(to instructionText: String) -> String {
        guard let traceInstructions = currentInstructionText() else {
            return instructionText
        }
        return instructionText + traceInstructions
    }
}
