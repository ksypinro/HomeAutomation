import Foundation
import HomeAutomationCore
import HomeAutomationRAG

/// Detects language and mixed-language state from the user's natural-language command.
///
/// The `LanguageAgent` is one of six NLU agents that run in parallel during the first phase
/// of the orchestrator pipeline. It produces a `HomeLanguageDetectionResult` containing
/// the detected BCP-47 language code, mixed-language flag, and confidence score.
///
/// When Foundation Models are available, the agent delegates to `LanguageAgentWorkerSession`
/// which uses a `LanguageModelSession` for detection. When models are unavailable, it falls back
/// to the deterministic `AgentTextParser` which uses keyword-based multilingual detection.
///
/// RAG enrichment is applied when a `ContextRetriever` is provided, prepending relevant
/// few-shot examples from the generated command dataset to improve detection accuracy.
public struct LanguageAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = HomeLanguageDetectionResult

    public let id = AgentID.language
    public let capabilities: Set<AgentCapability> = [.languageDetection]
    public let timeoutNanoseconds: UInt64 = 10_000_000_000
    private let worker: LanguageAgentWorkerSession
    private let contextRetriever: ContextRetriever?

    public init(
        contextRetriever: ContextRetriever? = nil,
        detect: @escaping @Sendable (String) async throws -> HomeLanguageDetectionResult
    ) {
        self.init(
            worker: LanguageAgentWorkerSession(detect: detect),
            contextRetriever: contextRetriever
        )
    }

    public init(
        worker: LanguageAgentWorkerSession = LanguageAgentWorkerSession(),
        contextRetriever: ContextRetriever? = nil
    ) {
        self.worker = worker
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: String, context: ResolutionContext) async throws -> HomeLanguageDetectionResult {
        let enrichedInput = await AgentRAGSupport.nluInput(input, task: "language detection", contextRetriever: contextRetriever)
        return try await worker.detectLanguage(enrichedInput)
    }
}
