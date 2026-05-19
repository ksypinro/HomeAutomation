import Foundation
import FoundationModels
import HomeAutomationCore

public struct AutomationDraftInput: Sendable, Hashable, Codable {
    public let text: String
    public let operation: HomeOperationDetectionResult?

    public init(
        text: String,
        operation: HomeOperationDetectionResult? = nil
    ) {
        self.text = text
        self.operation = operation
    }
}

public enum AutomationDraftError: LocalizedError, Sendable, Hashable {
    case unsupported(String)
    case invalidOutput(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let reason):
            return reason
        case .invalidOutput(let reason):
            return "Automation draft output was invalid: \(reason)"
        }
    }
}

@Generable
public enum AutomationTriggerOutputType: String, Sendable, Hashable, Codable {
    case schedule
    case device
}

@Generable
public enum AutomationConditionOutputType: String, Sendable, Hashable, Codable {
    case and
    case or
    case not
    case changes
    case comparison
}

@Generable
public enum AutomationConditionOperandOutputType: String, Sendable, Hashable, Codable {
    case deviceAttribute
    case literalString
    case literalNumber
    case literalRange
    case locationMode
    case unsupported
}

@Generable
public enum AutomationComparisonOperatorOutput: String, Sendable, Hashable, Codable {
    case equals
    case greaterThan
    case lessThan
    case greaterThanOrEquals
    case lessThanOrEquals
    case between
    case changes

    public var homeOperator: HomeAutomationComparisonOperator {
        switch self {
        case .equals:
            return .equals
        case .greaterThan:
            return .greaterThan
        case .lessThan:
            return .lessThan
        case .greaterThanOrEquals:
            return .greaterThanOrEquals
        case .lessThanOrEquals:
            return .lessThanOrEquals
        case .between:
            return .between
        case .changes:
            return .changes
        }
    }
}

@Generable
public enum AutomationConditionTriggerPolicyOutput: String, Sendable, Hashable, Codable {
    case always
    case never

    public var homePolicy: HomeAutomationConditionTriggerPolicy {
        switch self {
        case .always:
            return .always
        case .never:
            return .never
        }
    }
}

@Generable
public struct AutomationConditionOperandOutput: Sendable, Hashable, Codable {
    public let type: AutomationConditionOperandOutputType
    public let description: String?
    public let stringValue: String?
    public let numberValue: Double?
    public let endNumberValue: Double?
    public let unit: String?

    public init(
        type: AutomationConditionOperandOutputType,
        description: String? = nil,
        stringValue: String? = nil,
        numberValue: Double? = nil,
        endNumberValue: Double? = nil,
        unit: String? = nil
    ) {
        self.type = type
        self.description = description
        self.stringValue = stringValue
        self.numberValue = numberValue
        self.endNumberValue = endNumberValue
        self.unit = unit
    }

    public func makeHomeOperand() -> HomeAutomationConditionOperand {
        switch type {
        case .deviceAttribute:
            return .deviceAttribute(
                description: nonEmpty(description) ?? nonEmpty(stringValue) ?? "device attribute",
                deviceID: nil,
                capability: nil,
                attribute: nil
            )
        case .literalString:
            return .literalString(nonEmpty(stringValue) ?? nonEmpty(description) ?? "")
        case .literalNumber:
            return .literalNumber(numberValue ?? 0, unit: nonEmpty(unit))
        case .literalRange:
            return .literalRange(
                start: numberValue ?? 0,
                end: endNumberValue ?? numberValue ?? 0,
                unit: nonEmpty(unit)
            )
        case .locationMode:
            return .locationMode(nonEmpty(stringValue) ?? nonEmpty(description) ?? "")
        case .unsupported:
            return .unsupported(rawValue: nonEmpty(description) ?? nonEmpty(stringValue) ?? "unsupported condition operand")
        }
    }
}

@Generable
public struct AutomationConditionOutput: Sendable, Hashable, Codable {
    public let type: AutomationConditionOutputType
    public let children: [AutomationConditionOutput]
    public let left: AutomationConditionOperandOutput?
    public let operatorName: AutomationComparisonOperatorOutput?
    public let right: AutomationConditionOperandOutput?
    public let triggerPolicy: AutomationConditionTriggerPolicyOutput?

    public init(
        type: AutomationConditionOutputType,
        children: [AutomationConditionOutput] = [],
        left: AutomationConditionOperandOutput? = nil,
        operatorName: AutomationComparisonOperatorOutput? = nil,
        right: AutomationConditionOperandOutput? = nil,
        triggerPolicy: AutomationConditionTriggerPolicyOutput? = nil
    ) {
        self.type = type
        self.children = children
        self.left = left
        self.operatorName = operatorName
        self.right = right
        self.triggerPolicy = triggerPolicy
    }

    public func makeHomeCondition(
        defaultTriggerPolicy: HomeAutomationConditionTriggerPolicy = .never
    ) throws -> HomeAutomationCondition {
        switch type {
        case .and:
            let conditions = try children.map {
                try $0.makeHomeCondition(defaultTriggerPolicy: defaultTriggerPolicy)
            }
            guard !conditions.isEmpty else {
                throw AutomationDraftError.invalidOutput("and condition has no children")
            }
            return .and(conditions)
        case .or:
            let conditions = try children.map {
                try $0.makeHomeCondition(defaultTriggerPolicy: defaultTriggerPolicy)
            }
            guard !conditions.isEmpty else {
                throw AutomationDraftError.invalidOutput("or condition has no children")
            }
            return .or(conditions)
        case .not:
            guard let child = children.first else {
                throw AutomationDraftError.invalidOutput("not condition has no child")
            }
            return .not(try child.makeHomeCondition(defaultTriggerPolicy: defaultTriggerPolicy))
        case .changes:
            guard let child = children.first else {
                throw AutomationDraftError.invalidOutput("changes condition has no child")
            }
            return .changes(try child.makeHomeCondition(defaultTriggerPolicy: defaultTriggerPolicy))
        case .comparison:
            guard let left, let right else {
                throw AutomationDraftError.invalidOutput("comparison condition is missing operands")
            }
            return .comparison(
                HomeAutomationComparisonCondition(
                    left: left.makeHomeOperand(),
                    operatorName: operatorName?.homeOperator ?? .equals,
                    right: right.makeHomeOperand(),
                    triggerPolicy: triggerPolicy?.homePolicy ?? defaultTriggerPolicy
                )
            )
        }
    }
}

@Generable
public struct AutomationTriggerOutput: Sendable, Hashable, Codable {
    public let type: AutomationTriggerOutputType
    public let repeatRule: String?
    public let time: String?
    public let timezoneIdentifier: String?
    public let description: String?
    public let condition: AutomationConditionOutput?

    public init(
        type: AutomationTriggerOutputType,
        repeatRule: String? = nil,
        time: String? = nil,
        timezoneIdentifier: String? = nil,
        description: String? = nil,
        condition: AutomationConditionOutput? = nil
    ) {
        self.type = type
        self.repeatRule = repeatRule
        self.time = time
        self.timezoneIdentifier = timezoneIdentifier
        self.description = description
        self.condition = condition
    }

    public func makeHomeTrigger() throws -> HomeAutomationTrigger {
        switch type {
        case .schedule:
            return .schedule(
                HomeAutomationScheduleTrigger(
                    repeatRule: Self.makeRepeatRule(from: repeatRule),
                    timeOfDay: Self.makeTimeOfDay(from: time),
                    timezoneIdentifier: nonEmpty(timezoneIdentifier)
                )
            )
        case .device:
            guard let condition else {
                throw AutomationDraftError.invalidOutput("device trigger is missing its condition")
            }
            let homeCondition = try condition.makeHomeCondition(defaultTriggerPolicy: .always)
            return .device(
                HomeAutomationDeviceTrigger(
                    description: nonEmpty(description) ?? "device trigger",
                    condition: homeCondition
                )
            )
        }
    }

    private static func makeRepeatRule(from value: String?) -> HomeAutomationRepeatRule {
        let normalized = (value ?? "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.isEmpty || ["everyday", "every day", "daily"].contains(normalized) {
            return .everyDay
        }
        if normalized == "once" {
            return .once
        }
        if normalized == "weekdays" {
            return .daysOfWeek([.monday, .tuesday, .wednesday, .thursday, .friday])
        }
        if normalized == "weekends" {
            return .daysOfWeek([.saturday, .sunday])
        }
        if normalized.hasPrefix("days of week ") || normalized.hasPrefix("daysOfWeek:".lowercased()) {
            let rawDays = normalized
                .replacingOccurrences(of: "days of week ", with: "")
                .replacingOccurrences(of: "daysofweek:", with: "")
            let days = rawDays
                .split { $0 == "," || $0 == " " }
                .compactMap { HomeAutomationWeekday(rawValue: String($0)) }
            return days.isEmpty ? .unsupported(rawValue: normalized) : .daysOfWeek(days)
        }
        if let match = normalized.firstAutomationMatch(of: #"\bevery\s+(\d+)\s+(minute|minutes|hour|hours|day|days)\b"#),
           let interval = Int(match[1]) {
            let unit: HomeAutomationTimeUnit
            switch match[2] {
            case "hour", "hours":
                unit = .hour
            case "day", "days":
                unit = .day
            default:
                unit = .minute
            }
            return .interval(value: interval, unit: unit)
        }

        let days = HomeAutomationWeekday.allCasesInNaturalOrder.filter { day in
            normalized.contains(day.rawValue)
        }
        if !days.isEmpty {
            return .daysOfWeek(days)
        }

        return .unsupported(rawValue: value ?? "unsupported repeat rule")
    }

    private static func makeTimeOfDay(from value: String?) -> HomeAutomationTimeOfDay? {
        guard let raw = nonEmpty(value) else { return nil }
        let normalized = raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let match = normalized.firstAutomationMatch(of: #"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$"#),
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
}

@Generable
public struct AutomationDraftOutput: Sendable, Hashable, Codable {
    public let name: String
    public let trigger: AutomationTriggerOutput?
    public let condition: AutomationConditionOutput?
    public let actionDescriptions: [String]
    public let unsupportedFragments: [String]
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    public let confidence: Double

    public init(
        name: String,
        trigger: AutomationTriggerOutput?,
        condition: AutomationConditionOutput?,
        actionDescriptions: [String],
        unsupportedFragments: [String] = [],
        confidence: Double
    ) {
        self.name = name
        self.trigger = trigger
        self.condition = condition
        self.actionDescriptions = actionDescriptions
        self.unsupportedFragments = unsupportedFragments
        self.confidence = confidence
    }

    public func makeRuleDraft() throws -> HomeAutomationRuleDraft {
        let cleanedActions = actionDescriptions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleanedActions.isEmpty else {
            throw AutomationDraftError.invalidOutput("missing action descriptions")
        }

        return HomeAutomationRuleDraft(
            name: nonEmpty(name) ?? cleanedActions.first ?? "Automation",
            trigger: try trigger?.makeHomeTrigger(),
            condition: try condition?.makeHomeCondition(defaultTriggerPolicy: .never),
            actionDescriptions: cleanedActions,
            confidence: confidence
        )
    }
}

private func nonEmpty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

private extension HomeAutomationWeekday {
    static let allCasesInNaturalOrder: [HomeAutomationWeekday] = [
        .monday,
        .tuesday,
        .wednesday,
        .thursday,
        .friday,
        .saturday,
        .sunday
    ]
}

extension String {
    func firstAutomationMatch(of pattern: String) -> [String]? {
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
