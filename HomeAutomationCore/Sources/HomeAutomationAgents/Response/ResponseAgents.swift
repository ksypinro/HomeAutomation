import Foundation
import HomeAutomationCore

public struct ClarificationAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = HomeCommandResolution

    public let id = AgentID.clarification
    public let capabilities: Set<AgentCapability> = [.clarification]
    public let timeoutNanoseconds: UInt64 = 1_000_000_000

    public init() {}

    public func run(_ input: String, context: ResolutionContext) async throws -> HomeCommandResolution {
        .needsClarification(input)
    }
}

public struct ResultSummaryAgent: HomeAgent {
    public typealias Input = HomeCommandResolution
    public typealias Output = String

    public let id = AgentID.resultSummary
    public let capabilities: Set<AgentCapability> = [.resultSummary]
    public let timeoutNanoseconds: UInt64 = 1_000_000_000

    public init() {}

    public func run(_ input: HomeCommandResolution, context: ResolutionContext) async throws -> String {
        input.displaySummary
    }
}
