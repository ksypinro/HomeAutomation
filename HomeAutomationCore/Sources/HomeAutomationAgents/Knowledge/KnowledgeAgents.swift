import Foundation
import HomeAutomationCore
import HomeAutomationRAG

public struct BixbyKnowledgeInput: Sendable, Hashable {
    public let text: String
    public let deviceNames: [String]

    public init(text: String, deviceNames: [String] = ["bedroom light"]) {
        self.text = text
        self.deviceNames = deviceNames
    }
}

public struct CommandExampleInput: Sendable, Hashable {
    public let text: String
    public let limit: Int

    public init(text: String, limit: Int = 5) {
        self.text = text
        self.limit = limit
    }
}

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

public struct CommandExampleAgent: HomeAgent {
    public typealias Input = CommandExampleInput
    public typealias Output = [KnowledgeSnippet]

    public let id = AgentID.commandExample
    public let capabilities: Set<AgentCapability> = [.knowledgeRetrieval]
    public let timeoutNanoseconds: UInt64 = 5_000_000_000
    private let contextRetriever: ContextRetriever?

    public init(contextRetriever: ContextRetriever? = nil) {
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: CommandExampleInput, context: ResolutionContext) async throws -> [KnowledgeSnippet] {
        let examples = HomeAutomationKnowledgeBase.generatedDatasetCommands()
        let examplesByID = Dictionary(uniqueKeysWithValues: examples.map { ($0.id, $0) })
        var ranked: [(example: HomeGeneratedCommandExample, score: Double?)] = []

        if let contextRetriever {
            let chunks = await contextRetriever.retrieve(
                query: input.text,
                topK: input.limit,
                filter: MetadataFilter(source: .nlDataset)
            )
            ranked.append(contentsOf: chunks.compactMap { scored in
                guard let id = scored.chunk.metadata["exampleId"],
                      let example = examplesByID[id] else {
                    return nil
                }
                return (example, Double(scored.score))
            })
        }

        ranked.append(contentsOf: Self.staticRankedExamples(input: input, examples: examples))

        return AgentRAGSupport.stableUnique(ranked) { $0.example.id }
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
}
