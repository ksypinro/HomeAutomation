import Foundation
import FoundationModels

public enum HomeGenerationMode: Sendable, Hashable, Codable {
    case greedy
    case defaultSampling
}

public struct HomeModelInstructionPackage: @unchecked Sendable {
    public let instructions: Instructions
    public let prompt: String
    public let tools: [any Tool]
    public let useAdapter: Bool
    public let generationMode: HomeGenerationMode

    public init(
        instructions: Instructions,
        prompt: String,
        tools: [any Tool] = [],
        useAdapter: Bool,
        generationMode: HomeGenerationMode
    ) {
        self.instructions = instructions
        self.prompt = prompt
        self.tools = tools
        self.useAdapter = useAdapter
        self.generationMode = generationMode
    }
}
