import Foundation
import HomeAutomationCore
import HomeAutomationRAG

/// Extracts normalized device-type hints from the user's command text.
///
/// The `DeviceTypeAgent` identifies device types mentioned in the command such as `light`,
/// `airConditioner`, `thermostat`, `lock`, `tv`, `speaker`, and others. These hints are used
/// by `CandidateRetrievalAgent` and `CandidateRankingAgent` to narrow the candidate search
/// space and improve ranking accuracy.
///
/// Device types use stable internal English identifiers regardless of the input language.
/// The agent uses the expanded cross-client catalog identifiers from
/// `HomeAutomationKnowledgeBase` when Foundation Models are available.
///
/// Runs in parallel with the other five NLU agents during the first orchestrator phase.
public struct DeviceTypeAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = HomeDeviceTypeResult

    public let id = AgentID.deviceType
    public let capabilities: Set<AgentCapability> = [.deviceTypeExtraction]
    public let timeoutNanoseconds: UInt64 = 10_000_000_000
    private let classify: @Sendable (String) async throws -> HomeDeviceTypeResult
    private let contextRetriever: ContextRetriever?

    public init(
        contextRetriever: ContextRetriever? = nil,
        classify: @escaping @Sendable (String) async throws -> HomeDeviceTypeResult
    ) {
        self.classify = classify
        self.contextRetriever = contextRetriever
    }

    public init(
        worker: HomeAgentWorkerSessionSupport = HomeAgentWorkerSessionSupport(),
        contextRetriever: ContextRetriever? = nil
    ) {
        self.classify = worker.classifyDeviceType
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: String, context: ResolutionContext) async throws -> HomeDeviceTypeResult {
        let enrichedInput = await AgentRAGSupport.nluInput(input, task: "device type extraction", contextRetriever: contextRetriever)
        return try await classify(enrichedInput)
    }
}
