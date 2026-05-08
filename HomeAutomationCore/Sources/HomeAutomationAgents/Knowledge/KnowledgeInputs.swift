import Foundation
import HomeAutomationCore
import HomeAutomationRAG

/// Input types shared across Knowledge agents.

/// Input for `BixbyKnowledgeAgent` containing the user text and device names
/// to use for Bixby command matching.
public struct BixbyKnowledgeInput: Sendable, Hashable {
    public let text: String
    public let deviceNames: [String]

    public init(text: String, deviceNames: [String] = ["bedroom light"]) {
        self.text = text
        self.deviceNames = deviceNames
    }
}

/// Input for `CommandExampleAgent` containing the user text and the maximum
/// number of examples to retrieve.
public struct CommandExampleInput: Sendable, Hashable {
    public let text: String
    public let limit: Int

    public init(text: String, limit: Int = 5) {
        self.text = text
        self.limit = limit
    }
}
