import Foundation

public protocol HomeAutomationRuleCompiling: Sendable {
    func compile(_ plan: HomeAutomationCreationPlan) throws -> SmartThingsRuleDocument
}

public struct SmartThingsRuleCompiler: HomeAutomationRuleCompiling {
    public init() {}

    public func compile(_ plan: HomeAutomationCreationPlan) throws -> SmartThingsRuleDocument {
        guard let trigger = plan.ruleDraft.trigger else {
            throw SmartThingsRuleCompileError.unsupportedTrigger("Missing automation trigger")
        }

        let commandActions = try plan.resolvedActions.map(commandAction)
        let actions: [[String: Any]]

        switch trigger {
        case .schedule(let schedule):
            actions = [
                try everyAction(
                    schedule: schedule,
                    nestedActions: wrapWithConditionIfNeeded(
                        commandActions,
                        condition: plan.ruleDraft.condition
                    )
                )
            ]
        case .device(let deviceTrigger):
            let condition = try conditionJSON(deviceTrigger.condition, triggerDefault: .always)
            actions = [
                [
                    "if": [
                        "condition": condition,
                        "then": try wrapWithConditionIfNeeded(
                            commandActions,
                            condition: plan.ruleDraft.condition
                        )
                    ]
                ]
            ]
        }

        let root: [String: Any] = [
            "name": plan.name,
            "actions": actions
        ]

        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return SmartThingsRuleDocument(name: plan.name, jsonString: json)
    }

    private func everyAction(
        schedule: HomeAutomationScheduleTrigger,
        nestedActions: [[String: Any]]
    ) throws -> [String: Any] {
        switch schedule.repeatRule {
        case .everyDay:
            guard let timeOfDay = schedule.timeOfDay else {
                throw SmartThingsRuleCompileError.unsupportedSchedule(schedule.repeatRule)
            }
            return [
                "every": [
                    "specific": [
                        "reference": "Midnight",
                        "offset": [
                            "value": ["integer": timeOfDay.minutesAfterMidnight],
                            "unit": "Minute"
                        ]
                    ],
                    "actions": nestedActions
                ]
            ]
        case .interval(let value, let unit):
            let smartThingsUnit: String
            switch unit {
            case .minute:
                smartThingsUnit = "Minute"
            case .hour:
                smartThingsUnit = "Hour"
            case .day:
                smartThingsUnit = "Day"
            }
            return [
                "every": [
                    "interval": [
                        "value": ["integer": value],
                        "unit": smartThingsUnit
                    ],
                    "actions": nestedActions
                ]
            ]
        case .once, .daysOfWeek, .unsupported:
            throw SmartThingsRuleCompileError.unsupportedSchedule(schedule.repeatRule)
        }
    }

    private func commandAction(_ action: HomeAutomationResolvedAction) throws -> [String: Any] {
        guard let device = action.device,
              let capability = action.draft.capability,
              let command = action.draft.command else {
            throw SmartThingsRuleCompileError.unresolvedAction(action.originalText)
        }

        return [
            "command": [
                "devices": [device.id],
                "commands": [
                    [
                        "component": "main",
                        "capability": capability,
                        "command": command,
                        "arguments": commandArguments(from: action.draft.parameters)
                    ]
                ]
            ]
        ]
    }

    private func commandArguments(from parameters: [HomeResolvedParameter]) -> [Any] {
        parameters.compactMap { parameter in
            if let numericValue = parameter.numericValue {
                if numericValue.rounded() == numericValue {
                    return Int(numericValue)
                }
                return numericValue
            }
            return parameter.value
        }
    }

    private func wrapWithConditionIfNeeded(
        _ actions: [[String: Any]],
        condition: HomeAutomationCondition?
    ) throws -> [[String: Any]] {
        guard let condition else { return actions }
        return [
            [
                "if": [
                    "condition": try conditionJSON(condition, triggerDefault: .never),
                    "then": actions
                ]
            ]
        ]
    }

    private func conditionJSON(
        _ condition: HomeAutomationCondition,
        triggerDefault: HomeAutomationConditionTriggerPolicy
    ) throws -> [String: Any] {
        switch condition {
        case .and(let children):
            return ["and": try children.map { try conditionJSON($0, triggerDefault: triggerDefault) }]
        case .or(let children):
            return ["or": try children.map { try conditionJSON($0, triggerDefault: triggerDefault) }]
        case .not(let child):
            return ["not": try conditionJSON(child, triggerDefault: triggerDefault)]
        case .comparison(let comparison):
            let op = comparison.operatorName.rawValue
            return [
                op: [
                    "left": try operandJSON(comparison.left),
                    "right": try operandJSON(comparison.right),
                    "trigger": comparison.triggerPolicy == .always || triggerDefault == .always ? "Always" : "Never"
                ]
            ]
        }
    }

    private func operandJSON(_ operand: HomeAutomationConditionOperand) throws -> [String: Any] {
        switch operand {
        case .deviceAttribute(let description, let deviceID, let capability, let attribute):
            guard let deviceID, let capability, let attribute else {
                throw SmartThingsRuleCompileError.unsupportedCondition("Unresolved device condition operand: \(description)")
            }
            return [
                "device": [
                    "devices": [deviceID],
                    "component": "main",
                    "capability": capability,
                    "attribute": attribute
                ]
            ]
        case .literalString(let value):
            return ["string": value]
        case .literalNumber(let value, let unit):
            var number: [String: Any] = ["decimal": value]
            if let unit {
                number["unit"] = unit
            }
            return ["value": number]
        case .locationMode(let value):
            return ["locationMode": value]
        case .unsupported(let rawValue):
            throw SmartThingsRuleCompileError.unsupportedCondition(rawValue)
        }
    }
}
