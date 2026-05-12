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
    public var retrievalReports: [KnowledgeRetrievalReport]
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
        self.retrievalReports = []
        self.memoryHints = []
        self.errors = []
        self.trace = []
    }
}

public struct KnowledgeRetrievalReport: Sendable, Codable, Hashable {
    public let agentID: String
    public let source: String
    public let strategy: String
    public let query: String
    public let returnedCount: Int
    public let acceptedCount: Int
    public let averageScore: Double
    public let maxScore: Double
    public let minScore: Double
    public let filterHints: [String: [String]]
    public let reformulatedQuery: String?
    public let retryCount: Int

    public init(
        agentID: String,
        source: String,
        strategy: String,
        query: String,
        returnedCount: Int,
        acceptedCount: Int,
        averageScore: Double,
        maxScore: Double,
        minScore: Double,
        filterHints: [String: [String]] = [:],
        reformulatedQuery: String? = nil,
        retryCount: Int = 0
    ) {
        self.agentID = agentID
        self.source = source
        self.strategy = strategy
        self.query = query
        self.returnedCount = returnedCount
        self.acceptedCount = acceptedCount
        self.averageScore = averageScore
        self.maxScore = maxScore
        self.minScore = minScore
        self.filterHints = filterHints
        self.reformulatedQuery = reformulatedQuery
        self.retryCount = retryCount
    }

    public var isLowConfidence: Bool {
        returnedCount == 0 || maxScore < minScore
    }

    public static func make(
        agentID: AgentID,
        source: String,
        strategy: String,
        query: String,
        results: [Double],
        minScore: Double,
        filterHints: [String: [String]] = [:],
        reformulatedQuery: String? = nil,
        retryCount: Int = 0
    ) -> KnowledgeRetrievalReport {
        let average = results.isEmpty ? 0 : results.reduce(0, +) / Double(results.count)
        return KnowledgeRetrievalReport(
            agentID: agentID.rawValue,
            source: source,
            strategy: strategy,
            query: query,
            returnedCount: results.count,
            acceptedCount: results.filter { $0 >= minScore }.count,
            averageScore: average,
            maxScore: results.max() ?? 0,
            minScore: minScore,
            filterHints: filterHints,
            reformulatedQuery: reformulatedQuery,
            retryCount: retryCount
        )
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
