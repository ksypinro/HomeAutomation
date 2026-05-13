import Foundation
import HomeAutomationCore

public struct AutomationPatternParser: Sendable {
    public init() {}

    public func parse(_ text: String) -> AutomationDraftOutput? {
        let commandText = AgentTextParser.userCommandText(from: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = Self.normalized(commandText)
        guard !commandText.isEmpty else { return nil }

        if normalized.hasPrefix("when ") || normalized.hasPrefix("whenever ") {
            return parseDeviceTrigger(commandText, normalized: normalized)
        }

        guard let time = Self.extractTime(from: normalized) else {
            return nil
        }

        let repeatRule = Self.extractRepeatRule(from: normalized)
        let unsupportedFragments = Self.unsupportedFragments(in: normalized, repeatRule: repeatRule)
        let split = Self.splitCondition(from: commandText)
        let actionText = Self.cleanedActionText(split.actionText)
        let actions = Self.actionDescriptions(from: actionText)
        guard !actions.isEmpty else { return nil }

        let condition = split.conditionText.flatMap { Self.condition(from: $0, triggerPolicy: .never) }
        let trigger = AutomationTriggerOutput(
            type: .schedule,
            repeatRule: Self.repeatRuleString(repeatRule),
            time: Self.timeString(time)
        )

        return AutomationDraftOutput(
            name: Self.name(for: actions, trigger: trigger),
            trigger: trigger,
            condition: condition,
            actionDescriptions: actions,
            unsupportedFragments: unsupportedFragments,
            confidence: unsupportedFragments.isEmpty ? 0.90 : 0.78
        )
    }

    public func parseRuleDraft(_ text: String) -> HomeAutomationRuleDraft? {
        try? parse(text)?.makeRuleDraft()
    }

    private func parseDeviceTrigger(_ text: String, normalized: String) -> AutomationDraftOutput? {
        let separators = [",", " then "]
        var triggerPart = text
        var actionPart = ""
        for separator in separators {
            if let range = text.range(of: separator, options: [.caseInsensitive]) {
                triggerPart = String(text[..<range.lowerBound])
                actionPart = String(text[range.upperBound...])
                break
            }
        }
        if actionPart.isEmpty,
           let range = normalized.range(of: " turn ", options: [.caseInsensitive]) {
            let distance = normalized.distance(from: normalized.startIndex, to: range.lowerBound)
            let start = text.index(text.startIndex, offsetBy: min(distance, text.count))
            triggerPart = String(text[..<start])
            actionPart = String(text[start...])
        }

        let cleanedTrigger = triggerPart
            .replacingOccurrences(of: #"(?i)^\s*whenever\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*when\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let actions = Self.actionDescriptions(from: Self.cleanedActionText(actionPart))
        guard !cleanedTrigger.isEmpty, !actions.isEmpty else { return nil }

        let condition = Self.condition(from: cleanedTrigger, triggerPolicy: .always) ??
            AutomationConditionOutput(
                type: .comparison,
                left: AutomationConditionOperandOutput(
                    type: .unsupported,
                    description: cleanedTrigger
                ),
                operatorName: .changes,
                right: AutomationConditionOperandOutput(
                    type: .literalString,
                    stringValue: "changed"
                ),
                triggerPolicy: .always
            )
        let trigger = AutomationTriggerOutput(
            type: .device,
            description: cleanedTrigger,
            condition: condition
        )

        return AutomationDraftOutput(
            name: Self.name(for: actions, trigger: trigger),
            trigger: trigger,
            condition: nil,
            actionDescriptions: actions,
            unsupportedFragments: [],
            confidence: 0.76
        )
    }

    private static func splitCondition(from text: String) -> (actionText: String, conditionText: String?) {
        guard let range = text.range(of: #"(?i)\s+if\s+"#, options: .regularExpression) else {
            return (text, nil)
        }
        return (
            String(text[..<range.lowerBound]),
            String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func extractRepeatRule(from normalized: String) -> HomeAutomationRepeatRule {
        if normalized.contains("weekdays") {
            return .daysOfWeek([.monday, .tuesday, .wednesday, .thursday, .friday])
        }
        if normalized.contains("weekends") {
            return .daysOfWeek([.saturday, .sunday])
        }

        let weekdayMap: [(String, HomeAutomationWeekday)] = [
            ("monday", .monday),
            ("tuesday", .tuesday),
            ("wednesday", .wednesday),
            ("thursday", .thursday),
            ("friday", .friday),
            ("saturday", .saturday),
            ("sunday", .sunday)
        ]
        let days = weekdayMap.compactMap { day, value in
            normalized.contains("every \(day)") ? value : nil
        }
        if !days.isEmpty {
            return .daysOfWeek(days)
        }

        if let match = normalized.firstAutomationMatch(of: #"\bevery\s+(\d+)\s+(minute|minutes|hour|hours|day|days)\b"#),
           let value = Int(match[1]) {
            let unit: HomeAutomationTimeUnit
            switch match[2] {
            case "hour", "hours":
                unit = .hour
            case "day", "days":
                unit = .day
            default:
                unit = .minute
            }
            return .interval(value: value, unit: unit)
        }

        if normalized.contains("once") {
            return .once
        }

        return .everyDay
    }

    private static func extractTime(from normalized: String) -> HomeAutomationTimeOfDay? {
        guard let match = normalized.firstAutomationMatch(of: #"\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#),
              var hour = Int(match[1]) else {
            return nil
        }
        let minute = Int(match[2]) ?? 0
        let meridiem = match[3]
        if meridiem == "pm", hour < 12 {
            hour += 12
        } else if meridiem == "am", hour == 12 {
            hour = 0
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            return nil
        }
        return HomeAutomationTimeOfDay(hour: hour, minute: minute)
    }

    private static func cleanedActionText(_ text: String) -> String {
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

    private static func rearrangedScheduleAction(_ text: String) -> String {
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

    private static func actionDescriptions(from text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: #"\s*,\s*and\s+"#, with: " and ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*,\s*"#, with: " and ", options: .regularExpression)
        return normalized
            .components(separatedBy: " and ")
            .map { uppercaseFirst($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
    }

    private static func condition(
        from text: String,
        triggerPolicy: AutomationConditionTriggerPolicyOutput
    ) -> AutomationConditionOutput? {
        let normalized = Self.normalized(text)

        if normalized.contains(" or ") {
            let children = normalized
                .components(separatedBy: " or ")
                .compactMap { condition(from: $0, triggerPolicy: triggerPolicy) }
            return children.isEmpty ? nil : AutomationConditionOutput(type: .or, children: children)
        }
        if normalized.contains(" and ") {
            let children = normalized
                .components(separatedBy: " and ")
                .compactMap { condition(from: $0, triggerPolicy: triggerPolicy) }
            return children.isEmpty ? nil : AutomationConditionOutput(type: .and, children: children)
        }
        if normalized.hasPrefix("not ") {
            return condition(from: String(normalized.dropFirst(4)), triggerPolicy: triggerPolicy).map {
                AutomationConditionOutput(type: .not, children: [$0])
            }
        }

        let valuePairs: [(String, String)] = [
            (" is closed", "closed"),
            (" is open", "open"),
            (" opens", "open"),
            (" closes", "closed"),
            (" is on", "on"),
            (" is off", "off"),
            ("motion is detected", "active"),
            ("detects motion", "active")
        ]
        for (phrase, value) in valuePairs where normalized.contains(phrase) {
            let leftDescription = normalized
                .replacingOccurrences(of: phrase, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return AutomationConditionOutput(
                type: .comparison,
                left: AutomationConditionOperandOutput(
                    type: .deviceAttribute,
                    description: leftDescription.isEmpty ? normalized : leftDescription
                ),
                operatorName: .equals,
                right: AutomationConditionOperandOutput(
                    type: .literalString,
                    stringValue: value
                ),
                triggerPolicy: triggerPolicy
            )
        }

        if let match = normalized.firstAutomationMatch(of: #"(.+)\s+(above|greater than|over|below|less than|under)\s+(\d+)"#),
           let value = Double(match[3]) {
            let op: AutomationComparisonOperatorOutput = ["above", "greater than", "over"].contains(match[2])
                ? .greaterThan
                : .lessThan
            return AutomationConditionOutput(
                type: .comparison,
                left: AutomationConditionOperandOutput(type: .deviceAttribute, description: match[1]),
                operatorName: op,
                right: AutomationConditionOperandOutput(type: .literalNumber, numberValue: value),
                triggerPolicy: triggerPolicy
            )
        }

        return nil
    }

    private static func unsupportedFragments(
        in normalized: String,
        repeatRule: HomeAutomationRepeatRule
    ) -> [String] {
        var fragments: [String] = []
        switch repeatRule {
        case .daysOfWeek(let days):
            if normalized.contains("weekdays") {
                fragments.append("weekdays")
            } else if normalized.contains("weekends") {
                fragments.append("weekends")
            } else {
                fragments.append(
                    days
                        .map { "every \($0.rawValue)" }
                        .joined(separator: ", ")
                )
            }
        case .unsupported(let rawValue):
            fragments.append(rawValue)
        case .once, .everyDay, .interval:
            break
        }

        if normalized.contains("holiday") || normalized.contains("holidays") {
            fragments.append("holidays")
        }
        return stableUnique(fragments)
    }

    private static func repeatRuleString(_ repeatRule: HomeAutomationRepeatRule) -> String {
        switch repeatRule {
        case .once:
            return "once"
        case .everyDay:
            return "everyDay"
        case .interval(let value, let unit):
            return "every \(value) \(unit.rawValue)\(value == 1 ? "" : "s")"
        case .daysOfWeek(let days):
            return "daysOfWeek:" + days.map(\.rawValue).joined(separator: ",")
        case .unsupported(let rawValue):
            return rawValue
        }
    }

    private static func timeString(_ time: HomeAutomationTimeOfDay) -> String {
        String(format: "%02d:%02d", time.hour, time.minute)
    }

    private static func name(for actions: [String], trigger: AutomationTriggerOutput) -> String {
        let action = actions.first ?? "Automation"
        switch trigger.type {
        case .schedule:
            let repeatRule = trigger.repeatRule ?? "schedule"
            let time = trigger.time ?? "time"
            return "\(action) \(repeatRule) at \(time)"
        case .device:
            return "\(action) when \(trigger.description ?? "condition changes")"
        }
    }

    private static func normalized(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9:\s]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func canonicalVerb(_ value: String) -> String {
        switch normalized(value) {
        case "switch on":
            return "Turn on"
        case "switch off":
            return "Turn off"
        default:
            return uppercaseFirst(value)
        }
    }

    private static func uppercaseFirst(_ value: String) -> String {
        guard let first = value.first else { return value }
        return String(first).uppercased() + value.dropFirst()
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let key = normalized(value)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(value)
        }
        return result
    }
}
