import Foundation

public enum QueryReformulator {
    public static func reformulate(rawText: String, hints: NLURetrievalHints?) -> String {
        guard let hints, !hints.isEmpty else {
            return rawText
        }

        let expansions = [
            hints.intentFamilies.joined(separator: " "),
            hints.deviceTypes.joined(separator: " "),
            hints.rooms.joined(separator: " "),
            hints.capabilities.joined(separator: " ")
        ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !expansions.isEmpty else { return rawText }
        return ([rawText] + expansions).joined(separator: " ")
    }
}
