import Foundation
import HomeAutomationCore

/// Condition parsing methods for automation pattern parsing.
extension AutomationPatternParser {
    internal static func conversationalCondition(from text: String, normalized: String) -> AutomationConditionOutput? {
        temperatureCondition(from: text, normalized: normalized)
    }

    internal static func temperatureCondition(from text: String, normalized: String) -> AutomationConditionOutput? {
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

    internal static func temperatureReading(from normalized: String) -> (sensorDescription: String, value: Double)? {
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

    internal static func temperatureOperator(from normalized: String) -> AutomationComparisonOperatorOutput {
        if containsAnyWord(normalized, ["cold", "cool", "freezing", "chilly"]) {
            return .lessThanOrEquals
        }
        if containsAnyWord(normalized, ["hot", "warm", "heat"]) || normalized.contains("too high") {
            return .greaterThanOrEquals
        }
        return .equals
    }

    internal static func temperatureUnit(from normalized: String) -> String? {
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

    internal static func cleanConditionDescription(_ value: String) -> String {
        normalized(value)
            .replacingOccurrences(of: #"^(the|a|an)\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    internal static func containsAnyWord(_ text: String, _ words: [String]) -> Bool {
        words.contains { word in
            let escaped = NSRegularExpression.escapedPattern(for: word)
            return text.range(of: #"\b\#(escaped)\b"#, options: .regularExpression) != nil
        }
    }

    internal static func operatorText(_ operatorName: AutomationComparisonOperatorOutput) -> String {
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

    internal static func condition(
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

        if let match = normalized.firstAutomationMatch(
            of: #"^(.+?)\s+(?:is\s+)?(at least|greater than or equal to|above or equal to|at most|less than or equal to|below or equal to)\s+(\d+(?:\.\d+)?)\s*(celsius|fahrenheit|degrees?|degree c|degrees c|degree f|degrees f)?$"#
        ),
           let value = Double(match[3]) {
            let op: AutomationComparisonOperatorOutput = ["at least", "greater than or equal to", "above or equal to"].contains(match[2])
                ? .greaterThanOrEquals
                : .lessThanOrEquals
            return AutomationConditionOutput(
                type: .comparison,
                left: AutomationConditionOperandOutput(type: .deviceAttribute, description: match[1]),
                operatorName: op,
                right: AutomationConditionOperandOutput(
                    type: .literalNumber,
                    numberValue: value,
                    unit: normalizedConditionUnit(match[4])
                ),
                triggerPolicy: triggerPolicy
            )
        }

        if let match = normalized.firstAutomationMatch(of: #"^(.+)\s+(above|greater than|over|below|less than|under)\s+(\d+(?:\.\d+)?)\s*(celsius|fahrenheit|degrees?|degree c|degrees c|degree f|degrees f)?$"#),
           let value = Double(match[3]) {
            let op: AutomationComparisonOperatorOutput = ["above", "greater than", "over"].contains(match[2])
                ? .greaterThan
                : .lessThan
            return AutomationConditionOutput(
                type: .comparison,
                left: AutomationConditionOperandOutput(type: .deviceAttribute, description: match[1]),
                operatorName: op,
                right: AutomationConditionOperandOutput(
                    type: .literalNumber,
                    numberValue: value,
                    unit: normalizedConditionUnit(match[4])
                ),
                triggerPolicy: triggerPolicy
            )
        }

        return nil
    }

    private static func normalizedConditionUnit(_ value: String) -> String? {
        let normalized = normalized(value)
        if normalized.isEmpty { return nil }
        if normalized.contains("fahrenheit") || normalized.contains("degree f") || normalized.contains("degrees f") {
            return "fahrenheit"
        }
        if normalized.contains("celsius") || normalized.contains("degree") {
            return "celsius"
        }
        return normalized
    }

    internal static func logicalSegments(in normalized: String, separator: String) -> [String]? {
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
}
