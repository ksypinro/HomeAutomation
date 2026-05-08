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
    public typealias Output = [KnowledgeSnippet]

    public let id = AgentID.capabilityKnowledge
    public let capabilities: Set<AgentCapability> = [.knowledgeRetrieval]
    public let timeoutNanoseconds: UInt64 = 5_000_000_000
    private let contextRetriever: ContextRetriever?

    public init(contextRetriever: ContextRetriever? = nil) {
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: [String], context: ResolutionContext) async throws -> [KnowledgeSnippet] {
        var scoredIDs: [(id: String, score: Double?)] = input.map { ($0, nil) }

        if let contextRetriever {
            let query = input.isEmpty ? context.request.text : input.joined(separator: " ")
            let chunks = await contextRetriever.retrieve(
                query: query,
                topK: 5,
                filter: MetadataFilter(source: .capability)
            )
            scoredIDs.append(contentsOf: chunks.compactMap { scored in
                guard let id = scored.chunk.metadata["capabilityId"] else { return nil }
                return (id, Double(scored.score))
            })
        }

        return AgentRAGSupport.stableUnique(scoredIDs) { $0.id }.compactMap { id, score in
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
    }
}
