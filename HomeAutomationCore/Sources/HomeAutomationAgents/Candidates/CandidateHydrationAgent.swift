import Foundation
import HomeAutomationCore
import os

/// Converts selected candidate IDs into fully hydrated `HomeCandidateRecord` values.
public struct CandidateHydrationAgent: HomeAgent {
    public typealias Input = CandidateHydrationInput
    public typealias Output = [HomeCandidateRecord]

    public let id = AgentID.candidateHydration
    public let capabilities: Set<AgentCapability> = [.candidateHydration]
    public let timeoutNanoseconds: UInt64 = 5_000_000_000
    private let hydrate: @Sendable (CandidateHydrationInput) async throws -> [HomeCandidateRecord]
    private let logger = Logger(subsystem: "HomeAutomation", category: "Agent.CandidateHydration")

    public init(hydrate: @escaping @Sendable (CandidateHydrationInput) async throws -> [HomeCandidateRecord]) {
        self.hydrate = hydrate
    }

    public init(registry: MockHomeDeviceRegistry = MockHomeDeviceRegistry()) {
        self.hydrate = { input in
            let devices = await registry.allDevices()
            let idSet = Set(input.candidateIDs)
            return devices.filter { idSet.contains($0.id) }
        }
    }

    public func run(_ input: CandidateHydrationInput, context: ResolutionContext) async throws -> [HomeCandidateRecord] {
        logger.debug("[run] Executing CandidateHydrationAgent for \(input.candidateIDs.count) candidate IDs")
        return try await hydrate(input)
    }
}
