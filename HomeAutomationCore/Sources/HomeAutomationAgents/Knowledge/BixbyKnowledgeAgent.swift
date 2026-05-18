import Foundation
import HomeAutomationCore
import HomeAutomationRAG

/// Retrieves and hydrates relevant Bixby voice-command snippets for the user's command.
///
/// The `BixbyKnowledgeAgent` combines RAG-based semantic retrieval of Bixby command chunks
/// with deterministic catalog matching from `HomeBixbyCommandCatalog`. It produces
/// `KnowledgeSnippet` values containing Bixby capability-action pairs, methods, and hints
/// that enrich downstream instruction composition and fallback mapping.
///
/// The agent uses stable deduplication to merge RAG-retrieved and catalog-matched commands,
/// ensuring no duplicate snippets reach the instruction composer.
public struct BixbyKnowledgeAgent: HomeAgent {
    public typealias Input = BixbyKnowledgeInput
    public typealias Output = KnowledgeRetrievalAgentOutput

    public let id = AgentID.bixbyKnowledge
    public let capabilities: Set<AgentCapability> = [.knowledgeRetrieval]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let contextRetriever: ContextRetriever?

    public init(contextRetriever: ContextRetriever? = nil) {
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: BixbyKnowledgeInput, context: ResolutionContext) async throws -> KnowledgeRetrievalAgentOutput {
        let names = input.deviceNames.isEmpty ? ["bedroom light"] : input.deviceNames
        var commands: [(command: HomeBixbyVoiceCommand, deviceName: String, score: Double?)] = []
        var reports: [KnowledgeRetrievalReport] = []

        if let contextRetriever {
            let hints = Self.nluHints(from: context)
            let query = ([input.text] + names + hints.deviceTypes + hints.capabilities).joined(separator: " ")
            let filter = MetadataFilter(
                source: .bixbyCommand,
                requiredTagValues: hints.deviceTypes.isEmpty ? [:] : ["relatedDeviceTypes": hints.deviceTypes]
            )
            let structuredQuery = StructuredRetrievalQuery(
                rawText: input.text,
                semanticText: query,
                keywordTerms: names + hints.deviceTypes + hints.capabilities,
                metadataFilter: filter,
                nluHints: hints,
                strategy: .hybrid(alpha: 0.55),
                minScore: 0.01,
                topK: 5
            )
            let chunks = await contextRetriever.retrieve(structuredQuery)
            commands.append(contentsOf: chunks.compactMap { scored in
                guard let command = Self.hydrateBixbyCommand(from: scored.chunk) else { return nil }
                return (command, names.first ?? "bedroom light", Double(scored.score))
            })
            reports.append(
                KnowledgeRetrievalReport.make(
                    agentID: id,
                    source: KnowledgeSource.bixbyCommand.rawValue,
                    strategy: structuredQuery.strategy.name,
                    query: query,
                    results: chunks.map { Double($0.score) },
                    minScore: Double(structuredQuery.minScore),
                    filterHints: Self.filterHints(from: hints)
                )
            )
        }

        for name in names {
            commands.append(contentsOf: HomeBixbyCommandCatalog.commands(matching: input.text, deviceName: name).map {
                ($0, name, nil)
            })
        }

        let snippets = AgentRAGSupport.stableUnique(commands) {
            "\($0.command.id)|\($0.deviceName)"
        }
        .map { command, deviceName, score in
            KnowledgeSnippet(
                sourceID: command.id,
                content: "Bixby: \(command.capabilityAction), method: \(command.method), hint: \(command.hint)",
                score: score,
                metadata: [
                    "source": "canonicalBixby",
                    "capability": command.capability,
                    "action": command.action,
                    "deviceName": deviceName
                ]
            )
        }
        return KnowledgeRetrievalAgentOutput(snippets: snippets, reports: reports)
    }

    private static func hydrateBixbyCommand(from chunk: DocumentChunk) -> HomeBixbyVoiceCommand? {
        guard let capability = chunk.metadata["capability"],
              let action = chunk.metadata["action"],
              let method = chunk.metadata["method"] else {
            return nil
        }

        return HomeBixbyCommandCatalog.commands.first {
            $0.capability == capability &&
                $0.action == action &&
                $0.method == method
        }
    }

    private static func nluHints(from context: ResolutionContext) -> NLURetrievalHints {
        let families = context.intent?.topFamilies ?? context.resolutionState?.intent.topFamilies ?? []
        let deviceTypes = context.deviceType?.deviceTypes ?? context.resolutionState?.deviceType.deviceTypes ?? []
        let rooms = context.slots?.rooms ?? context.resolutionState?.slots.rooms ?? []
        return NLURetrievalHints(
            deviceTypes: deviceTypes,
            intentFamilies: families.map { String(describing: $0) },
            rooms: rooms,
            capabilities: IntentCapabilityMap.capabilities(for: families)
        )
    }

    private static func filterHints(from hints: NLURetrievalHints) -> [String: [String]] {
        [
            "deviceTypes": hints.deviceTypes,
            "intentFamilies": hints.intentFamilies,
            "rooms": hints.rooms,
            "capabilities": hints.capabilities
        ].filter { !$0.value.isEmpty }
    }
}
