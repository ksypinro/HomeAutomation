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

@Generable
public struct HomeLanguageDetectionResult: Sendable, Hashable, Codable {
    public let languageCode: String
    public let isMixedLanguage: Bool
    public let confidence: Double
    public let unsupportedLanguageLikely: Bool

    public init(
        languageCode: String,
        isMixedLanguage: Bool,
        confidence: Double,
        unsupportedLanguageLikely: Bool
    ) {
        self.languageCode = languageCode
        self.isMixedLanguage = isMixedLanguage
        self.confidence = confidence
        self.unsupportedLanguageLikely = unsupportedLanguageLikely
    }
}

@Generable
public struct HomeDomainClassificationResult: Sendable, Hashable, Codable {
    public let domain: HomeAutomationCommandDomain
    public let confidence: Double

    public init(domain: HomeAutomationCommandDomain, confidence: Double) {
        self.domain = domain
        self.confidence = confidence
    }
}

@Generable
public struct HomeIntentFamilyResult: Sendable, Hashable, Codable {
    public let topFamilies: [HomeAutomationIntentFamily]
    public let confidence: Double

    public init(topFamilies: [HomeAutomationIntentFamily], confidence: Double) {
        self.topFamilies = topFamilies
        self.confidence = confidence
    }
}

@Generable
public struct HomeDeviceTypeResult: Sendable, Hashable, Codable {
    public let deviceTypes: [String]
    public let confidence: Double

    public init(deviceTypes: [String], confidence: Double) {
        self.deviceTypes = deviceTypes
        self.confidence = confidence
    }
}

@Generable
public struct HomeExtractedSlot: Sendable, Hashable, Codable {
    public let name: String
    public let rawValue: String
    public let numericValue: Double?
    public let unit: String?
    public let confidence: Double

    public init(
        name: String,
        rawValue: String,
        numericValue: Double? = nil,
        unit: String? = nil,
        confidence: Double
    ) {
        self.name = name
        self.rawValue = rawValue
        self.numericValue = numericValue
        self.unit = unit
        self.confidence = confidence
    }
}

@Generable
public struct HomeSlotExtractionResult: Sendable, Hashable, Codable {
    public let rooms: [String]
    public let deviceNicknames: [String]
    public let values: [HomeExtractedSlot]
    public let modes: [String]
    public let confidence: Double

    public init(
        rooms: [String],
        deviceNicknames: [String],
        values: [HomeExtractedSlot],
        modes: [String],
        confidence: Double
    ) {
        self.rooms = rooms
        self.deviceNicknames = deviceNicknames
        self.values = values
        self.modes = modes
        self.confidence = confidence
    }
}

@Generable
public struct HomeRiskClassificationResult: Sendable, Hashable, Codable {
    public let riskLevel: HomeAutomationRiskLevel
    public let requiresConfirmation: Bool
    public let reason: String
    public let confidence: Double

    public init(
        riskLevel: HomeAutomationRiskLevel,
        requiresConfirmation: Bool,
        reason: String,
        confidence: Double
    ) {
        self.riskLevel = riskLevel
        self.requiresConfirmation = requiresConfirmation
        self.reason = reason
        self.confidence = confidence
    }
}

public struct HomeResolutionState: Sendable, Hashable, Codable {
    public let rawText: String
    public let language: HomeLanguageDetectionResult
    public let domain: HomeDomainClassificationResult
    public let intent: HomeIntentFamilyResult
    public let deviceType: HomeDeviceTypeResult
    public let slots: HomeSlotExtractionResult
    public let risk: HomeRiskClassificationResult

    public init(
        rawText: String,
        language: HomeLanguageDetectionResult,
        domain: HomeDomainClassificationResult,
        intent: HomeIntentFamilyResult,
        deviceType: HomeDeviceTypeResult,
        slots: HomeSlotExtractionResult,
        risk: HomeRiskClassificationResult
    ) {
        self.rawText = rawText
        self.language = language
        self.domain = domain
        self.intent = intent
        self.deviceType = deviceType
        self.slots = slots
        self.risk = risk
    }
}

public enum HomeCandidateType: Sendable, Hashable, Codable {
    case device
    case group
    case routine
}

public struct HomeCandidateRecord: Identifiable, Sendable, Hashable, Codable {
    public let id: String
    public let type: HomeCandidateType
    public let displayName: String
    public let deviceType: String
    public let room: String?
    public let capabilities: [String]
    public let supportedCommands: [String: [String]]
    public let supportedModes: [String]
    public var currentState: [String: String]
    public let metadata: [String: String]
    public let riskLevel: HomeAutomationRiskLevel

    public init(
        id: String,
        type: HomeCandidateType = .device,
        displayName: String,
        deviceType: String,
        room: String?,
        capabilities: [String],
        supportedCommands: [String: [String]],
        supportedModes: [String] = [],
        currentState: [String: String] = [:],
        metadata: [String: String] = [:],
        riskLevel: HomeAutomationRiskLevel = .low
    ) {
        self.id = id
        self.type = type
        self.displayName = displayName
        self.deviceType = deviceType
        self.room = room
        self.capabilities = capabilities
        self.supportedCommands = supportedCommands
        self.supportedModes = supportedModes
        self.currentState = currentState
        self.metadata = metadata
        self.riskLevel = riskLevel
    }

    public var compactView: HomeCompactCandidateView {
        HomeCompactCandidateView(
            id: id,
            label: displayName,
            room: room,
            deviceType: deviceType,
            shortCapabilities: capabilities
        )
    }
}

public struct HomeCompactCandidateView: Sendable, Hashable, Codable, CustomStringConvertible {
    public let id: String
    public let label: String
    public let room: String?
    public let deviceType: String
    public let shortCapabilities: [String]

    public init(
        id: String,
        label: String,
        room: String?,
        deviceType: String,
        shortCapabilities: [String]
    ) {
        self.id = id
        self.label = label
        self.room = room
        self.deviceType = deviceType
        self.shortCapabilities = shortCapabilities
    }

    public var description: String {
        let roomText = room.map { " room=\($0)" } ?? ""
        return "\(id): \(label) type=\(deviceType)\(roomText) capabilities=\(shortCapabilities.joined(separator: ","))"
    }
}

@Generable
public struct HomeCandidateShardSelection: Sendable, Hashable, Codable {
    public let selectedCandidateIDs: [String]
    public let rejectedCandidateIDs: [String]
    public let confidence: Double
    public let reason: String

    public init(
        selectedCandidateIDs: [String],
        rejectedCandidateIDs: [String],
        confidence: Double,
        reason: String
    ) {
        self.selectedCandidateIDs = selectedCandidateIDs
        self.rejectedCandidateIDs = rejectedCandidateIDs
        self.confidence = confidence
        self.reason = reason
    }
}

@Generable
public struct HomeCandidateAggregationResult: Sendable, Hashable, Codable {
    public let finalCandidateIDs: [String]
    public let needsClarification: Bool
    public let clarificationQuestion: String?
    public let confidence: Double

    public init(
        finalCandidateIDs: [String],
        needsClarification: Bool,
        clarificationQuestion: String? = nil,
        confidence: Double
    ) {
        self.finalCandidateIDs = finalCandidateIDs
        self.needsClarification = needsClarification
        self.clarificationQuestion = clarificationQuestion
        self.confidence = confidence
    }
}

@Generable
public struct HomeResolvedParameter: Sendable, Hashable, Codable {
    public let name: String
    public let value: String?
    public let numericValue: Double?
    public let unit: String?
    public let confidence: Double

    public init(
        name: String,
        value: String? = nil,
        numericValue: Double? = nil,
        unit: String? = nil,
        confidence: Double
    ) {
        self.name = name
        self.value = value
        self.numericValue = numericValue
        self.unit = unit
        self.confidence = confidence
    }
}

@Generable
public struct HomeCommandDraft: Sendable, Hashable, Codable {
    public let intent: HomeAutomationIntent

    @Guide(description: "Selected device ID from the hydrated candidates only.")
    public let targetDeviceID: String?

    @Guide(description: "Selected group or room ID if the command targets a group.")
    public let targetGroupID: String?

    public let capability: String?
    public let command: String?
    public let parameters: [HomeResolvedParameter]
    public let needsClarification: Bool
    public let clarificationQuestion: String?
    public let requiresConfirmation: Bool
    public let confidence: Double

    public init(
        intent: HomeAutomationIntent,
        targetDeviceID: String? = nil,
        targetGroupID: String? = nil,
        capability: String? = nil,
        command: String? = nil,
        parameters: [HomeResolvedParameter] = [],
        needsClarification: Bool,
        clarificationQuestion: String? = nil,
        requiresConfirmation: Bool,
        confidence: Double
    ) {
        self.intent = intent
        self.targetDeviceID = targetDeviceID
        self.targetGroupID = targetGroupID
        self.capability = capability
        self.command = command
        self.parameters = parameters
        self.needsClarification = needsClarification
        self.clarificationQuestion = clarificationQuestion
        self.requiresConfirmation = requiresConfirmation
        self.confidence = confidence
    }
}

public struct HomeAutomationExecutionStep: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public let type: String
    public let deviceID: String
    public let deviceName: String
    public let capability: String
    public let command: String
    public let value: String?
    public let attribute: String?
    public let valueFormula: String?

    public init(
        id: UUID = UUID(),
        type: String,
        deviceID: String,
        deviceName: String,
        capability: String,
        command: String,
        value: String? = nil,
        attribute: String? = nil,
        valueFormula: String? = nil
    ) {
        self.id = id
        self.type = type
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.capability = capability
        self.command = command
        self.value = value
        self.attribute = attribute
        self.valueFormula = valueFormula
    }
}

public struct HomeAutomationExecutionPlan: Sendable, Hashable, Codable {
    public let steps: [HomeAutomationExecutionStep]
    public let requiresConfirmation: Bool

    public init(steps: [HomeAutomationExecutionStep], requiresConfirmation: Bool) {
        self.steps = steps
        self.requiresConfirmation = requiresConfirmation
    }
}

public enum HomeCommandResolution: Sendable, Hashable, Codable {
    case readyToExecute(HomeAutomationExecutionPlan)
    case executed(HomeAutomationExecutionPlan, updatedDevice: HomeCandidateRecord)
    case requiresConfirmation(HomeCommandDraft)
    case needsClarification(String)
    case unsupported(String)

    public var displaySummary: String {
        switch self {
        case .readyToExecute(let plan):
            if plan.steps.allSatisfy({ $0.type == "query" }) {
                return "Resolved \(plan.steps.count) status query step(s)."
            }
            return "Ready to execute \(plan.steps.count) low-risk step(s)."
        case .executed(let plan, let device):
            return "Executed \(plan.steps.count) step(s) on \(device.displayName)."
        case .requiresConfirmation:
            return "This command requires confirmation before execution."
        case .needsClarification(let question):
            return question
        case .unsupported(let reason):
            return reason
        }
    }
}

public struct HomeFinalResolutionInput: Sendable, Hashable, Codable {
    public let rawText: String
    public let resolutionState: HomeResolutionState
    public let hydratedCandidates: [HomeCandidateRecord]
    public let aggregation: HomeCandidateAggregationResult

    public init(
        rawText: String,
        resolutionState: HomeResolutionState,
        hydratedCandidates: [HomeCandidateRecord],
        aggregation: HomeCandidateAggregationResult
    ) {
        self.rawText = rawText
        self.resolutionState = resolutionState
        self.hydratedCandidates = hydratedCandidates
        self.aggregation = aggregation
    }
}
