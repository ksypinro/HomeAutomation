import Foundation
import FoundationModels
import HomeAutomationCore

extension HomeCandidateResolverSupport {
    internal static func scopedCandidates(
        _ candidates: [HomeCompactCandidateView],
        using resolutionState: HomeResolutionState
    ) -> [HomeCompactCandidateView] {
        var scoped = candidates
        let rooms = Set(
            resolutionState.slots.rooms
                .map(\.agentNormalizedHomeTokenString)
                .filter { !$0.isEmpty && $0 != "home" }
        )
        if !rooms.isEmpty {
            let roomMatches = scoped.filter { candidateMatchesRoom($0, rooms: rooms) }
            if !roomMatches.isEmpty {
                scoped = roomMatches
            }
        }

        let types = Set(
            resolutionState.deviceType.deviceTypes
                .map(\.agentNormalizedHomeTokenString)
                .filter { !$0.isEmpty }
        )
        if !types.isEmpty {
            let typeMatches = scoped.filter { types.contains($0.deviceType.agentNormalizedHomeTokenString) }
            if !typeMatches.isEmpty {
                scoped = typeMatches
            }
        }

        return scoped
    }

    private static func candidateMatchesRoom(_ candidate: HomeCompactCandidateView, rooms: Set<String>) -> Bool {
        if let room = candidate.room?.agentNormalizedHomeTokenString, rooms.contains(room) {
            return true
        }
        let label = candidate.label.agentNormalizedHomeTokenString
        let id = candidate.id.agentNormalizedHomeTokenString
        return rooms.contains { room in
            label.contains(room) || id.contains(room)
        }
    }
}
