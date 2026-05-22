import Foundation
import HomeAutomationCore

/// Action extraction and text cleaning helpers for automation pattern parsing.
extension AutomationPatternParser {
    internal static func cleanedActionText(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: #"(?i)\bevery\s+day\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\beveryday\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bdaily\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bonce\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bweekdays\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bweekends\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bevery\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bevery\s+\d+\s+(minute|minutes|hour|hours|day|days)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bat\s+\d{1,2}(:\d{2})?\s*(am|pm)?\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*schedule\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*create\s+(an?\s+)?(automation|rule)\s+to\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

        return rearrangedScheduleAction(cleaned)
    }

    internal static func rearrangedScheduleAction(_ text: String) -> String {
        guard let match = text.firstAutomationMatch(
            of: #"^(.+?)\s+to\s+(turn on|turn off|switch on|switch off|set|start|stop|open|close|lock|unlock)(?:\s+(.+))?$"#
        ) else {
            return text
        }
        let target = match[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let verb = canonicalVerb(match[2])
        let remainder = match[3].trimmingCharacters(in: .whitespacesAndNewlines)
        let reordered = [verb, target, remainder]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return uppercaseFirst(reordered)
    }

    internal static func actionDescriptions(from text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: #"\s*,\s*and\s+"#, with: " and ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*,\s*"#, with: " and ", options: .regularExpression)
        return normalized
            .components(separatedBy: " and ")
            .map { uppercaseFirst($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
    }

    internal static func conversationalAction(from text: String) -> String? {
        guard let match = text.firstAutomationMatch(
            of: #"\b(?:always\s+)?(turn on|turn off|switch on|switch off|set|increase|decrease|unlock|lock|open|close|start|stop)\s+(.+?)(?:\s+(?:in|under|for)\s+(?:a\s+)?similar\s+situation|\s+when\s+this\s+happens|[.!?]|$)"#
        ) else {
            return nil
        }

        let verb = canonicalVerb(match[1])
        let target = match[2]
            .replacingOccurrences(of: #"(?i)\s+from\s+now\s+on$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        guard !target.isEmpty else { return nil }
        return "\(verb) \(target)"
    }

    internal static func canonicalVerb(_ value: String) -> String {
        switch normalized(value) {
        case "switch on":
            return "Turn on"
        case "switch off":
            return "Turn off"
        default:
            return uppercaseFirst(value)
        }
    }
}
