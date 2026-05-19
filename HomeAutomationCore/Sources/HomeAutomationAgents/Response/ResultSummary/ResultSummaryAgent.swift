import Foundation
import HomeAutomationCore

/// Formats final result summaries from `HomeCommandResolution` into user-facing text.
///
/// The `ResultSummaryAgent` converts the resolved command outcome into a human-readable
/// summary string. It uses `HomeCommandResolution.displaySummary` to produce text
/// appropriate for the UI result panel.
public struct ResultSummaryAgent: HomeAgent {
    public typealias Input = HomeCommandResolution
    public typealias Output = String

    public let id = AgentID.resultSummary
    public let capabilities: Set<AgentCapability> = [.resultSummary]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000

    public init() {}

    public func run(_ input: HomeCommandResolution, context: ResolutionContext) async throws -> String {
        input.displaySummary
    }
}
