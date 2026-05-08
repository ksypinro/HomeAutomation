import Foundation
import HomeAutomationCore

/// Immutable snapshot of resolution state. Agents read this value and emit patches.
public struct ResolutionContext: Sendable {
    public let request: CommandRequest
    public var language: HomeLanguageDetectionResult?
    public var domain: HomeDomainClassificationResult?
    public var intent: HomeIntentFamilyResult?
    public var deviceType: HomeDeviceTypeResult?
    public var slots: HomeSlotExtractionResult?
    public var risk: HomeRiskClassificationResult?
    public var resolutionState: HomeResolutionState?
    public var retrievedCandidates: [HomeCandidateRecord]
    public var selectedCandidateIDs: [String]
    public var aggregation: HomeCandidateAggregationResult?
    public var hydratedCandidates: [HomeCandidateRecord]
    public var knowledgeSnippets: [KnowledgeSnippet]
    public var memoryHints: [MemoryHint]
    public var instructionPackage: HomeModelInstructionPackage?
    public var draft: HomeCommandDraft?
    public var executionPlan: HomeAutomationExecutionPlan?
    public var resolution: HomeCommandResolution?
    public var errors: [AgentFailure]
    public var trace: [AgentTraceEntry]

    public init(request: CommandRequest) {
        self.request = request
        self.retrievedCandidates = []
        self.selectedCandidateIDs = []
        self.hydratedCandidates = []
        self.knowledgeSnippets = []
        self.memoryHints = []
        self.errors = []
        self.trace = []
    }
}

/// Input command from the user.
public struct CommandRequest: Sendable {
    public let text: String
    public let executeLowRiskCommands: Bool
    public let timestamp: Date

    public init(text: String, executeLowRiskCommands: Bool) {
        self.text = text
        self.executeLowRiskCommands = executeLowRiskCommands
        self.timestamp = Date()
    }
}

/// Compact knowledge selected by static lookup or RAG.
public struct KnowledgeSnippet: Sendable, Codable, Hashable {
    public let sourceID: String
    public let content: String
    public let score: Double?
    public let metadata: [String: String]

    public init(
        sourceID: String,
        content: String,
        score: Double? = nil,
        metadata: [String: String] = [:]
    ) {
        self.sourceID = sourceID
        self.content = content
        self.score = score
        self.metadata = metadata
    }
}

/// Low-authority hint from conversation memory. Never grants execution authority.
public struct MemoryHint: Sendable, Codable, Hashable {
    public let deviceID: String?
    public let capability: String?
    public let confidence: Double
    public let reason: String

    public init(deviceID: String?, capability: String?, confidence: Double, reason: String) {
        self.deviceID = deviceID
        self.capability = capability
        self.confidence = confidence
        self.reason = reason
    }
}
