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
        let actions: [SmartThingsRuleAction]

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
            actions = [
                .conditional(
                    SmartThingsIfAction(
                        condition: try conditionRule(deviceTrigger.condition, triggerDefault: .always),
                        thenActions: try wrapWithConditionIfNeeded(
                            commandActions,
                            condition: plan.ruleDraft.condition
                        )
                    )
                )
            ]
        }

        return try SmartThingsRuleDocument(
            payload: SmartThingsRulePayload(name: plan.name, actions: actions)
        )
    }

    private func everyAction(
        schedule: HomeAutomationScheduleTrigger,
        nestedActions: [SmartThingsRuleAction]
    ) throws -> SmartThingsRuleAction {
        switch schedule.repeatRule {
        case .everyDay:
            guard let timeOfDay = schedule.timeOfDay else {
                throw SmartThingsRuleCompileError.unsupportedSchedule(schedule.repeatRule)
            }
            return .every(
                SmartThingsEveryAction(
                    schedule: .specific(
                        reference: "Midnight",
                        offsetMinutes: timeOfDay.minutesAfterMidnight
                    ),
                    actions: nestedActions
                )
            )
        case .interval(let value, let unit):
            return .every(
                SmartThingsEveryAction(
                    schedule: .interval(
                        value: value,
                        unit: smartThingsTimeUnit(for: unit)
                    ),
                    actions: nestedActions
                )
            )
        case .once, .daysOfWeek, .unsupported:
            throw SmartThingsRuleCompileError.unsupportedSchedule(schedule.repeatRule)
        }
    }

    private func smartThingsTimeUnit(for unit: HomeAutomationTimeUnit) -> String {
        switch unit {
        case .minute:
            return "Minute"
        case .hour:
            return "Hour"
        case .day:
            return "Day"
        }
    }

    private func commandAction(_ action: HomeAutomationResolvedAction) throws -> SmartThingsRuleAction {
        guard let device = action.device,
              let capability = action.draft.capability,
              let command = action.draft.command else {
            throw SmartThingsRuleCompileError.unresolvedAction(action.originalText)
        }

        return .command(
            SmartThingsCommandAction(
                devices: [device.id],
                commands: [
                    SmartThingsCommand(
                        capability: capability,
                        command: command,
                        arguments: commandArguments(from: action.draft.parameters)
                    )
                ]
            )
        )
    }

    private func commandArguments(from parameters: [HomeResolvedParameter]) -> [SmartThingsRuleJSONValue] {
        parameters.compactMap { parameter in
            if let numericValue = parameter.numericValue {
                if numericValue.rounded() == numericValue {
                    return .integer(Int(numericValue))
                }
                return .decimal(numericValue)
            }
            guard let value = parameter.value else { return nil }
            return .string(value)
        }
    }

    private func wrapWithConditionIfNeeded(
        _ actions: [SmartThingsRuleAction],
        condition: HomeAutomationCondition?
    ) throws -> [SmartThingsRuleAction] {
        guard let condition else { return actions }
        return [
            .conditional(
                SmartThingsIfAction(
                    condition: try conditionRule(condition, triggerDefault: .never),
                    thenActions: actions
                )
            )
        ]
    }

    private func conditionRule(
        _ condition: HomeAutomationCondition,
        triggerDefault: HomeAutomationConditionTriggerPolicy
    ) throws -> SmartThingsRuleCondition {
        switch condition {
        case .and(let children):
            return .and(try children.map { try conditionRule($0, triggerDefault: triggerDefault) })
        case .or(let children):
            return .or(try children.map { try conditionRule($0, triggerDefault: triggerDefault) })
        case .not(let child):
            return .not(try conditionRule(child, triggerDefault: triggerDefault))
        case .comparison(let comparison):
            switch comparison.operatorName {
            case .between, .changes:
                throw SmartThingsRuleCompileError.unsupportedCondition(
                    "\(comparison.operatorName.rawValue) condition compilation is not implemented"
                )
            case .equals, .greaterThan, .lessThan, .greaterThanOrEquals, .lessThanOrEquals:
                break
            }

            let triggerPolicy: SmartThingsRuleTriggerPolicy =
                comparison.triggerPolicy == .always || triggerDefault == .always ? .always : .never
            return .comparison(
                operatorName: comparison.operatorName.rawValue,
                left: try operandRule(comparison.left, triggerPolicy: triggerPolicy),
                right: try operandRule(comparison.right, triggerPolicy: triggerPolicy)
            )
        }
    }

    private func operandRule(
        _ operand: HomeAutomationConditionOperand,
        triggerPolicy: SmartThingsRuleTriggerPolicy
    ) throws -> SmartThingsRuleOperand {
        switch operand {
        case .deviceAttribute(let description, let deviceID, let capability, let attribute):
            guard let deviceID, let capability, let attribute else {
                throw SmartThingsRuleCompileError.unresolvedConditionOperand(description)
            }
            return .deviceAttribute(
                devices: [deviceID],
                component: "main",
                capability: capability,
                attribute: attribute,
                trigger: triggerPolicy
            )
        case .literalString(let value):
            return .string(value)
        case .literalNumber(let value, let unit):
            if value.rounded() == value, unit == nil {
                return .integer(Int(value))
            }
            return .decimal(value, unit: unit)
        case .locationMode(let value):
            return .locationMode(value)
        case .unsupported(let rawValue):
            throw SmartThingsRuleCompileError.unsupportedCondition(rawValue)
        }
    }
}
