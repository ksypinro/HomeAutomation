import Foundation
import HomeAutomationCore
import HomeAutomationRAG

/// Classifies whether the user's text belongs to the home-automation domain or another domain.
///
/// The `DomainAgent` produces a `HomeDomainClassificationResult` indicating whether the command
/// is a smart-home request (`.homeAutomation`) or unrelated (`.unsupported`). This classification
/// is critical for early pipeline exit — non-home-automation commands are routed to the
/// `UnsupportedCommandAgent` without consuming further pipeline resources.
///
/// Runs in parallel with the other five NLU agents during the first orchestrator phase.
public struct DomainAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = HomeDomainClassificationResult

    public let id = AgentID.domain
    public let capabilities: Set<AgentCapability> = [.domainClassification]
    public let timeoutNanoseconds: UInt64 = 10_000_000_000
    private let classify: @Sendable (String) async throws -> HomeDomainClassificationResult
    private let contextRetriever: ContextRetriever?

    public init(
        contextRetriever: ContextRetriever? = nil,
        classify: @escaping @Sendable (String) async throws -> HomeDomainClassificationResult
    ) {
        self.classify = classify
        self.contextRetriever = contextRetriever
    }

    public init(
        worker: HomeAgentWorkerSessionSupport = HomeAgentWorkerSessionSupport(),
        contextRetriever: ContextRetriever? = nil
    ) {
        self.classify = worker.classifyDomain
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: String, context: ResolutionContext) async throws -> HomeDomainClassificationResult {
        let enrichedInput = await AgentRAGSupport.nluInput(input, task: "domain classification", contextRetriever: contextRetriever)
        return try await classify(enrichedInput)
    }
}
