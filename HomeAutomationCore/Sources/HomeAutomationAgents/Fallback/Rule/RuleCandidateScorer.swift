import Foundation
import HomeAutomationCore

struct RuleCandidateScorer {
    struct Result {
        let scored: [AgentScoredDevice]
        let selected: AgentScoredDevice?
        let secondScore: Int
        let isAmbiguous: Bool
        let confidence: Double
    }

    static func score(
        _ device: HomeCandidateRecord,
        for intent: AgentRuleIntent,
        normalized: String,
        semanticHints: AgentSemanticHints
    ) -> Int {
        let queryTokens = normalized.agentTokenSet
        let name = device.displayName.agentNormalizedHomeTokenString
        let nameTokens = name.agentTokenSet
        let type = device.deviceType.agentNormalizedHomeTokenString
        let room = device.room?.agentNormalizedHomeTokenString
        let aliases = device.metadata["aliases"]?
            .split(separator: ",")
            .map { String($0).agentNormalizedHomeTokenString } ?? []

        var total = 0
        if normalized.contains(name) { total += 20 }
        if aliases.contains(where: { !$0.isEmpty && containsTokenPhrase(normalized, phrase: $0) }) { total += 14 }
        if normalized.contains(type) || HomeDeviceTypeRelations.matches(type, in: intent.deviceTypeHints) { total += 7 }
        if let room, normalized.contains(room) { total += 6 }

        let overlap = queryTokens.intersection(nameTokens).count
        total += min(overlap * 2, 8)

        if intent.capabilityPreferences.contains(where: { device.capabilities.contains($0.capability) }) {
            total += 6
        }

        if semanticHints.preferredDeviceIDs.contains(device.id) {
            total += 8
        }
        if !semanticHints.preferredCapabilityIDs.isDisjoint(with: Set(device.capabilities)) {
            total += 4
        }

        if device.type == .routine, intent.family == .routine {
            total += 8
        }

        return total
    }

    static func rank(
        devices: [HomeCandidateRecord],
        intent: AgentRuleIntent,
        normalized: String,
        semanticHints: AgentSemanticHints = AgentSemanticHints()
    ) -> Result {
        let scored = devices.compactMap { device -> AgentScoredDevice? in
            guard let draftIntent = intent.makeDraftIntent(for: device) else { return nil }
            let s = score(device, for: intent, normalized: normalized, semanticHints: semanticHints)
            guard s > 0 else { return nil }
            return AgentScoredDevice(device: device, draftIntent: draftIntent, score: s)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.device.displayName < rhs.device.displayName
            }
            return lhs.score > rhs.score
        }

        let selected = scored.first
        let secondScore = scored.dropFirst().first?.score ?? 0
        let isAmbiguous: Bool
        if let sel = selected {
            isAmbiguous = sel.score < 8 || (secondScore > 0 && sel.score - secondScore < 2)
        } else {
            isAmbiguous = true
        }
        let confidence = selected.map { min(0.98, Double($0.score) / 24.0) } ?? 0.0

        return Result(
            scored: scored,
            selected: selected,
            secondScore: secondScore,
            isAmbiguous: isAmbiguous,
            confidence: confidence
        )
    }

    private static func containsTokenPhrase(_ normalizedText: String, phrase: String) -> Bool {
        let normalizedPhrase = phrase.agentNormalizedHomeTokenString
        guard !normalizedPhrase.isEmpty else { return false }
        return " \(normalizedText) ".contains(" \(normalizedPhrase) ")
    }
}
