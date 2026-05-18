import Foundation
import HomeAutomationCore
import Testing

@Suite
struct TelemetryTests {
    @Test
    func dailyWriterIncludesFilterableAgentAndInvocationTags() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("home-automation-telemetry-\(UUID().uuidString)", isDirectory: true)
        let telemetry = HomeAutomationTelemetry(
            configuration: HomeAutomationTelemetryConfiguration(
                isEnabled: true,
                logDirectoryURL: directory,
                payloadMode: .cappedPayload,
                maxPayloadCharacters: 16
            )
        )
        let context = HomeAutomationTelemetryContext(
            runID: "12345678-ABCD-4DEF-9012-123456789ABC",
            operation: "automationCreation",
            graphID: "automation-creation-graph",
            stage: "automationActionResolution:a1/draftGeneration",
            graphNodeID: "draftGeneration",
            agentID: "draftGeneration",
            agentInvocationID: "12345678-a1-draftGeneration-01",
            actionID: "a1",
            attempt: 1,
            runtimeMode: "graph"
        )

        await telemetry.log(
            "agent.output",
            context: context,
            status: "completed",
            payload: [
                "output": String(repeating: "x", count: 32)
            ]
        )

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let file = try #require(files.first)
        let text = try String(contentsOf: file, encoding: .utf8)

        #expect(file.lastPathComponent.hasPrefix("home-automation-"))
        #expect(file.lastPathComponent.hasSuffix(".txt"))
        #expect(text.contains("[RUN:12345678]"))
        #expect(text.contains("[INV:12345678-a1-draftGeneration-01]"))
        #expect(text.contains("[OP:automationCreation]"))
        #expect(text.contains("[ACTION:a1]"))
        #expect(text.contains("[AGENT:draftGeneration]"))
        #expect(text.contains("[EVENT:agent.output]"))
        #expect(text.contains(#""outputTruncated":"true""#))
        #expect(text.contains(#""outputCharacterCount":"32""#))
    }
}
