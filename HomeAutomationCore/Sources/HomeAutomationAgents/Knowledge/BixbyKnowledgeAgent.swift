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
    public typealias Output = [KnowledgeSnippet]

    public let id = AgentID.bixbyKnowledge
    public let capabilities: Set<AgentCapability> = [.knowledgeRetrieval]
    public let timeoutNanoseconds: UInt64 = 5_000_000_000
    private let contextRetriever: ContextRetriever?

    public init(contextRetriever: ContextRetriever? = nil) {
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: BixbyKnowledgeInput, context: ResolutionContext) async throws -> [KnowledgeSnippet] {
        let names = input.deviceNames.isEmpty ? ["bedroom light"] : input.deviceNames
        var commands: [(command: HomeBixbyVoiceCommand, deviceName: String, score: Double?)] = []

        if let contextRetriever {
            let chunks = await contextRetriever.retrieve(
                query: ([input.text] + names).joined(separator: " "),
                topK: 5,
                filter: MetadataFilter(source: .bixbyCommand)
            )
            commands.append(contentsOf: chunks.compactMap { scored in
                guard let command = Self.hydrateBixbyCommand(from: scored.chunk) else { return nil }
                return (command, names.first ?? "bedroom light", Double(scored.score))
            })
        }

        for name in names {
            commands.append(contentsOf: HomeBixbyCommandCatalog.commands(matching: input.text, deviceName: name).map {
                ($0, name, nil)
            })
        }

        return AgentRAGSupport.stableUnique(commands) {
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
}
