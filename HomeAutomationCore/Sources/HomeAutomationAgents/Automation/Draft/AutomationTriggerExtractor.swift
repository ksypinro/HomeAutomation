import Foundation
import HomeAutomationCore

/// Trigger extraction methods for automation pattern parsing.
extension AutomationPatternParser {
    internal func parseConversationalRoutine(_ text: String, normalized: String) -> AutomationDraftOutput? {
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

    internal func parseDeviceTrigger(_ text: String, normalized: String) -> AutomationDraftOutput? {
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

    internal func parseConditionOnlyAction(
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

    internal static func splitCondition(from text: String) -> (actionText: String, conditionText: String?) {
        guard let range = text.range(of: #"(?i)\s+if\s+"#, options: .regularExpression) else {
            return (text, nil)
        }
        return (
            String(text[..<range.lowerBound]),
            String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    internal static func hasConversationalRoutineSignal(_ normalized: String) -> Bool {
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

    internal static func triggerDescription(for condition: AutomationConditionOutput) -> String {
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
}
