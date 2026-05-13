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
    case comparison(HomeAutomationComparisonCondition)
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
