import Foundation
import FoundationModels

@Generable
public enum HomeAutomationCommandDomain: Sendable, Hashable, Codable {
    case homeAutomation
    case appNavigation
    case generalQuestion
    case unsupported
}

@Generable
public enum HomeAutomationIntentFamily: Sendable, Hashable, Codable {
    case createAutomation
    case power
    case temperature
    case brightness
    case media
    case applianceCycle
    case lockUnlock
    case openClose
    case routine
    case statusQuery
    case maintenanceQuery
    case unsupported
}

@Generable
public enum HomeAutomationRiskLevel: Sendable, Hashable, Codable {
    case low
    case medium
    case high
    case critical
}

@Generable
public enum HomeAutomationIntent: Sendable, Hashable, Codable {
    case turnOn
    case turnOff
    case setValue
    case increaseValue
    case decreaseValue
    case getStatus
    case start
    case stop
    case pause
    case resume
    case open
    case close
    case lock
    case unlock
    case runRoutine
    case unsupported
}

public enum HomeCandidateType: Sendable, Hashable, Codable {
    case device
    case group
    case routine
}
