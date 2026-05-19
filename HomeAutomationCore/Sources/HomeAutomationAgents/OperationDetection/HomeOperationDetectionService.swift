import Foundation
import HomeAutomationCore

public struct HomeOperationDetectionService: Sendable {
    public init() {}

    public func detect(_ text: String) -> HomeOperationDetectionResult {
        analyzeSemantics(text)
    }

    public func analyzeSemantics(_ text: String) -> HomeOperationDetectionResult {
        let normalized = Self.normalized(text)
        guard !normalized.isEmpty else {
            return HomeOperationDetectionResult(
                domain: .unsupported,
                operation: .unsupported,
                confidence: 1,
                reason: "Empty command"
            )
        }

        let referencesAutomationObject = containsAny(
            normalized,
            ["automation", "automations", "rule", "rules"]
        )
        if referencesAutomationObject, containsAny(normalized, ["delete", "remove"]) {
            return result(.automationDeletion, confidence: 0.9, reason: "Deletion keyword matched")
        }
        if referencesAutomationObject, containsAny(normalized, ["update", "change", "edit", "disable", "enable"]) {
            return result(.automationUpdate, confidence: 0.86, reason: "Update keyword matched")
        }
        if referencesAutomationObject,
           containsAny(normalized, ["show", "list"]) || normalized.hasPrefix("what ") {
            return result(.automationQuery, confidence: 0.86, reason: "Automation query keyword matched")
        }

        let hasAutomationKeyword = containsAny(
            normalized,
            ["automation", "automatically", "schedule", "rule", "routine to"]
        )
        let hasConversationalAutomationIntent =
            containsAny(normalized, ["remember this", "remember that", "similar situation", "similar situations", "when this happens", "whenever this happens", "in this situation", "from now on", "next time"]) &&
            containsAny(normalized, ["turn on", "turn off", "set ", "increase", "decrease", "lock", "unlock", "open", "close", "start", "stop"])
        let hasSchedule = containsAny(
            normalized,
            ["every day", "everyday", "daily", "every monday", "every tuesday", "every wednesday", "every thursday", "every friday", "every saturday", "every sunday", "weekdays", "weekends"]
        ) || Self.containsTimeExpression(normalized)
        let hasTrigger = containsAny(normalized, [" when ", "whenever ", " if ", " after ", " before "]) ||
            normalized.hasPrefix("when ") ||
            normalized.hasPrefix("whenever ")

        if hasAutomationKeyword || hasSchedule || hasTrigger || hasConversationalAutomationIntent {
            return result(
                .automationCreation,
                confidence: hasAutomationKeyword || hasConversationalAutomationIntent ? 0.92 : 0.84,
                reason: "Schedule, trigger, conversational routine, or automation keyword matched"
            )
        }

        if containsAny(
            normalized,
            ["turn on", "turn off", "set ", "increase", "decrease", "warmer", "cooler", "brighter", "dim", "lock", "unlock", "open", "close", "run "]
        ) {
            return result(.executeDeviceCommand, confidence: 0.82, reason: "Immediate device command matched")
        }

        return result(.executeDeviceCommand, confidence: 0.52, reason: "No automation pattern matched; using direct command pipeline")
    }

    private func result(
        _ operation: HomeAutomationOperationKind,
        confidence: Double,
        reason: String
    ) -> HomeOperationDetectionResult {
        HomeOperationDetectionResult(
            domain: operation == .unsupported ? .unsupported : .homeAutomation,
            operation: operation,
            confidence: confidence,
            reason: reason
        )
    }

    static func normalized(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9:\s]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsAny(_ text: String, _ patterns: [String]) -> Bool {
        patterns.contains { text.contains($0) }
    }

    private static func containsTimeExpression(_ text: String) -> Bool {
        text.range(
            of: #"\bat\s+\d{1,2}(:\d{2})?\s*(am|pm)?\b"#,
            options: .regularExpression
        ) != nil
    }
}
