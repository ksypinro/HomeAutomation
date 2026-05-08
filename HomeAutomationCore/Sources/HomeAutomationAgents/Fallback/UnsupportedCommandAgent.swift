import Foundation
import HomeAutomationCore

/// Produces a safe `.unsupported` resolution when no agent can resolve the command.
public struct UnsupportedCommandAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = HomeCommandResolution

    public let id = AgentID.unsupportedCommand
    public let capabilities: Set<AgentCapability> = [.unsupported]
    public let timeoutNanoseconds: UInt64 = 1_000_000_000
    private let reasonBuilder: @Sendable (String) -> String

    public init(reasonBuilder: @escaping @Sendable (String) -> String = { _ in "This command is not supported." }) {
        self.reasonBuilder = reasonBuilder
    }

    public func run(_ input: String, context: ResolutionContext) async throws -> HomeCommandResolution {
        .unsupported(reasonBuilder(input))
    }
}
