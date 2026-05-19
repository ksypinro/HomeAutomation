import Foundation
import HomeAutomationCore
import HomeAutomationRAG

public enum AgentRetrievalFallbackBehavior: String, Sendable, Hashable, Codable {
    case skip
    case useCanonicalRegistry
    case retryWithReformulation
    case deterministicOnly
}

/// Agent-owned retrieval policy.
///
/// This keeps RAG behavior explicit at the agent boundary instead of burying
/// source filters, limits, thresholds, and fallback choices inside helper code.
public struct AgentRetrievalStrategy: Sendable, Hashable {
    public let name: String
    public let agentID: AgentID
    public let purpose: String
    public let source: KnowledgeSource?
    public let requiredTags: [String: String]
    public let topK: Int
    public let minScore: Float
    public let ranking: RetrievalStrategy
    public let fallbackBehavior: AgentRetrievalFallbackBehavior

    public init(
        name: String,
        agentID: AgentID,
        purpose: String,
        source: KnowledgeSource? = nil,
        requiredTags: [String: String] = [:],
        topK: Int,
        minScore: Float,
        ranking: RetrievalStrategy,
        fallbackBehavior: AgentRetrievalFallbackBehavior
    ) {
        self.name = name
        self.agentID = agentID
        self.purpose = purpose
        self.source = source
        self.requiredTags = requiredTags
        self.topK = max(1, topK)
        self.minScore = max(0, minScore)
        self.ranking = ranking
        self.fallbackBehavior = fallbackBehavior
    }

    public func makeQuery(
        rawText: String,
        semanticText: String? = nil,
        keywordTerms: [String] = [],
        requiredTagValues: [String: [String]] = [:],
        nluHints: NLURetrievalHints? = nil,
        operation: HomeAutomationOperationKind? = nil,
        automationConcepts: [String] = [],
        conditionOperators: [String] = [],
        repeatHints: [String] = []
    ) -> StructuredRetrievalQuery {
        StructuredRetrievalQuery(
            rawText: rawText,
            semanticText: semanticText,
            keywordTerms: keywordTerms,
            metadataFilter: metadataFilter(requiredTagValues: requiredTagValues),
            nluHints: nluHints,
            operation: operation,
            automationConcepts: automationConcepts,
            conditionOperators: conditionOperators,
            repeatHints: repeatHints,
            strategy: ranking,
            minScore: minScore,
            topK: topK
        )
    }

    public func metadataFilter(requiredTagValues: [String: [String]] = [:]) -> MetadataFilter? {
        guard source != nil || !requiredTags.isEmpty || !requiredTagValues.isEmpty else {
            return nil
        }
        return MetadataFilter(
            source: source,
            requiredTags: requiredTags,
            requiredTagValues: requiredTagValues
        )
    }

    public func reportHints(
        nluHints: NLURetrievalHints? = nil,
        extra: [String: [String]] = [:]
    ) -> [String: [String]] {
        var hints = extra
        hints["strategyName"] = [name]
        hints["fallbackBehavior"] = [fallbackBehavior.rawValue]
        if let source {
            hints["source"] = [source.rawValue]
        }
        if let nluHints {
            if !nluHints.deviceTypes.isEmpty { hints["deviceTypes"] = nluHints.deviceTypes }
            if !nluHints.intentFamilies.isEmpty { hints["intentFamilies"] = nluHints.intentFamilies }
            if !nluHints.rooms.isEmpty { hints["rooms"] = nluHints.rooms }
            if !nluHints.capabilities.isEmpty { hints["capabilities"] = nluHints.capabilities }
        }
        for (key, value) in requiredTags where !value.isEmpty {
            hints["requiredTag.\(key)"] = [value]
        }
        return hints
    }
}

