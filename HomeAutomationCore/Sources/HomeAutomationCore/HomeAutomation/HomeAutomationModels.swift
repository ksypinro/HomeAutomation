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

@Generable
public struct HomeLanguageDetectionResult: Sendable, Hashable, Codable {
    @Guide(description: "BCP-47-style language code such as en, es, fr, ja, bn, or mixed_bn_en.")
    public let languageCode: String
    public let isMixedLanguage: Bool
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
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
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    public let confidence: Double

    public init(domain: HomeAutomationCommandDomain, confidence: Double) {
        self.domain = domain
        self.confidence = confidence
    }
}

@Generable
public struct HomeIntentFamilyResult: Sendable, Hashable, Codable {
    @Guide(description: "Most likely smart-home intent families, ordered by likelihood.", .maximumCount(3))
    public let topFamilies: [HomeAutomationIntentFamily]
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    public let confidence: Double

    public init(topFamilies: [HomeAutomationIntentFamily], confidence: Double) {
        self.topFamilies = topFamilies
        self.confidence = confidence
    }
}

@Generable
public struct HomeDeviceTypeResult: Sendable, Hashable, Codable {
    @Guide(description: "Likely device types in internal English schema names.", .maximumCount(5))
    public let deviceTypes: [String]
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    public let confidence: Double

    public init(deviceTypes: [String], confidence: Double) {
        self.deviceTypes = deviceTypes
        self.confidence = confidence
    }
}

@Generable
public struct HomeSemanticNLUResult: Sendable, Hashable, Codable {
    public let intent: HomeIntentFamilyResult
    public let deviceType: HomeDeviceTypeResult

    public init(
        intent: HomeIntentFamilyResult,
        deviceType: HomeDeviceTypeResult
    ) {
        self.intent = intent
        self.deviceType = deviceType
    }
}

@Generable
public struct HomeExtractedSlot: Sendable, Hashable, Codable {
    @Guide(description: "Canonical slot name such as value, duration, temperature, mode, room, or device.")
    public let name: String
    @Guide(description: "Exact text or normalized phrase from the user command.")
    public let rawValue: String
    public let numericValue: Double?
    @Guide(description: "Short unit such as percent, degree, minute, hour, celsius, or fahrenheit.")
    public let unit: String?
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
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
    @Guide(description: "Room or location names mentioned by the user.", .maximumCount(5))
    public let rooms: [String]
    @Guide(description: "Device nicknames or labels mentioned by the user.", .maximumCount(5))
    public let deviceNicknames: [String]
    @Guide(description: "Numeric, duration, temperature, color, or other value slots.", .maximumCount(6))
    public let values: [HomeExtractedSlot]
    @Guide(description: "Mode names mentioned by the user.", .maximumCount(5))
    public let modes: [String]
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
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
    @Guide(description: "One concise sentence explaining the risk classification.")
    public let reason: String
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
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
    @Guide(description: "Candidate IDs selected from this shard only.", .maximumCount(3))
    public let selectedCandidateIDs: [String]
    @Guide(description: "Candidate IDs rejected from this shard only.", .maximumCount(20))
    public let rejectedCandidateIDs: [String]
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    public let confidence: Double
    @Guide(description: "One concise sentence explaining the shard choice.")
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
    @Guide(description: "Final candidate IDs selected from provided candidates only.", .maximumCount(5))
    public let finalCandidateIDs: [String]
    public let needsClarification: Bool
    @Guide(description: "One concise user-facing question when clarification is needed.")
    public let clarificationQuestion: String?
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
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
    @Guide(description: "Canonical parameter name such as value, mode, duration, color, attribute, or delta.")
    public let name: String
    @Guide(description: "String parameter value when not numeric.")
    public let value: String?
    public let numericValue: Double?
    @Guide(description: "Short unit such as percent, degree, minute, hour, celsius, or fahrenheit.")
    public let unit: String?
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
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

    @Guide(description: "Capability name from hydrated candidates or canonical registry context only.")
    public let capability: String?
    @Guide(description: "Command name valid for the selected capability only.")
    public let command: String?
    @Guide(description: "Resolved parameters required by the selected command.", .maximumCount(6))
    public let parameters: [HomeResolvedParameter]
    public let needsClarification: Bool
    @Guide(description: "One concise user-facing question when clarification is needed.")
    public let clarificationQuestion: String?
    public let requiresConfirmation: Bool
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
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
    case automationDrafted(HomeAutomationCreationPlan)
    case automationRequiresConfirmation(HomeAutomationCreationPlan)
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
        case .automationDrafted(let plan):
            if plan.backendResponse?.status == .created {
                return "Automation created with \(plan.resolvedActions.count) action(s)."
            }
            if plan.smartThingsRuleJSON != nil {
                return "Automation drafted with \(plan.resolvedActions.count) action(s) and SmartThings JSON."
            }
            return "Automation drafted with \(plan.resolvedActions.count) action(s)."
        case .automationRequiresConfirmation:
            return "This automation requires confirmation before it can be created."
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
    public let capabilityDecision: HomeCapabilityDecision?

    public init(
        rawText: String,
        resolutionState: HomeResolutionState,
        hydratedCandidates: [HomeCandidateRecord],
        aggregation: HomeCandidateAggregationResult,
        capabilityDecision: HomeCapabilityDecision? = nil
    ) {
        self.rawText = rawText
        self.resolutionState = resolutionState
        self.hydratedCandidates = hydratedCandidates
        self.aggregation = aggregation
        self.capabilityDecision = capabilityDecision
    }
}

public struct HomeCapabilityAlternative: Sendable, Hashable, Codable {
    public let capability: String
    public let command: String?
    public let targetDeviceID: String?
    public let confidence: Double
    public let evidence: [String]

    public init(
        capability: String,
        command: String?,
        targetDeviceID: String?,
        confidence: Double,
        evidence: [String]
    ) {
        self.capability = capability
        self.command = command
        self.targetDeviceID = targetDeviceID
        self.confidence = confidence
        self.evidence = evidence
    }
}

public struct HomeCapabilityDecision: Sendable, Hashable, Codable {
    public let selectedCapability: String?
    public let selectedCommand: String?
    public let targetDeviceID: String?
    public let alternatives: [HomeCapabilityAlternative]
    public let evidence: [String]
    public let confidence: Double

    public init(
        selectedCapability: String?,
        selectedCommand: String?,
        targetDeviceID: String?,
        alternatives: [HomeCapabilityAlternative],
        evidence: [String],
        confidence: Double
    ) {
        self.selectedCapability = selectedCapability
        self.selectedCommand = selectedCommand
        self.targetDeviceID = targetDeviceID
        self.alternatives = alternatives
        self.evidence = evidence
        self.confidence = confidence
    }
}

public struct HomeAutomationSubgraphRunSummary: Sendable, Hashable, Codable {
    public let id: String
    public let parentNodeID: String
    public let scopeID: String
    public let graphID: String
    public let goal: String
    public let nodeStatuses: [String: String]
    public let selectedAgents: [String: String]
    public let skippedNodeIDs: [String]
    public let nodeDurations: [String: Double]

    public init(
        id: String,
        parentNodeID: String,
        scopeID: String,
        graphID: String,
        goal: String,
        nodeStatuses: [String: String],
        selectedAgents: [String: String],
        skippedNodeIDs: [String],
        nodeDurations: [String: Double]
    ) {
        self.id = id
        self.parentNodeID = parentNodeID
        self.scopeID = scopeID
        self.graphID = graphID
        self.goal = goal
        self.nodeStatuses = nodeStatuses
        self.selectedAgents = selectedAgents
        self.skippedNodeIDs = skippedNodeIDs
        self.nodeDurations = nodeDurations
    }
}
