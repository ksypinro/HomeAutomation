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
        let textFile = try #require(files.first { $0.pathExtension == "txt" })
        let jsonlFile = try #require(files.first { $0.pathExtension == "jsonl" })
        let text = try String(contentsOf: textFile, encoding: .utf8)
        let jsonl = try String(contentsOf: jsonlFile, encoding: .utf8)

        #expect(textFile.lastPathComponent.hasPrefix("home-automation-"))
        #expect(textFile.lastPathComponent.hasSuffix(".txt"))
        #expect(jsonlFile.lastPathComponent.hasPrefix("home-automation-"))
        #expect(jsonlFile.lastPathComponent.hasSuffix(".jsonl"))
        #expect(text.contains("[RUN:12345678]"))
        #expect(text.contains("[INV:12345678-a1-draftGeneration-01]"))
        #expect(text.contains("[OP:automationCreation]"))
        #expect(text.contains("[ACTION:a1]"))
        #expect(text.contains("[AGENT:draftGeneration]"))
        #expect(text.contains("[EVENT:agent.output]"))
        #expect(text.contains(#""outputTruncated":true"#))
        #expect(text.contains(#""outputCharacterCount":32"#))
        #expect(jsonl.contains(#""agentInvocationID":"12345678-a1-draftGeneration-01""#))
        #expect(jsonl.contains(#""eventType":"agent.output""#))
        #expect(jsonl.contains(#""runtimeMode":"graph""#))
    }

    @Test
    func jsonlWriterPromotesEvaluationFields() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("home-automation-jsonl-\(UUID().uuidString)", isDirectory: true)
        let telemetry = HomeAutomationTelemetry(
            configuration: HomeAutomationTelemetryConfiguration(
                isEnabled: true,
                logDirectoryURL: directory,
                payloadMode: .fullPayload
            )
        )

        await telemetry.log(
            "agent.evaluationOutput",
            context: HomeAutomationTelemetryContext(
                runID: "run-1",
                graphID: "direct-command-graph",
                graphNodeID: "capabilityResolution",
                agentID: "capabilityResolution",
                agentInvocationID: "run-1-root-capabilityResolution-01",
                runtimeMode: "graph"
            ),
            status: "completed",
            payload: [
                "selectedCandidateIDs": "bedroom_ac,bedroom_lamp",
                "selectedCapability": "switch",
                "selectedCommand": "on",
                "targetDeviceID": "bedroom_ac"
            ]
        )

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let jsonlFile = try #require(files.first { $0.pathExtension == "jsonl" })
        let jsonl = try String(contentsOf: jsonlFile, encoding: .utf8)

        #expect(jsonl.contains(#""selectedCandidateIDs":["bedroom_ac","bedroom_lamp"]"#))
        #expect(jsonl.contains(#""selectedCapability":"switch""#))
        #expect(jsonl.contains(#""selectedCommand":"on""#))
        #expect(jsonl.contains(#""targetDeviceID":"bedroom_ac""#))
    }
}
