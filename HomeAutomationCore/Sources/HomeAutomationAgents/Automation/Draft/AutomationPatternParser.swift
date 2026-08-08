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

        if let inlineDeviceTrigger = parseInlineDeviceTrigger(commandText, normalized: normalized) {
            return inlineDeviceTrigger
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

    internal static func name(for actions: [String], trigger: AutomationTriggerOutput) -> String {
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
}
