import Foundation
import HomeAutomationCore
import HomeAutomationRAG

/// Extracts normalized device-type hints from the user's command text.
///
/// The redesigned `DeviceTypeAgent` uses Foundation Models with a Tool-based approach.
/// The FM session is given access to `AvailableDeviceTypesTool`, which returns all valid
/// device type identifiers with rich descriptions. This lets the model look up the catalog
/// rather than relying on fragile keyword matching.
///
/// Device types use stable internal English identifiers regardless of the input language.
///
/// Runs in parallel with the other five NLU agents during the first orchestrator phase.
public struct DeviceTypeAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = HomeDeviceTypeResult

    public let id = AgentID.deviceType
    public let capabilities: Set<AgentCapability> = [.deviceTypeExtraction]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let worker: DeviceTypeAgentWorkerSession
    private let contextRetriever: ContextRetriever?

    public init(
        contextRetriever: ContextRetriever? = nil,
        classify: @escaping @Sendable (String) async throws -> HomeDeviceTypeResult
    ) {
        self.init(
            worker: DeviceTypeAgentWorkerSession(classify: classify),
            contextRetriever: contextRetriever
        )
    }

    public init(
        worker: DeviceTypeAgentWorkerSession = DeviceTypeAgentWorkerSession(),
        contextRetriever: ContextRetriever? = nil
    ) {
        self.worker = worker
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: String, context: ResolutionContext) async throws -> HomeDeviceTypeResult {
        let enrichedInput = await AgentRAGSupport.nluInput(input, task: "device type extraction", contextRetriever: contextRetriever)
        return try await worker.classifyDeviceType(enrichedInput)
    }
}
