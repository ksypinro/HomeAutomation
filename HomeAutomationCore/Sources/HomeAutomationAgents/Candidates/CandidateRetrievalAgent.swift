import Foundation
import HomeAutomationCore
import HomeAutomationRAG
import os

/// Retrieves candidate devices from the mock registry, merging semantic RAG matches
/// and conversation-memory-hinted devices.
public struct CandidateRetrievalAgent: HomeAgent {
    public typealias Input = CandidateRetrievalInput
    public typealias Output = [HomeCandidateRecord]

    public let id = AgentID.candidateRetrieval
    public let capabilities: Set<AgentCapability> = [.candidateRetrieval]
    public let timeoutNanoseconds: UInt64 = 5_000_000_000
    private let retrieve: @Sendable (CandidateRetrievalInput) async throws -> [HomeCandidateRecord]
    private let logger = Logger(subsystem: "HomeAutomation", category: "Agent.CandidateRetrieval")

    public init(retrieve: @escaping @Sendable (CandidateRetrievalInput) async throws -> [HomeCandidateRecord]) {
        self.retrieve = retrieve
    }

    public init(
        registry: MockHomeDeviceRegistry = MockHomeDeviceRegistry(),
        contextRetriever: ContextRetriever? = nil
    ) {
        self.retrieve = { input in
            let existing = await registry.retrieveCandidates(text: input.text, hints: input.state, limit: input.limit)
            let allDevices = await registry.allDevices()
            let memoryDeviceIDs = Set(input.memoryHints.compactMap(\.deviceID))
            let memoryCandidates = allDevices.filter { memoryDeviceIDs.contains($0.id) }
            guard let contextRetriever else {
                return AgentRAGSupport.stableUnique(existing + memoryCandidates) { $0.id }
            }

            let semanticQuery = Self.semanticQuery(from: input)
            let deviceChunks = await contextRetriever.retrieve(
                query: semanticQuery,
                topK: 12,
                filter: MetadataFilter(source: .device)
            )
            let ragDeviceIDs = Set(deviceChunks.compactMap { $0.chunk.metadata["deviceId"] })
            guard !ragDeviceIDs.isEmpty else {
                return AgentRAGSupport.stableUnique(existing + memoryCandidates) { $0.id }
            }

            let ragOnlyCandidates = allDevices.filter { ragDeviceIDs.contains($0.id) }
            return AgentRAGSupport.stableUnique(existing + ragOnlyCandidates + memoryCandidates) { $0.id }
        }
    }

    public func run(_ input: CandidateRetrievalInput, context: ResolutionContext) async throws -> [HomeCandidateRecord] {
        logger.debug("[run] Executing CandidateRetrievalAgent with input limit \(input.limit)")
        return try await retrieve(input)
    }

    private static func semanticQuery(from input: CandidateRetrievalInput) -> String {
        var parts: [String] = [input.text]
        parts.append(contentsOf: input.state.slots.rooms)
        parts.append(contentsOf: input.state.slots.deviceNicknames)
        parts.append(contentsOf: input.state.deviceType.deviceTypes)
        parts.append(contentsOf: input.state.intent.topFamilies.map { String(describing: $0) })
        parts.append(contentsOf: input.memoryHints.compactMap(\.deviceID))
        parts.append(contentsOf: input.memoryHints.compactMap(\.capability))
        return parts.joined(separator: " ")
    }
}
