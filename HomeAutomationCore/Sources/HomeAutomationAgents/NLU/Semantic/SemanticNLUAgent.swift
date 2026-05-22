import Foundation
import HomeAutomationCore
import HomeAutomationRAG

/// Fuses broad intent-family classification and canonical device-type extraction.
public struct SemanticNLUAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = HomeSemanticNLUResult

    public let id = AgentID.semanticNLU
    public let capabilities: Set<AgentCapability> = [.intentClassification, .deviceTypeExtraction]
    public let timeoutNanoseconds: UInt64 = 560_000_000_000
    private let worker: SemanticNLUWorkerSession
    private let contextRetriever: ContextRetriever?

    public init(
        contextRetriever: ContextRetriever? = nil,
        classify: @escaping @Sendable (String) async throws -> HomeSemanticNLUResult
    ) {
        self.init(
            worker: SemanticNLUWorkerSession(classify: classify),
            contextRetriever: contextRetriever
        )
    }

    public init(
        worker: SemanticNLUWorkerSession = SemanticNLUWorkerSession(),
        contextRetriever: ContextRetriever? = nil
    ) {
        self.worker = worker
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: String, context: ResolutionContext) async throws -> HomeSemanticNLUResult {
        let enrichedInput = await AgentRAGSupport.nluInput(
            input,
            task: "semantic NLU intent and device type classification",
            contextRetriever: contextRetriever
        )
        return try await worker.classifySemanticNLU(enrichedInput)
    }
}
