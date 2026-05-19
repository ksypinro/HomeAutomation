import Foundation
import HomeAutomationCore

public struct AutomationConditionOperandResolutionRecord: Sendable, Hashable, Codable {
    public let id: String
    public let order: Int
    public let path: String
    public let description: String
    public let input: HomeAutomationConditionOperand
    public let output: HomeAutomationConditionOperand

    public init(
        id: String,
        order: Int,
        path: String,
        description: String,
        input: HomeAutomationConditionOperand,
        output: HomeAutomationConditionOperand
    ) {
        self.id = id
        self.order = order
        self.path = path
        self.description = description
        self.input = input
        self.output = output
    }

    public var isResolved: Bool {
        switch output {
        case .deviceAttribute(_, let deviceID, let capability, let attribute):
            return Self.hasText(deviceID) && Self.hasText(capability) && Self.hasText(attribute)
        case .literalString, .literalNumber, .literalRange, .locationMode:
            return true
        case .unsupported:
            return false
        }
    }

    private static func hasText(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

public struct AutomationConditionResolutionOutput: Sendable, Hashable, Codable {
    public let ruleDraft: HomeAutomationRuleDraft
    public let records: [AutomationConditionOperandResolutionRecord]

    public init(
        ruleDraft: HomeAutomationRuleDraft,
        records: [AutomationConditionOperandResolutionRecord]
    ) {
        self.ruleDraft = ruleDraft
        self.records = records
    }
}
