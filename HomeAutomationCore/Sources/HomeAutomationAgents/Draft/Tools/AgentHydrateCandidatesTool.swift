import Foundation
import FoundationModels
import HomeAutomationCore

public struct AgentHydrateCandidatesTool: Tool {
    public let name = "hydrateCandidateRecords"
    public let description = "Returns full device records for candidate IDs."
    private let registry: MockHomeDeviceRegistry
    private let outputSizeStore: AgentToolOutputSizeStore

    public init(
        registry: MockHomeDeviceRegistry,
        outputSizeStore: AgentToolOutputSizeStore = .shared
    ) {
        self.registry = registry
        self.outputSizeStore = outputSizeStore
    }

    @Generable
    public struct Arguments {
        @Guide(description: "Candidate IDs selected from provided candidates only.", .maximumCount(25))
        public let candidateIDs: [String]
    }

    public func call(arguments: Arguments) async throws -> String {
        let startedAt = await agentStartToolTelemetry(toolName: name, arguments: arguments)
        let devices = await registry.allDevices()
        let idSet = Set(arguments.candidateIDs)
        return await recordOutput(AgentToolFormatting.records(devices.filter { idSet.contains($0.id) }), startedAt: startedAt)
    }

    private func recordOutput(_ output: String, startedAt: Date) async -> String {
        await agentFinishToolTelemetry(
            toolName: name,
            output: output,
            outputSizeStore: outputSizeStore,
            startedAt: startedAt
        )
    }
}
