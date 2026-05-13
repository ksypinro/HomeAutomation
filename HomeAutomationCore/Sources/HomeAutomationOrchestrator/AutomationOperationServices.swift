import Foundation
import HomeAutomationCore

public struct HomeOperationDetectionService: Sendable {
    public init() {}

    public func detect(_ text: String) -> HomeOperationDetectionResult {
        let normalized = Self.normalized(text)
        guard !normalized.isEmpty else {
            return HomeOperationDetectionResult(
                domain: .unsupported,
                operation: .unsupported,
                confidence: 1,
                reason: "Empty command"
            )
        }

        if containsAny(normalized, ["delete automation", "delete rule", "remove automation", "remove rule"]) {
            return result(.automationDeletion, confidence: 0.9, reason: "Deletion keyword matched")
        }
        if containsAny(normalized, ["update automation", "update rule", "change automation", "change rule"]) {
            return result(.automationUpdate, confidence: 0.86, reason: "Update keyword matched")
        }
        if containsAny(normalized, ["show automations", "list automations", "what automations", "show rules", "list rules"]) {
            return result(.automationQuery, confidence: 0.86, reason: "Automation query keyword matched")
        }

        let hasAutomationKeyword = containsAny(
            normalized,
            ["automation", "automatically", "schedule", "rule", "routine to"]
        )
        let hasSchedule = containsAny(
            normalized,
            ["every day", "everyday", "daily", "every monday", "every tuesday", "every wednesday", "every thursday", "every friday", "every saturday", "every sunday", "weekdays", "weekends"]
        ) || Self.containsTimeExpression(normalized)
        let hasTrigger = containsAny(normalized, [" when ", "whenever ", " if ", " after ", " before "]) ||
            normalized.hasPrefix("when ") ||
            normalized.hasPrefix("whenever ")

        if hasAutomationKeyword || hasSchedule || hasTrigger {
            return result(.automationCreation, confidence: hasAutomationKeyword ? 0.92 : 0.84, reason: "Schedule, trigger, or automation keyword matched")
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

public struct AutomationPatternParser: Sendable {
    public init() {}

    public func parse(_ text: String) -> HomeAutomationRuleDraft? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = HomeOperationDetectionService.normalized(trimmed)
        guard !trimmed.isEmpty else { return nil }

        if normalized.hasPrefix("when ") || normalized.hasPrefix("whenever ") {
            return parseDeviceTrigger(trimmed, normalized: normalized)
        }

        guard let time = Self.extractTime(from: normalized) else {
            return nil
        }

        let repeatRule = Self.extractRepeatRule(from: normalized)
        let split = Self.splitCondition(from: trimmed)
        let actionText = Self.cleanedActionText(split.actionText)
        let actions = Self.actionDescriptions(from: actionText)
        guard !actions.isEmpty else { return nil }

        let condition = split.conditionText.flatMap { Self.condition(from: $0, triggerPolicy: .never) }
        let trigger = HomeAutomationTrigger.schedule(
            HomeAutomationScheduleTrigger(
                repeatRule: repeatRule,
                timeOfDay: time
            )
        )

        return HomeAutomationRuleDraft(
            name: Self.name(for: actions, trigger: trigger),
            trigger: trigger,
            condition: condition,
            actionDescriptions: actions,
            confidence: 0.86
        )
    }

    private func parseDeviceTrigger(_ text: String, normalized: String) -> HomeAutomationRuleDraft? {
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
            let start = text.index(text.startIndex, offsetBy: normalized.distance(from: normalized.startIndex, to: range.lowerBound))
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
            .comparison(
                HomeAutomationComparisonCondition(
                    left: .unsupported(rawValue: cleanedTrigger),
                    operatorName: .changes,
                    right: .literalString("changed"),
                    triggerPolicy: .always
                )
            )
        let trigger = HomeAutomationTrigger.device(
            HomeAutomationDeviceTrigger(description: cleanedTrigger, condition: condition)
        )
        return HomeAutomationRuleDraft(
            name: Self.name(for: actions, trigger: trigger),
            trigger: trigger,
            condition: nil,
            actionDescriptions: actions,
            confidence: 0.72
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
        if let match = normalized.firstMatch(of: #"\bevery\s+(\d+)\s+(minute|minutes|hour|hours|day|days)\b"#),
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
        return .everyDay
    }

    private static func extractTime(from normalized: String) -> HomeAutomationTimeOfDay? {
        guard let match = normalized.firstMatch(of: #"\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#),
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
        text
            .replacingOccurrences(of: #"(?i)\bevery\s+day\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\beveryday\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bdaily\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bweekdays\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bweekends\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bevery\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bevery\s+\d+\s+(minute|minutes|hour|hours|day|days)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bat\s+\d{1,2}(:\d{2})?\s*(am|pm)?\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bschedule\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bcreate\s+(an?\s+)?(automation|rule)\s+to\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func actionDescriptions(from text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: #"\s*,\s*and\s+"#, with: " and ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*,\s*"#, with: " and ", options: .regularExpression)
        return normalized
            .components(separatedBy: " and ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func condition(
        from text: String,
        triggerPolicy: HomeAutomationConditionTriggerPolicy
    ) -> HomeAutomationCondition? {
        let normalized = HomeOperationDetectionService.normalized(text)
        if normalized.contains(" and ") {
            let children = normalized
                .components(separatedBy: " and ")
                .compactMap { condition(from: $0, triggerPolicy: triggerPolicy) }
            return children.isEmpty ? nil : .and(children)
        }
        if normalized.contains(" or ") {
            let children = normalized
                .components(separatedBy: " or ")
                .compactMap { condition(from: $0, triggerPolicy: triggerPolicy) }
            return children.isEmpty ? nil : .or(children)
        }
        if normalized.hasPrefix("not ") {
            return condition(from: String(normalized.dropFirst(4)), triggerPolicy: triggerPolicy).map { .not($0) }
        }

        let valuePairs: [(String, String)] = [
            (" is closed", "closed"),
            (" is open", "open"),
            (" opens", "open"),
            (" closes", "closed"),
            (" is on", "on"),
            (" is off", "off"),
            (" motion is detected", "active"),
            (" detects motion", "active")
        ]
        for (phrase, value) in valuePairs where normalized.contains(phrase) {
            let leftDescription = normalized
                .replacingOccurrences(of: phrase, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .comparison(
                HomeAutomationComparisonCondition(
                    left: .deviceAttribute(
                        description: leftDescription.isEmpty ? normalized : leftDescription,
                        deviceID: nil,
                        capability: nil,
                        attribute: nil
                    ),
                    operatorName: .equals,
                    right: .literalString(value),
                    triggerPolicy: triggerPolicy
                )
            )
        }
        if let match = normalized.firstMatch(of: #"(.+)\s+(above|greater than|over|below|less than|under)\s+(\d+)"#),
           let value = Double(match[3]) {
            let op: HomeAutomationComparisonOperator = ["above", "greater than", "over"].contains(match[2]) ? .greaterThan : .lessThan
            return .comparison(
                HomeAutomationComparisonCondition(
                    left: .deviceAttribute(description: match[1], deviceID: nil, capability: nil, attribute: nil),
                    operatorName: op,
                    right: .literalNumber(value, unit: nil),
                    triggerPolicy: triggerPolicy
                )
            )
        }
        return nil
    }

    private static func name(for actions: [String], trigger: HomeAutomationTrigger) -> String {
        let action = actions.first ?? "Automation"
        return "\(action) \(trigger.displayString)"
    }
}

private extension String {
    func firstMatch(of pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: nsRange) else {
            return nil
        }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound,
                  let swiftRange = Range(range, in: self) else {
                return ""
            }
            return String(self[swiftRange])
        }
    }
}
