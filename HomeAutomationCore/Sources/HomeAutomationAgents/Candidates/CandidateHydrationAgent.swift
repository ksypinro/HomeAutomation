import Foundation
import HomeAutomationCore

/// Converts selected candidate IDs into fully hydrated `HomeCandidateRecord` values.
public struct CandidateHydrationAgent: HomeAgent {
    public typealias Input = CandidateHydrationInput
    public typealias Output = [HomeCandidateRecord]

    public let id = AgentID.candidateHydration
    public let capabilities: Set<AgentCapability> = [.candidateHydration]
    public let timeoutNanoseconds: UInt64 = 5_000_000_000
    private let hydrate: @Sendable (CandidateHydrationInput) async throws -> [HomeCandidateRecord]

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
        try await hydrate(input)
    }
}
