import Foundation
import HomeAutomationCore

/// Candidate list text formatting helpers for prompt construction.
extension CandidateResolutionPromptBuilder {
    internal func fullCandidateLines(_ candidates: [HomeCompactCandidateView]) -> String {
        candidates.map(\.description).joined(separator: "\n")
    }

    internal func compactCandidateLines(_ candidates: [HomeCompactCandidateView]) -> String {
        candidates.map { candidate in
            let caps = candidate.shortCapabilities.prefix(5).joined(separator: ",")
            return "id=\(candidate.id) label=\(candidate.label) type=\(candidate.deviceType) room=\(candidate.room ?? "") caps=\(caps)"
        }
        .joined(separator: "\n")
    }

    internal func minimalCandidateLines(_ candidates: [HomeCompactCandidateView]) -> String {
        candidates.map { candidate in
            "id=\(candidate.id) label=\(candidate.label) type=\(candidate.deviceType) room=\(candidate.room ?? "")"
        }
        .joined(separator: "\n")
    }
}
