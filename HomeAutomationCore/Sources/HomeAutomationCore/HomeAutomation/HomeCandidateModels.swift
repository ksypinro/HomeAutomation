import Foundation
import FoundationModels

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
