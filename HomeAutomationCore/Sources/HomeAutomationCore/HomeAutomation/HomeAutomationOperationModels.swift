import Foundation
import FoundationModels

@Generable
public enum HomeAutomationOperationKind: String, Sendable, Hashable, Codable {
    case executeDeviceCommand
    case automationCreation
    case automationUpdate
    case automationDeletion
    case automationQuery
    case sceneCreation
    case routineExecution
    case unsupported
}

@Generable
public struct HomeOperationDetectionResult: Sendable, Hashable, Codable {
    public let domain: HomeAutomationCommandDomain
    public let operation: HomeAutomationOperationKind
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    public let confidence: Double
    public let reason: String

    public init(
        domain: HomeAutomationCommandDomain,
        operation: HomeAutomationOperationKind,
        confidence: Double,
        reason: String
    ) {
        self.domain = domain
        self.operation = operation
        self.confidence = confidence
        self.reason = reason
    }
}

public struct SmartThingsRuleDocument: Sendable, Hashable, Codable {
    public let name: String
    public let jsonString: String

    public init(name: String, jsonString: String) {
        self.name = name
        self.jsonString = jsonString
    }
}

public enum SmartThingsRuleCompileError: Error, Sendable, Hashable, LocalizedError {
    case unsupportedSchedule(HomeAutomationRepeatRule)
    case unresolvedAction(String)
    case unsupportedTrigger(String)
    case unsupportedCondition(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchedule(let repeatRule):
            return "SmartThings Rules v1 compilation does not support schedule: \(repeatRule.displayString)"
        case .unresolvedAction(let action):
            return "Automation action is unresolved: \(action)"
        case .unsupportedTrigger(let reason):
            return "Unsupported trigger: \(reason)"
        case .unsupportedCondition(let reason):
            return "Unsupported condition: \(reason)"
        }
    }
}
