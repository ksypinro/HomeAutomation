import Foundation
import HomeAutomationCore

/// Input for `RuleFallbackAgent` containing user text, execution preference, and memory hints.
public struct RuleFallbackInput: Sendable, Hashable {
    public let text: String
    public let executeLowRiskCommands: Bool
    public let memoryHints: [MemoryHint]

    public init(
        text: String,
        executeLowRiskCommands: Bool = true,
        memoryHints: [MemoryHint] = []
    ) {
        self.text = text
        self.executeLowRiskCommands = executeLowRiskCommands
        self.memoryHints = memoryHints
    }
}
