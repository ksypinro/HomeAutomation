import Foundation
import HomeAutomationCore
import HomeAutomationRAG

/// Identifies broad intent families from the user's smart-home command.
///
/// The `IntentFamilyAgent` classifies commands into families such as `.power`, `.temperature`,
/// `.brightness`, `.media`, `.lockUnlock`, `.routine`, `.statusQuery`, and others. These
/// families drive downstream routing decisions including:
/// - Which tools are provided to the draft generation model
/// - Which capabilities are prioritized during candidate ranking
/// - Which safety policies apply during validation
///
/// Runs in parallel with the other five NLU agents during the first orchestrator phase.
public struct IntentFamilyAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = HomeIntentFamilyResult

    public let id = AgentID.intentFamily
    public let capabilities: Set<AgentCapability> = [.intentClassification]
    public let timeoutNanoseconds: UInt64 = 10_000_000_000
    private let classify: @Sendable (String) async throws -> HomeIntentFamilyResult
    private let contextRetriever: ContextRetriever?

    public init(
        contextRetriever: ContextRetriever? = nil,
        classify: @escaping @Sendable (String) async throws -> HomeIntentFamilyResult
    ) {
        self.classify = classify
        self.contextRetriever = contextRetriever
    }

    public init(
        worker: HomeAgentWorkerSessionSupport = HomeAgentWorkerSessionSupport(),
        contextRetriever: ContextRetriever? = nil
    ) {
        self.classify = worker.classifyIntentFamily
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: String, context: ResolutionContext) async throws -> HomeIntentFamilyResult {
        let enrichedInput = await AgentRAGSupport.nluInput(input, task: "intent family classification", contextRetriever: contextRetriever)
        return try await classify(enrichedInput)
    }
}
