import Foundation
import HomeAutomationCore

/// Produces user-facing clarification responses when the command target or intent is ambiguous.
///
/// The `ClarificationAgent` converts an ambiguity question string into a
/// `.needsClarification` resolution. It is invoked when `CandidateRankingAgent`
/// determines that multiple candidates are equally plausible and the user needs
/// to specify which device or action they intended.
public struct ClarificationAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = HomeCommandResolution

    public let id = AgentID.clarification
    public let capabilities: Set<AgentCapability> = [.clarification]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000

    public init() {}

    public func run(_ input: String, context: ResolutionContext) async throws -> HomeCommandResolution {
        .needsClarification(input)
    }
}
