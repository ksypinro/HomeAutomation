import Foundation
import HomeAutomationCore

public struct AutomationPatternParser: Sendable {
    public init() {}

    public func parse(_ text: String) -> AutomationDraftOutput? {
        let commandText = AgentTextParser.userCommandText(from: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = Self.normalized(commandText)
        guard !commandText.isEmpty else { return nil }

        if let conversationalRoutine = parseConversationalRoutine(commandText, normalized: normalized) {
            return conversationalRoutine
        }

        if normalized.hasPrefix("when ") || normalized.hasPrefix("whenever ") {
            return parseDeviceTrigger(commandText, normalized: normalized)
        }

        let split = Self.splitCondition(from: commandText)
        guard let time = Self.extractTime(from: normalized) else {
            return parseConditionOnlyAction(actionText: split.actionText, conditionText: split.conditionText)
        }

        let repeatRule = Self.extractRepeatRule(from: normalized)
        let unsupportedFragments = Self.unsupportedFragments(in: normalized, repeatRule: repeatRule)
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

    private func parseConversationalRoutine(_ text: String, normalized: String) -> AutomationDraftOutput? {
        guard Self.hasConversationalRoutineSignal(normalized),
              let actionText = Self.conversationalAction(from: text),
              let condition = Self.conversationalCondition(from: text, normalized: normalized) else {
            return nil
        }

        let actions = Self.actionDescriptions(from: Self.cleanedActionText(actionText))
        guard !actions.isEmpty else { return nil }

        let trigger = AutomationTriggerOutput(
            type: .device,
            description: Self.triggerDescription(for: condition),
            condition: condition
        )

        return AutomationDraftOutput(
            name: Self.name(for: actions, trigger: trigger),
            trigger: trigger,
            condition: nil,
            actionDescriptions: actions,
            unsupportedFragments: [],
            confidence: 0.91
        )
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

    private func parseConditionOnlyAction(
        actionText: String,
        conditionText: String?
    ) -> AutomationDraftOutput? {
        guard let conditionText,
              let condition = Self.condition(from: conditionText, triggerPolicy: .always) else {
            return nil
        }

        let actions = Self.actionDescriptions(from: Self.cleanedActionText(actionText))
        guard !actions.isEmpty else { return nil }

        let trigger = AutomationTriggerOutput(
            type: .device,
            description: conditionText.trimmingCharacters(in: .whitespacesAndNewlines),
            condition: condition
        )
        return AutomationDraftOutput(
            name: Self.name(for: actions, trigger: trigger),
            trigger: trigger,
            condition: nil,
            actionDescriptions: actions,
            unsupportedFragments: [],
            confidence: 0.90
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

    private static func hasConversationalRoutineSignal(_ normalized: String) -> Bool {
        let routineSignals = [
            "remember this",
            "remember that",
            "similar situation",
            "similar situations",
            "when this happens",
            "whenever this happens",
            "from now on",
            "next time"
        ]
        let actionSignals = [
            "turn on",
            "turn off",
            "switch on",
            "switch off",
            "set ",
            "increase",
            "decrease",
            "lock",
            "unlock",
            "open",
            "close",
            "start",
            "stop"
        ]
        return routineSignals.contains { normalized.contains($0) } &&
            actionSignals.contains { normalized.contains($0) }
    }

    private static func conversationalAction(from text: String) -> String? {
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

    private static func conversationalCondition(from text: String, normalized: String) -> AutomationConditionOutput? {
        temperatureCondition(from: text, normalized: normalized)
    }

    private static func temperatureCondition(from text: String, normalized: String) -> AutomationConditionOutput? {
        guard let reading = temperatureReading(from: normalized) ?? temperatureReading(from: Self.normalized(text)) else {
            return nil
        }

        return AutomationConditionOutput(
            type: .comparison,
            left: AutomationConditionOperandOutput(
                type: .deviceAttribute,
                description: reading.sensorDescription
            ),
            operatorName: temperatureOperator(from: normalized),
            right: AutomationConditionOperandOutput(
                type: .literalNumber,
                numberValue: reading.value,
                unit: temperatureUnit(from: normalized)
            ),
            triggerPolicy: .always
        )
    }

    private static func temperatureReading(from normalized: String) -> (sensorDescription: String, value: Double)? {
        if let match = normalized.firstAutomationMatch(
            of: #"\b((?:(?:bedroom|living room|kitchen|hallway|entry|front|back|nursery|basement|garage|porch|patio)\s+)?temperature\s+sensor)\s+(?:is\s+)?(?:showing|shows|reading|reads|reports|says|is\s+at|at)\s+(\d+(?:\.\d+)?)\b"#
        ),
           let value = Double(match[2]) {
            return (cleanConditionDescription(match[1]), value)
        }

        if let match = normalized.firstAutomationMatch(
            of: #"\btemperature\s+(?:is\s+)?(?:showing|shows|reading|reads|reports|says|is\s+at|at)\s+(\d+(?:\.\d+)?)\b"#
        ),
           let value = Double(match[1]) {
            return ("temperature sensor", value)
        }

        return nil
    }

    private static func temperatureOperator(from normalized: String) -> AutomationComparisonOperatorOutput {
        if containsAnyWord(normalized, ["cold", "cool", "freezing", "chilly"]) {
            return .lessThanOrEquals
        }
        if containsAnyWord(normalized, ["hot", "warm", "heat"]) || normalized.contains("too high") {
            return .greaterThanOrEquals
        }
        return .equals
    }

    private static func temperatureUnit(from normalized: String) -> String? {
        if normalized.contains("celsius") ||
            normalized.contains("celcius") ||
            normalized.contains("degree c") ||
            normalized.contains("degrees c") {
            return "celsius"
        }
        if normalized.contains("fahrenheit") ||
            normalized.contains("degree f") ||
            normalized.contains("degrees f") {
            return "fahrenheit"
        }
        return normalized.contains("degree") || normalized.contains("degrees") ? "celsius" : nil
    }

    private static func triggerDescription(for condition: AutomationConditionOutput) -> String {
        guard condition.type == .comparison,
              let left = condition.left?.description,
              let operatorName = condition.operatorName,
              let right = condition.right else {
            return "similar situation"
        }

        let value: String
        if let number = right.numberValue {
            value = number.rounded() == number ? String(Int(number)) : String(number)
        } else {
            value = right.stringValue ?? right.description ?? "value"
        }
        let unit = right.unit.map { " \($0)" } ?? ""
        return "\(left) \(operatorText(operatorName)) \(value)\(unit)"
    }

    private static func cleanConditionDescription(_ value: String) -> String {
        normalized(value)
            .replacingOccurrences(of: #"^(the|a|an)\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsAnyWord(_ text: String, _ words: [String]) -> Bool {
        words.contains { word in
            let escaped = NSRegularExpression.escapedPattern(for: word)
            return text.range(of: #"\b\#(escaped)\b"#, options: .regularExpression) != nil
        }
    }

    private static func operatorText(_ operatorName: AutomationComparisonOperatorOutput) -> String {
        switch operatorName {
        case .equals:
            return "equals"
        case .greaterThan:
            return "greater than"
        case .lessThan:
            return "less than"
        case .greaterThanOrEquals:
            return "is at least"
        case .lessThanOrEquals:
            return "is at most"
        case .between:
            return "between"
        case .changes:
            return "changes"
        }
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

        if let segments = logicalSegments(in: normalized, separator: " or ") {
            let children = segments
                .compactMap { condition(from: $0, triggerPolicy: triggerPolicy) }
            return children.isEmpty ? nil : AutomationConditionOutput(type: .or, children: children)
        }
        if let segments = logicalSegments(in: normalized, separator: " and ") {
            let children = segments
                .compactMap { condition(from: $0, triggerPolicy: triggerPolicy) }
            return children.isEmpty ? nil : AutomationConditionOutput(type: .and, children: children)
        }
        if normalized.hasPrefix("not ") {
            return condition(from: String(normalized.dropFirst(4)), triggerPolicy: triggerPolicy).map {
                AutomationConditionOutput(type: .not, children: [$0])
            }
        }

        if let match = normalized.firstAutomationMatch(
            of: #"^(.+?)\s+(?:is\s+)?between\s+(\d+(?:\.\d+)?)\s+(?:and|to)\s+(\d+(?:\.\d+)?)$"#
        ),
           let start = Double(match[2]),
           let end = Double(match[3]) {
            return AutomationConditionOutput(
                type: .comparison,
                left: AutomationConditionOperandOutput(type: .deviceAttribute, description: match[1]),
                operatorName: .between,
                right: AutomationConditionOperandOutput(
                    type: .literalRange,
                    numberValue: start,
                    endNumberValue: end
                ),
                triggerPolicy: triggerPolicy
            )
        }

        if let match = normalized.firstAutomationMatch(
            of: #"^(.+?)\s+changes\s+(?:to\s+)?(above|greater than|over|below|less than|under)\s+(\d+(?:\.\d+)?)$"#
        ),
           let value = Double(match[3]) {
            let op: AutomationComparisonOperatorOutput = ["above", "greater than", "over"].contains(match[2])
                ? .greaterThan
                : .lessThan
            return AutomationConditionOutput(
                type: .changes,
                children: [
                    AutomationConditionOutput(
                        type: .comparison,
                        left: AutomationConditionOperandOutput(type: .deviceAttribute, description: match[1]),
                        operatorName: op,
                        right: AutomationConditionOperandOutput(type: .literalNumber, numberValue: value),
                        triggerPolicy: triggerPolicy
                    )
                ]
            )
        }

        if let match = normalized.firstAutomationMatch(
            of: #"^(.+?)\s+changes\s+(?:to\s+)?(on|off|open|closed|active|inactive)$"#
        ) {
            return AutomationConditionOutput(
                type: .changes,
                children: [
                    AutomationConditionOutput(
                        type: .comparison,
                        left: AutomationConditionOperandOutput(type: .deviceAttribute, description: match[1]),
                        operatorName: .equals,
                        right: AutomationConditionOperandOutput(type: .literalString, stringValue: match[2]),
                        triggerPolicy: triggerPolicy
                    )
                ]
            )
        }

        let valuePairs: [(String, String)] = [
            (" is turned on", "on"),
            (" is turned off", "off"),
            (" is closed", "closed"),
            (" is open", "open"),
            (" opens", "open"),
            (" closes", "closed"),
            (" turns on", "on"),
            (" turns off", "off"),
            (" turned on", "on"),
            (" turned off", "off"),
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

        if let match = normalized.firstAutomationMatch(of: #"^(.+)\s+(above|greater than|over|below|less than|under)\s+(\d+)$"#),
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

    private static func logicalSegments(in normalized: String, separator: String) -> [String]? {
        var segments: [String] = []
        var segmentStart = normalized.startIndex
        var searchStart = normalized.startIndex

        while let range = normalized.range(of: separator, range: searchStart..<normalized.endIndex) {
            let beforeSeparator = String(normalized[segmentStart..<range.lowerBound])
            if separator == " and ",
               beforeSeparator.firstAutomationMatch(of: #"\bbetween\s+\d+(?:\.\d+)?\s*$"#) != nil {
                searchStart = range.upperBound
                continue
            }

            let segment = beforeSeparator.trimmingCharacters(in: .whitespacesAndNewlines)
            if !segment.isEmpty {
                segments.append(segment)
            }
            segmentStart = range.upperBound
            searchStart = range.upperBound
        }

        guard !segments.isEmpty else { return nil }
        let finalSegment = String(normalized[segmentStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalSegment.isEmpty {
            segments.append(finalSegment)
        }
        return segments
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
