import Foundation

public struct HomeAutomationTimeOfDay: Sendable, Hashable, Codable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public var minutesAfterMidnight: Int {
        hour * 60 + minute
    }

    public var displayString: String {
        let normalizedHour = hour % 24
        let suffix = normalizedHour >= 12 ? "PM" : "AM"
        let displayHour = {
            let value = normalizedHour % 12
            return value == 0 ? 12 : value
        }()
        return String(format: "%d:%02d %@", displayHour, minute, suffix)
    }
}

public enum HomeAutomationTimeUnit: String, Sendable, Hashable, Codable {
    case minute
    case hour
    case day
}

public enum HomeAutomationWeekday: String, Sendable, Hashable, Codable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday
}

public enum HomeAutomationRepeatRule: Sendable, Hashable, Codable {
    case once
    case everyDay
    case interval(value: Int, unit: HomeAutomationTimeUnit)
    case daysOfWeek([HomeAutomationWeekday])
    case unsupported(rawValue: String)

    public var displayString: String {
        switch self {
        case .once:
            return "once"
        case .everyDay:
            return "every day"
        case .interval(let value, let unit):
            return "every \(value) \(unit.rawValue)\(value == 1 ? "" : "s")"
        case .daysOfWeek(let days):
            return days.map(\.rawValue).joined(separator: ", ")
        case .unsupported(let rawValue):
            return rawValue
        }
    }
}

public struct HomeAutomationScheduleTrigger: Sendable, Hashable, Codable {
    public let repeatRule: HomeAutomationRepeatRule
    public let timeOfDay: HomeAutomationTimeOfDay?
    public let timezoneIdentifier: String?

    public init(
        repeatRule: HomeAutomationRepeatRule,
        timeOfDay: HomeAutomationTimeOfDay?,
        timezoneIdentifier: String? = nil
    ) {
        self.repeatRule = repeatRule
        self.timeOfDay = timeOfDay
        self.timezoneIdentifier = timezoneIdentifier
    }
}

public struct HomeAutomationDeviceTrigger: Sendable, Hashable, Codable {
    public let description: String
    public let condition: HomeAutomationCondition

    public init(description: String, condition: HomeAutomationCondition) {
        self.description = description
        self.condition = condition
    }
}

public enum HomeAutomationTrigger: Sendable, Hashable, Codable {
    case schedule(HomeAutomationScheduleTrigger)
    case device(HomeAutomationDeviceTrigger)

    public var displayString: String {
        switch self {
        case .schedule(let schedule):
            let time = schedule.timeOfDay?.displayString ?? "unspecified time"
            return "\(schedule.repeatRule.displayString) at \(time)"
        case .device(let trigger):
            return trigger.description
        }
    }
}

public enum HomeAutomationComparisonOperator: String, Sendable, Hashable, Codable {
    case equals
    case greaterThan
    case lessThan
    case greaterThanOrEquals
    case lessThanOrEquals
    case between
    case changes
}

public enum HomeAutomationConditionTriggerPolicy: String, Sendable, Hashable, Codable {
    case always
    case never
}

public enum HomeAutomationConditionOperand: Sendable, Hashable, Codable {
    case deviceAttribute(description: String, deviceID: String?, capability: String?, attribute: String?)
    case literalString(String)
    case literalNumber(Double, unit: String?)
    case literalRange(start: Double, end: Double, unit: String?)
    case locationMode(String)
    case unsupported(rawValue: String)
}

public struct HomeAutomationComparisonCondition: Sendable, Hashable, Codable {
    public let left: HomeAutomationConditionOperand
    public let operatorName: HomeAutomationComparisonOperator
    public let right: HomeAutomationConditionOperand
    public let triggerPolicy: HomeAutomationConditionTriggerPolicy

    public init(
        left: HomeAutomationConditionOperand,
        operatorName: HomeAutomationComparisonOperator,
        right: HomeAutomationConditionOperand,
        triggerPolicy: HomeAutomationConditionTriggerPolicy = .never
    ) {
        self.left = left
        self.operatorName = operatorName
        self.right = right
        self.triggerPolicy = triggerPolicy
    }
}

public indirect enum HomeAutomationCondition: Sendable, Hashable, Codable {
    case and([HomeAutomationCondition])
    case or([HomeAutomationCondition])
    case not(HomeAutomationCondition)
    case changes(HomeAutomationCondition)
    case comparison(HomeAutomationComparisonCondition)
}

public extension HomeAutomationCondition {
    /// Human-readable, parenthesized rendering of the condition's boolean
    /// structure — e.g. `(Light is on AND Fan is off) OR TV is off`. Nested
    /// AND/OR groups are wrapped in parentheses so the committed precedence
    /// reading is unambiguous; the outermost group is not. Pass `deviceNames`
    /// to substitute resolved device IDs with display names.
    func parenthesizedDescription(deviceNames: [String: String] = [:]) -> String {
        render(nested: false, deviceNames: deviceNames)
    }

    private func render(nested: Bool, deviceNames: [String: String]) -> String {
        switch self {
        case .and(let children):
            return Self.joinGroup(children, separator: " AND ", nested: nested, deviceNames: deviceNames)
        case .or(let children):
            return Self.joinGroup(children, separator: " OR ", nested: nested, deviceNames: deviceNames)
        case .not(let child):
            return "NOT \(child.render(nested: true, deviceNames: deviceNames))"
        case .changes(let child):
            return "changes \(child.render(nested: true, deviceNames: deviceNames))"
        case .comparison(let comparison):
            return comparison.readableDescription(deviceNames: deviceNames)
        }
    }

    private static func joinGroup(
        _ children: [HomeAutomationCondition],
        separator: String,
        nested: Bool,
        deviceNames: [String: String]
    ) -> String {
        let parts = children.map { $0.render(nested: true, deviceNames: deviceNames) }
        let joined = parts.joined(separator: separator)
        guard children.count > 1 else { return joined }
        return nested ? "(\(joined))" : joined
    }
}

public extension HomeAutomationComparisonCondition {
    /// Renders a single comparison as a natural clause. Prefers a resolved
    /// device display name plus the operator/value (`Fan is off`); falls back to
    /// the operand's raw description, which for deterministically drafted
    /// automations already reads as a full clause.
    func readableDescription(deviceNames: [String: String] = [:]) -> String {
        if case .deviceAttribute(let description, let deviceID, _, _) = left {
            if let deviceID, let name = deviceNames[deviceID] {
                return "\(name) \(valuePhrase())"
            }
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "\(Self.operandText(left)) \(valuePhrase())"
    }

    private func valuePhrase() -> String {
        let value = Self.operandText(right)
        switch operatorName {
        case .equals: return "is \(value)"
        case .greaterThan: return "is above \(value)"
        case .lessThan: return "is below \(value)"
        case .greaterThanOrEquals: return "is at least \(value)"
        case .lessThanOrEquals: return "is at most \(value)"
        case .between: return "is between \(value)"
        case .changes: return "changes to \(value)"
        }
    }

    private static func operandText(_ operand: HomeAutomationConditionOperand) -> String {
        switch operand {
        case .deviceAttribute(let description, _, _, _):
            return description
        case .literalString(let value), .locationMode(let value), .unsupported(let value):
            return value
        case .literalNumber(let value, let unit):
            let number = value.rounded() == value ? String(Int(value)) : String(value)
            return unit.map { "\(number) \($0)" } ?? number
        case .literalRange(let start, let end, let unit):
            let range = "\(start) and \(end)"
            return unit.map { "\(range) \($0)" } ?? range
        }
    }
}

public struct HomeAutomationRuleDraft: Sendable, Hashable, Codable {
    public let name: String
    public let domain: HomeAutomationCommandDomain
    public let operation: HomeAutomationOperationKind
    public let intent: HomeAutomationIntentFamily
    public let trigger: HomeAutomationTrigger?
    public let condition: HomeAutomationCondition?
    public let actionDescriptions: [String]
    public let confidence: Double

    public init(
        name: String,
        domain: HomeAutomationCommandDomain = .homeAutomation,
        operation: HomeAutomationOperationKind = .automationCreation,
        intent: HomeAutomationIntentFamily = .createAutomation,
        trigger: HomeAutomationTrigger?,
        condition: HomeAutomationCondition?,
        actionDescriptions: [String],
        confidence: Double
    ) {
        self.name = name
        self.domain = domain
        self.operation = operation
        self.intent = intent
        self.trigger = trigger
        self.condition = condition
        self.actionDescriptions = actionDescriptions
        self.confidence = confidence
    }
}

public struct HomeAutomationResolvedAction: Sendable, Hashable, Codable {
    public let originalText: String
    public let draft: HomeCommandDraft
    public let device: HomeCandidateRecord?
    public let confidence: Double

    public init(
        originalText: String,
        draft: HomeCommandDraft,
        device: HomeCandidateRecord?,
        confidence: Double
    ) {
        self.originalText = originalText
        self.draft = draft
        self.device = device
        self.confidence = confidence
    }
}
