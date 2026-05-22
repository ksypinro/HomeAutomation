import Foundation
import HomeAutomationCore

/// Deterministic heuristic-based ranking fallback used when Foundation Models are unavailable.
extension HomeCandidateResolverSupport {
    internal func deterministicAggregation(
        userText: String,
        resolutionState: HomeResolutionState,
        candidates: [HomeCompactCandidateView],
        memoryHints: [MemoryHint]
    ) -> HomeCandidateAggregationResult {
        let normalized = userText.agentNormalizedHomeTokenString
        let rooms = Set(resolutionState.slots.rooms.map(\.agentNormalizedHomeTokenString))
        let types = Set(resolutionState.deviceType.deviceTypes.map(\.agentNormalizedHomeTokenString))
        let hintedDeviceIDs = Set(memoryHints.compactMap(\.deviceID))
        let hintedCapabilities = Set(memoryHints.compactMap(\.capability))

        let scored = candidates.map { candidate in
            var score = 0
            let label = candidate.label.agentNormalizedHomeTokenString
            let type = candidate.deviceType.agentNormalizedHomeTokenString
            let room = candidate.room?.agentNormalizedHomeTokenString

            if normalized.contains(label) { score += 20 }
            if normalized.contains(type) || types.contains(type) { score += 8 }
            if let room, normalized.contains(room) || rooms.contains(room) { score += 8 }

            let overlap = normalized.agentTokenSet.intersection(label.agentTokenSet).count
            score += min(overlap * 2, 8)

            if resolutionState.intent.topFamilies.contains(.power),
               candidate.shortCapabilities.contains("switch") {
                score += 4
            }
            if resolutionState.intent.topFamilies.contains(.brightness),
               candidate.shortCapabilities.contains("switchLevel") {
                score += 4
            }
            if resolutionState.intent.topFamilies.contains(.temperature),
               candidate.shortCapabilities.contains(where: { $0.contains("thermostat") || $0 == "temperatureMeasurement" }) {
                score += 4
            }
            if resolutionState.intent.topFamilies.contains(.lockUnlock),
               candidate.shortCapabilities.contains("lock") {
                score += 6
            }
            if resolutionState.intent.topFamilies.contains(.routine),
               candidate.shortCapabilities.contains("routine") {
                score += 8
            }
            if hintedDeviceIDs.contains(candidate.id) {
                score += 10
            }
            if !hintedCapabilities.isDisjoint(with: Set(candidate.shortCapabilities)) {
                score += 4
            }

            return (candidate: candidate, score: score)
        }
        .filter { $0.score > 0 }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.candidate.label < rhs.candidate.label
            }
            return lhs.score > rhs.score
        }

        guard let best = scored.first else {
            return HomeCandidateAggregationResult(
                finalCandidateIDs: [],
                needsClarification: true,
                clarificationQuestion: "Which device do you want to control?",
                confidence: 0.2
            )
        }

        let second = scored.dropFirst().first?.score ?? 0
        if second > 0 && best.score - second < 2 {
            return HomeCandidateAggregationResult(
                finalCandidateIDs: scored.prefix(3).map(\.candidate.id),
                needsClarification: true,
                clarificationQuestion: "Which device do you mean?",
                confidence: 0.45
            )
        }

        return HomeCandidateAggregationResult(
            finalCandidateIDs: [best.candidate.id],
            needsClarification: false,
            confidence: min(0.95, Double(best.score) / 44.0)
        )
    }
}
