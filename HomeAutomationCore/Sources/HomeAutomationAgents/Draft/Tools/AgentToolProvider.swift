import Foundation
import FoundationModels
import HomeAutomationCore

public struct AgentToolProvider: Sendable {
    private let registry: MockHomeDeviceRegistry
    private let outputSizeStore: AgentToolOutputSizeStore

    public init(
        registry: MockHomeDeviceRegistry,
        outputSizeStore: AgentToolOutputSizeStore = .shared
    ) {
        self.registry = registry
        self.outputSizeStore = outputSizeStore
    }

    public func tools(for input: HomeFinalResolutionInput) -> [any Tool] {
        var tools: [any Tool] = [
            AgentFindDevicesTool(registry: registry, outputSizeStore: outputSizeStore),
            AgentInspectCandidateCommandTool(registry: registry, outputSizeStore: outputSizeStore),
            AgentHydrateCandidatesTool(registry: registry, outputSizeStore: outputSizeStore)
        ]

        if input.resolutionState.intent.topFamilies.contains(.temperature) ||
            input.resolutionState.intent.topFamilies.contains(.statusQuery) ||
            input.resolutionState.intent.topFamilies.contains(.brightness) {
            tools.append(AgentGetDeviceStateTool(registry: registry, outputSizeStore: outputSizeStore))
        }

        return tools
    }

    public func estimatedOutputCharacters(for tools: [any Tool], candidateCount: Int) -> Int {
        tools.reduce(0) { total, tool in
            total + outputSizeStore.estimate(
                toolName: tool.name,
                fallback: fallbackOutputEstimate(toolName: tool.name, candidateCount: candidateCount)
            )
        }
    }

    private func fallbackOutputEstimate(toolName: String, candidateCount: Int) -> Int {
        switch toolName {
        case "findDeviceCandidates":
            return min(candidateCount, 10) * 120
        case "hydrateCandidateRecords":
            return min(candidateCount, 5) * 160
        case "inspectCandidateCommand":
            return 600
        case "getCurrentDeviceState":
            return 300
        default:
            return 512
        }
    }
}
