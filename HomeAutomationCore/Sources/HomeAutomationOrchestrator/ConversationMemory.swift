import Foundation
import HomeAutomationAgents
import HomeAutomationCore

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

public actor ConversationMemory {
    private var turns: [ConversationTurn] = []
    private let maxTurns: Int

    public init(maxTurns: Int = 10) {
        self.maxTurns = max(1, maxTurns)
    }

    public func append(_ turn: ConversationTurn) {
        turns.append(turn)
        if turns.count > maxTurns {
            turns.removeFirst(turns.count - maxTurns)
        }
    }

    public func lastResolvedDeviceHint() -> MemoryHint? {
        guard let turn = turns.last(where: { $0.resolvedDeviceID != nil }) else {
            return nil
        }
        return MemoryHint(
            deviceID: turn.resolvedDeviceID,
            capability: turn.resolvedCapability,
            confidence: 0.45,
            reason: "Recent conversation turn"
        )
    }

    public func recentContext(limit: Int = 3) -> [ConversationTurn] {
        Array(turns.suffix(max(0, limit)))
    }

    public func clear() {
        turns.removeAll()
    }
}

public enum ConversationMemoryReferenceDetector {
    public static func containsMemoryReference(_ text: String) -> Bool {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let tokens = Set(
            normalized
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        return !tokens.isDisjoint(with: ["it", "that", "same", "there"])
    }
}
