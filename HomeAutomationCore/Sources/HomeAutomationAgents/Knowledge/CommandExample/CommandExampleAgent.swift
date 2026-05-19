import Foundation
import HomeAutomationCore
import HomeAutomationRAG

/// Retrieves generated command examples similar to the user's command for few-shot context.
///
/// The `CommandExampleAgent` combines RAG-based semantic retrieval with deterministic
/// token-overlap scoring to find the most relevant examples from the generated
/// natural-language command dataset. These examples provide few-shot context that improves
/// the accuracy of downstream draft generation.
///
/// The agent uses structural scoring that considers device type, capability, command,
/// and room matches in addition to raw token overlap, ensuring that semantically relevant
/// examples are prioritized even when surface-level text similarity is low.
public struct CommandExampleAgent: HomeAgent {
    public typealias Input = CommandExampleInput
    public typealias Output = KnowledgeRetrievalAgentOutput

    public let id = AgentID.commandExample
    public let capabilities: Set<AgentCapability> = [.knowledgeRetrieval]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    public static func retrievalStrategy(limit: Int) -> AgentRetrievalStrategy {
        AgentRetrievalStrategy(
            name: "commandExample.semantic.deviceTypeFiltered",
            agentID: .commandExample,
            purpose: "Retrieve similar generated command examples for few-shot grounding, then validate against the generated command corpus.",
            source: .nlDataset,
            topK: limit,
            minScore: 0.01,
            ranking: .semanticOnly,
            fallbackBehavior: .useCanonicalRegistry
        )
    }
    private let contextRetriever: ContextRetriever?

    public init(contextRetriever: ContextRetriever? = nil) {
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: CommandExampleInput, context: ResolutionContext) async throws -> KnowledgeRetrievalAgentOutput {
        let examples = HomeAutomationKnowledgeBase.generatedDatasetCommands()
        let examplesByID = Dictionary(uniqueKeysWithValues: examples.map { ($0.id, $0) })
        var ranked: [(example: HomeGeneratedCommandExample, score: Double?)] = []
        var reports: [KnowledgeRetrievalReport] = []

        if let contextRetriever {
            let hints = Self.nluHints(from: context)
            let strategy = Self.retrievalStrategy(limit: input.limit)
            let structuredQuery = strategy.makeQuery(
                rawText: input.text,
                semanticText: input.text,
                keywordTerms: hints.deviceTypes + hints.rooms + hints.capabilities,
                requiredTagValues: hints.deviceTypes.isEmpty ? [:] : ["deviceType": hints.deviceTypes],
                nluHints: hints,
                operation: .executeDeviceCommand
            )
            let chunks = await contextRetriever.retrieve(structuredQuery)
            ranked.append(contentsOf: chunks.compactMap { scored in
                guard let id = scored.chunk.metadata["exampleId"],
                      let example = examplesByID[id] else {
                    return nil
                }
                return (example, Double(scored.score))
            })
            reports.append(
                KnowledgeRetrievalReport.make(
                    agentID: id,
                    source: KnowledgeSource.nlDataset.rawValue,
                    strategy: structuredQuery.strategy.name,
                    query: input.text,
                    results: chunks.map { Double($0.score) },
                    minScore: Double(structuredQuery.minScore),
                    sourceIDs: chunks.map { $0.chunk.id },
                    filterHints: strategy.reportHints(nluHints: hints)
                )
            )
        }

        ranked.append(contentsOf: Self.staticRankedExamples(input: input, examples: examples))

        let snippets = AgentRAGSupport.stableUnique(ranked) { $0.example.id }
            .prefix(max(1, input.limit))
            .map { example, score in
                KnowledgeSnippet(
                    sourceID: example.id,
                    content: "Example: \(example.text); capability: \(example.capability); command: \(example.command); risk: \(example.riskLevel)",
                    score: score,
                    metadata: [
                        "source": "canonicalCommandDataset",
                        "language": example.language,
                        "deviceType": example.deviceType,
                        "capability": example.capability,
                        "command": example.command
                    ]
                )
            }
        return KnowledgeRetrievalAgentOutput(snippets: Array(snippets), reports: reports)
    }

    private static func staticRankedExamples(
        input: CommandExampleInput,
        examples: [HomeGeneratedCommandExample]
    ) -> [(example: HomeGeneratedCommandExample, score: Double?)] {
        let queryTokens = input.text.agentTokenSet
        return examples
            .map { example -> (HomeGeneratedCommandExample, Int) in
                let tokens = example.text.agentTokenSet
                let structuralScore = [
                    example.deviceType,
                    example.capability,
                    example.command,
                    example.room
                ]
                    .map(\.agentNormalizedHomeTokenString)
                    .filter { input.text.agentNormalizedHomeTokenString.contains($0) }
                    .count * 3
                return (example, queryTokens.intersection(tokens).count + structuralScore)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.id < rhs.0.id
                }
                return lhs.1 > rhs.1
            }
            .prefix(max(1, input.limit))
            .map { ($0.0, Double($0.1)) }
    }

    private static func nluHints(from context: ResolutionContext) -> NLURetrievalHints {
        let families = context.intent?.topFamilies ?? context.resolutionState?.intent.topFamilies ?? []
        let deviceTypes = context.deviceType?.deviceTypes ?? context.resolutionState?.deviceType.deviceTypes ?? []
        let slots = context.slots ?? context.resolutionState?.slots
        return NLURetrievalHints(
            deviceTypes: deviceTypes,
            intentFamilies: families.map { String(describing: $0) },
            rooms: slots?.rooms ?? [],
            capabilities: IntentCapabilityMap.capabilities(for: families)
        )
    }

}
