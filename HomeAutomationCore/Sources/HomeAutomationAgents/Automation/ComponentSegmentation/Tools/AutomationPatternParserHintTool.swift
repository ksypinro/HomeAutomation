import Foundation
import HomeAutomationCore

public enum AutomationPatternParserHintTool {
    public static func fallbackPlan(for text: String) -> AutomationComponentPlan? {
        guard let output = AutomationPatternParser().parse(text) else { return nil }
        return componentPlan(from: output, sourceText: text)
    }

    public static func componentPlan(
        from output: AutomationDraftOutput,
        sourceText: String
    ) -> AutomationComponentPlan {
        let split = AutomationPatternParser.splitCondition(from: sourceText)
        let actions = output.actionDescriptions.enumerated().map { index, action in
            AutomationActionComponent(
                id: "a\(index + 1)",
                rawText: action,
                order: index
            )
        }
        let trigger = output.trigger.map {
            AutomationTriggerComponent(
                id: "t1",
                rawText: rawTriggerText(from: $0),
                kindHint: $0.type == .schedule ? .schedule : .device
            )
        }
        let triggerCondition = output.trigger?.type == .device ? output.trigger?.condition : nil
        let conditionParts = conditionComponents(
            from: output.condition ?? triggerCondition,
            rawText: split.conditionText ?? output.trigger?.description
        )
        return AutomationComponentPlan(
            trigger: trigger,
            actions: actions,
            conditions: conditionParts.components,
            conditionTree: conditionParts.tree,
            unsupportedFragments: output.unsupportedFragments,
            confidence: output.confidence
        )
    }

    private static func rawTriggerText(from trigger: AutomationTriggerOutput) -> String {
        switch trigger.type {
        case .schedule:
            let repeatRule = trigger.repeatRule ?? "everyDay"
            let time = displayTime(trigger.time)
            return [displayRepeatRule(repeatRule), time]
                .compactMap { $0 }
                .joined(separator: " at ")
        case .device:
            return trigger.description ?? "device trigger"
        }
    }

    private static func conditionComponents(
        from condition: AutomationConditionOutput?,
        rawText: String?
    ) -> (components: [AutomationConditionComponent], tree: AutomationConditionTreeDescriptor?) {
        guard let condition else { return ([], nil) }
        var components: [AutomationConditionComponent] = []
        let tree = conditionTree(
            from: condition,
            rawText: rawText?.trimmingCharacters(in: .whitespacesAndNewlines),
            components: &components
        )
        return (components, tree)
    }

    private static func conditionTree(
        from condition: AutomationConditionOutput,
        rawText: String?,
        components: inout [AutomationConditionComponent]
    ) -> AutomationConditionTreeDescriptor? {
        switch condition.type {
        case .and, .or:
            let separator = condition.type == .and ? " and " : " or "
            let segments = rawText.flatMap {
                AutomationPatternParser.logicalSegments(
                    in: AutomationPatternParser.normalized($0),
                    separator: separator
                )
            }
            let children = condition.children.enumerated().compactMap { index, child in
                conditionTree(
                    from: child,
                    rawText: segments?.indices.contains(index) == true ? segments?[index] : nil,
                    components: &components
                )
            }
            guard !children.isEmpty else { return nil }
            return condition.type == .and ? .and(children) : .or(children)
        case .not:
            guard let child = condition.children.first,
                  let tree = conditionTree(from: child, rawText: rawText, components: &components) else {
                return nil
            }
            return .not(tree)
        case .changes, .comparison:
            let id = "c\(components.count + 1)"
            let text = rawText.flatMap(nonEmpty) ?? conditionDescription(condition)
            components.append(AutomationConditionComponent(id: id, rawText: text, order: components.count))
            return .leaf(id)
        }
    }

    private static func conditionDescription(_ condition: AutomationConditionOutput) -> String {
        if let left = condition.left?.description,
           let right = condition.right?.stringValue ?? condition.right?.description {
            return "\(left) \(condition.operatorName?.rawValue ?? "equals") \(right)"
        }
        return "condition"
    }

    private static func displayRepeatRule(_ value: String) -> String {
        switch AutomationPatternParser.normalized(value) {
        case "everyday", "every day", "daily":
            return "every day"
        default:
            return value
        }
    }

    private static func displayTime(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = AutomationPatternParser.normalized(value)
        guard let match = normalized.firstAutomationMatch(of: #"^(\d{1,2})(?::(\d{2}))?$"#),
              let hour = Int(match[1]) else {
            return value
        }
        let minute = Int(match[2]) ?? 0
        let suffix = hour >= 12 ? "PM" : "AM"
        let displayHour = {
            let value = hour % 12
            return value == 0 ? 12 : value
        }()
        return minute == 0 ? "\(displayHour) \(suffix)" : String(format: "%d:%02d %@", displayHour, minute, suffix)
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
