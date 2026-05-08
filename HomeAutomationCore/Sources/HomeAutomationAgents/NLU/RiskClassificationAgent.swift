import Foundation
import HomeAutomationCore
import HomeAutomationRAG

/// Produces an initial risk estimate for the user's smart-home command.
///
/// The `RiskClassificationAgent` classifies the command into one of four risk levels:
/// - **`.low`**: Lights, simple status queries, harmless brightness changes
/// - **`.medium`**: Temperature changes, appliance operations
/// - **`.high`**: Unlocking, opening entry points, disabling cameras, starting ovens,
///   or changing security state
/// - **`.critical`**: Security bypasses or unsafe automation
///
/// This initial risk estimate influences downstream safety behavior but is not the final
/// word — the `SafetyValidationAgent` and `ConfirmationPolicyAgent` perform authoritative
/// risk-based decisions using canonical `HomeRiskPolicy` and `HomeCapabilityRegistry` data.
///
/// Runs in parallel with the other five NLU agents during the first orchestrator phase.
public struct RiskClassificationAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = HomeRiskClassificationResult

    public let id = AgentID.riskClassification
    public let capabilities: Set<AgentCapability> = [.riskClassification]
    public let timeoutNanoseconds: UInt64 = 10_000_000_000
    private let classify: @Sendable (String) async throws -> HomeRiskClassificationResult
    private let contextRetriever: ContextRetriever?

    public init(
        contextRetriever: ContextRetriever? = nil,
        classify: @escaping @Sendable (String) async throws -> HomeRiskClassificationResult
    ) {
        self.classify = classify
        self.contextRetriever = contextRetriever
    }

    public init(
        worker: HomeAgentWorkerSessionSupport = HomeAgentWorkerSessionSupport(),
        contextRetriever: ContextRetriever? = nil
    ) {
        self.classify = worker.classifyRisk
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: String, context: ResolutionContext) async throws -> HomeRiskClassificationResult {
        let enrichedInput = await AgentRAGSupport.nluInput(input, task: "risk classification", contextRetriever: contextRetriever)
        return try await classify(enrichedInput)
    }
}
