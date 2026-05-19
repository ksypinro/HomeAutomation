import Foundation
import HomeAutomationCore
import HomeAutomationRAG

/// Retrieves relevant capability facts using RAG, then hydrates canonical definitions
/// from `HomeCapabilityRegistry`.
///
/// The `CapabilityKnowledgeAgent` serves as the bridge between the RAG retrieval layer
/// and the canonical capability catalog. It first uses semantic retrieval to find
/// capability chunks relevant to the user's command, then hydrates each match against
/// `HomeCapabilityRegistry.definitions` to produce `KnowledgeSnippet` values containing
/// authoritative capability data (commands, attributes, enum values, risk levels).
///
/// This ensures that RAG-selected context is always validated against the source-of-truth
/// registry before being passed to downstream agents like `InstructionComposerAgent`.
public struct CapabilityKnowledgeAgent: HomeAgent {
    public typealias Input = [String]
    public typealias Output = KnowledgeRetrievalAgentOutput

    public let id = AgentID.capabilityKnowledge
    public let capabilities: Set<AgentCapability> = [.knowledgeRetrieval]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    public static let retrievalStrategy = AgentRetrievalStrategy(
        name: "capability.hybrid.deviceTypeFiltered",
        agentID: .capabilityKnowledge,
        purpose: "Retrieve capability chunks that match the user's NLU hints, then hydrate canonical capability definitions.",
        source: .capability,
        topK: 5,
        minScore: 0.01,
        ranking: .hybrid(alpha: 0.6),
        fallbackBehavior: .useCanonicalRegistry
    )
    private let contextRetriever: ContextRetriever?

    public init(contextRetriever: ContextRetriever? = nil) {
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: [String], context: ResolutionContext) async throws -> KnowledgeRetrievalAgentOutput {
        var scoredIDs: [(id: String, score: Double?)] = input.map { ($0, nil) }
        var reports: [KnowledgeRetrievalReport] = []

        if let contextRetriever {
            let hints = Self.nluHints(from: context, capabilityHints: input)
            let query = input.isEmpty ? context.request.text : ([context.request.text] + input).joined(separator: " ")
            let structuredQuery = Self.retrievalStrategy.makeQuery(
                rawText: context.request.text,
                semanticText: query,
                keywordTerms: hints.capabilities + hints.deviceTypes + hints.rooms,
                requiredTagValues: hints.deviceTypes.isEmpty ? [:] : ["relatedDeviceTypes": hints.deviceTypes],
                nluHints: hints,
                operation: .executeDeviceCommand
            )
            let chunks = await contextRetriever.retrieve(structuredQuery)
            scoredIDs.append(contentsOf: chunks.compactMap { scored in
                guard let id = scored.chunk.metadata["capabilityId"] else { return nil }
                return (id, Double(scored.score))
            })
            reports.append(
                KnowledgeRetrievalReport.make(
                    agentID: id,
                    source: KnowledgeSource.capability.rawValue,
                    strategy: structuredQuery.strategy.name,
                    query: query,
                    results: chunks.map { Double($0.score) },
                    minScore: Double(structuredQuery.minScore),
                    sourceIDs: chunks.map { $0.chunk.id },
                    filterHints: Self.retrievalStrategy.reportHints(nluHints: hints)
                )
            )
        }

        let snippets = AgentRAGSupport.stableUnique(scoredIDs) { $0.id }.compactMap { item -> KnowledgeSnippet? in
            let (id, score) = item
            guard let definition = HomeCapabilityRegistry.definitions[id] else { return nil }
            return KnowledgeSnippet(
                sourceID: id,
                content: [
                    "Capability: \(definition.id)",
                    "displayName: \(definition.displayName)",
                    "commands: \(definition.commands.joined(separator: ","))",
                    "attributes: \(definition.attributeNames.joined(separator: ","))",
                    "enumValues: \(definition.enumValues.joined(separator: ","))",
                    "risk: \(definition.riskLevel)"
                ].joined(separator: "; "),
                score: score,
                metadata: ["source": "canonicalCapability"]
            )
        }
        return KnowledgeRetrievalAgentOutput(snippets: snippets, reports: reports)
    }

    private static func nluHints(from context: ResolutionContext, capabilityHints: [String]) -> NLURetrievalHints {
        let families = context.intent?.topFamilies ?? context.resolutionState?.intent.topFamilies ?? []
        let deviceTypes = context.deviceType?.deviceTypes ?? context.resolutionState?.deviceType.deviceTypes ?? []
        let rooms = context.slots?.rooms ?? context.resolutionState?.slots.rooms ?? []
        let capabilities = IntentCapabilityMap.capabilities(for: families) + capabilityHints
        return NLURetrievalHints(
            deviceTypes: deviceTypes,
            intentFamilies: families.map { String(describing: $0) },
            rooms: rooms,
            capabilities: Self.stableUnique(capabilities)
        )
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !value.isEmpty && !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
