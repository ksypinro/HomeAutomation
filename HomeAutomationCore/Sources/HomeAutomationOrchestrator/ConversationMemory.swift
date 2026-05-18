import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import OSLog

/// A record representing a single interaction or turn in the conversation.
public struct ConversationTurn: Sendable, Identifiable, Hashable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let userText: String
    public let resolvedDeviceID: String?
    public let resolvedCapability: String?
    public let wasConfirmed: Bool
    public let riskLevel: HomeAutomationRiskLevel?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        userText: String,
        resolvedDeviceID: String? = nil,
        resolvedCapability: String? = nil,
        wasConfirmed: Bool = false,
        riskLevel: HomeAutomationRiskLevel? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.userText = userText
        self.resolvedDeviceID = resolvedDeviceID
        self.resolvedCapability = resolvedCapability
        self.wasConfirmed = wasConfirmed
        self.riskLevel = riskLevel
    }
}

/// A localized, short-term memory store for a specific user's conversation session.
///
/// It tracks recent interactions, enabling follow-up commands (e.g., "turn it off")
/// by retrieving previously resolved device hints.
public actor ConversationMemory {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "ConversationMemory")
    private var turns: [ConversationTurn] = []
    private let maxTurns: Int

    public init(maxTurns: Int = 10) {
        self.maxTurns = max(1, maxTurns)
    }

    /// Appends a new turn to the memory, maintaining the `maxTurns` limit.
    public func append(_ turn: ConversationTurn) {
        turns.append(turn)
        if turns.count > maxTurns {
            turns.removeFirst(turns.count - maxTurns)
        }
        logger.debug("Appended new turn. Current memory size: \(self.turns.count, privacy: .public)")
    }

    /// Retrieves a contextual hint based on the most recently resolved device.
    ///
    /// - Returns: A `MemoryHint` if a device was resolved recently, or `nil`.
    public func lastResolvedDeviceHint() -> MemoryHint? {
        guard let turn = turns.last(where: { $0.resolvedDeviceID != nil }) else {
            logger.debug("No recently resolved device found in memory.")
            return nil
        }
        logger.debug("Providing memory hint for device ID: \(turn.resolvedDeviceID ?? "nil", privacy: .public)")
        return MemoryHint(
            deviceID: turn.resolvedDeviceID,
            capability: turn.resolvedCapability,
            confidence: 0.45,
            reason: "Recent conversation turn"
        )
    }

    /// Returns a slice of the most recent conversation turns.
    public func recentContext(limit: Int = 3) -> [ConversationTurn] {
        Array(turns.suffix(max(0, limit)))
    }

    /// Clears the entire conversation memory.
    public func clear() {
        logger.debug("Clearing conversation memory.")
        turns.removeAll()
    }
}

/// A utility to detect if a user's input likely contains a pronoun referencing a past interaction.
public enum ConversationMemoryReferenceDetector {
    /// Detects linguistic markers like "it", "that", "there", implying a memory reference.
    public static func containsMemoryReference(_ text: String) -> Bool {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        
        let actionPronouns = [
            "turn it", "switch it", "set it", "dim it", "make it",
            "turn that", "switch that", "set that", "make that",
            "unlock it", "lock it", "open it", "close it",
            "unlock that", "lock that", "open that", "close that",
            "do same", "the same", "do that", "same thing"
        ]
        return actionPronouns.contains { normalized.contains($0) }
    }
}
