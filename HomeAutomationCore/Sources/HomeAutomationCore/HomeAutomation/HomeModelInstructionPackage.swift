import Foundation
import FoundationModels

public enum HomeGenerationMode: Sendable, Hashable, Codable {
    case greedy
    case defaultSampling
}

public struct HomeModelInstructionPackage: @unchecked Sendable {
    public let instructions: Instructions
    public let instructionText: String?
    public let prompt: String
    public let tools: [any Tool]
    public let useAdapter: Bool
    public let generationMode: HomeGenerationMode
    public let contextBudgetReport: HomeModelContextBudgetReport?

    public init(
        instructions: Instructions,
        instructionText: String? = nil,
        prompt: String,
        tools: [any Tool] = [],
        useAdapter: Bool,
        generationMode: HomeGenerationMode,
        contextBudgetReport: HomeModelContextBudgetReport? = nil
    ) {
        self.instructions = instructions
        self.instructionText = instructionText
        self.prompt = prompt
        self.tools = tools
        self.useAdapter = useAdapter
        self.generationMode = generationMode
        self.contextBudgetReport = contextBudgetReport
    }
}
