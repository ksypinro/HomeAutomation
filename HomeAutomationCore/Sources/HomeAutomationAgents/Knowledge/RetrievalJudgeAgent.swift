import Foundation
import FoundationModels
import HomeAutomationCore
import HomeAutomationRAG

public struct RetrievalJudgeInput: Sendable, Hashable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct RetrievalJudgeAgent: HomeAgent {
    public typealias Input = RetrievalJudgeInput
    public typealias Output = KnowledgeRetrievalAgentOutput

    public let id = AgentID.retrievalJudge
    public let capabilities: Set<AgentCapability> = [.knowledgeRetrieval]
    public let timeoutNanoseconds: UInt64 = 5_000_000_000

    private let contextRetriever: ContextRetriever?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let maxRetryCount: Int

    public init(
        contextRetriever: ContextRetriever? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        maxRetryCount: Int = 1
    ) {
        self.contextRetriever = contextRetriever
        self.foundationModelAvailability = foundationModelAvailability
        self.maxRetryCount = maxRetryCount
    }

    public func run(_ input: RetrievalJudgeInput, context: ResolutionContext) async throws -> KnowledgeRetrievalAgentOutput {
        let reports = context.retrievalReports
        guard shouldRetry(reports), maxRetryCount > 0 else {
            return KnowledgeRetrievalAgentOutput(snippets: [], reports: [
                judgeReport(
                    query: input.text,
                    strategy: "acceptedFastPath",
                    scores: reports.map(\.maxScore),
                    minScore: 0,
                    retryCount: 0
                )
            ])
        }

        guard foundationModelAvailability(), let contextRetriever else {
            return KnowledgeRetrievalAgentOutput(snippets: [], reports: [
                judgeReport(
                    query: input.text,
                    strategy: "skippedUnavailable",
                    scores: reports.map(\.maxScore),
                    minScore: 0,
                    retryCount: 0
                )
            ])
        }

        let hints = Self.nluHints(from: context)
        let reformulated = QueryReformulator.reformulate(rawText: input.text, hints: hints)
        let sources = Self.sourcesNeedingRetry(from: reports)
        var snippets: [KnowledgeSnippet] = []
        var retryReports: [KnowledgeRetrievalReport] = []

        for source in sources {
            let filter = Self.filter(for: source, hints: hints)
            let query = StructuredRetrievalQuery(
                rawText: input.text,
                semanticText: reformulated,
                keywordTerms: hints.deviceTypes + hints.rooms + hints.capabilities,
                metadataFilter: filter,
                nluHints: hints,
                strategy: .agentic,
                minScore: 0.01,
                topK: 3
            )
            let chunks = await contextRetriever.retrieve(query)
            snippets.append(contentsOf: Self.hydrate(chunks: chunks, source: source))
            retryReports.append(
                KnowledgeRetrievalReport.make(
                    agentID: id,
                    source: source.rawValue,
                    strategy: query.strategy.name,
                    query: reformulated,
                    results: chunks.map { Double($0.score) },
                    minScore: Double(query.minScore),
                    filterHints: Self.filterHints(from: hints),
                    reformulatedQuery: reformulated == input.text ? nil : reformulated,
                    retryCount: 1
                )
            )
        }

        return KnowledgeRetrievalAgentOutput(
            snippets: AgentRAGSupport.stableUnique(snippets) { $0.sourceID },
            reports: retryReports
        )
    }

    private func shouldRetry(_ reports: [KnowledgeRetrievalReport]) -> Bool {
        guard !reports.isEmpty else { return false }
        return reports.contains { $0.returnedCount == 0 || $0.maxScore < $0.minScore || $0.averageScore < 0.01 }
    }

    private func judgeReport(
        query: String,
        strategy: String,
        scores: [Double],
        minScore: Double,
        retryCount: Int
    ) -> KnowledgeRetrievalReport {
        KnowledgeRetrievalReport.make(
            agentID: id,
            source: "retrievalJudge",
            strategy: strategy,
            query: query,
            results: scores,
            minScore: minScore,
            retryCount: retryCount
        )
    }

    private static func sourcesNeedingRetry(from reports: [KnowledgeRetrievalReport]) -> [KnowledgeSource] {
        let lowSources = reports
            .filter { $0.returnedCount == 0 || $0.maxScore < $0.minScore || $0.averageScore < 0.01 }
            .compactMap { KnowledgeSource(rawValue: $0.source) }
        let sources = lowSources.isEmpty ? [.capability, .bixbyCommand, .nlDataset] : lowSources
        return AgentRAGSupport.stableUnique(sources) { $0.rawValue }
    }

    private static func filter(for source: KnowledgeSource, hints: NLURetrievalHints) -> MetadataFilter {
        switch source {
        case .capability, .bixbyCommand:
            return MetadataFilter(
                source: source,
                requiredTagValues: hints.deviceTypes.isEmpty ? [:] : ["relatedDeviceTypes": hints.deviceTypes]
            )
        case .nlDataset:
            return MetadataFilter(
                source: source,
                requiredTagValues: hints.deviceTypes.isEmpty ? [:] : ["deviceType": hints.deviceTypes]
            )
        case .device:
            return MetadataFilter(
                source: source,
                requiredTagValues: hints.deviceTypes.isEmpty ? [:] : ["deviceType": hints.deviceTypes]
            )
        }
    }

    private static func hydrate(chunks: [ScoredChunk], source: KnowledgeSource) -> [KnowledgeSnippet] {
        switch source {
        case .capability:
            return chunks.compactMap { scored in
                guard let id = scored.chunk.metadata["capabilityId"],
                      let definition = HomeCapabilityRegistry.definitions[id] else { return nil }
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
                    score: Double(scored.score),
                    metadata: ["source": "canonicalCapability", "retrievalJudge": "true"]
                )
            }
        case .bixbyCommand:
            return chunks.compactMap { scored in
                guard let command = hydrateBixbyCommand(from: scored.chunk) else { return nil }
                return KnowledgeSnippet(
                    sourceID: command.id,
                    content: "Bixby: \(command.capabilityAction), method: \(command.method), hint: \(command.hint)",
                    score: Double(scored.score),
                    metadata: [
                        "source": "canonicalBixby",
                        "capability": command.capability,
                        "action": command.action,
                        "retrievalJudge": "true"
                    ]
                )
            }
        case .nlDataset:
            let examples = Dictionary(uniqueKeysWithValues: HomeAutomationKnowledgeBase.generatedDatasetCommands().map { ($0.id, $0) })
            return chunks.compactMap { scored in
                guard let id = scored.chunk.metadata["exampleId"],
                      let example = examples[id] else { return nil }
                return KnowledgeSnippet(
                    sourceID: example.id,
                    content: "Example: \(example.text); capability: \(example.capability); command: \(example.command); risk: \(example.riskLevel)",
                    score: Double(scored.score),
                    metadata: [
                        "source": "canonicalCommandDataset",
                        "deviceType": example.deviceType,
                        "capability": example.capability,
                        "command": example.command,
                        "retrievalJudge": "true"
                    ]
                )
            }
        case .device:
            return []
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

    private static func filterHints(from hints: NLURetrievalHints) -> [String: [String]] {
        [
            "deviceTypes": hints.deviceTypes,
            "intentFamilies": hints.intentFamilies,
            "rooms": hints.rooms,
            "capabilities": hints.capabilities
        ].filter { !$0.value.isEmpty }
    }
}
