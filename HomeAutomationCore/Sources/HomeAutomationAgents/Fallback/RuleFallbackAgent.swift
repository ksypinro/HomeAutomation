import Foundation
import HomeAutomationCore

/// Deterministic rule-based resolver using `AgentTextParser` + `AgentBixbyFallbackMapper`.
/// Used when Foundation Models are unavailable.
public struct RuleFallbackAgent: HomeAgent {
    public typealias Input = RuleFallbackInput
    public typealias Output = HomeAutomationResolverResult

    public let id = AgentID.ruleFallback
    public let capabilities: Set<AgentCapability> = [.ruleFallback]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let resolve: @Sendable (RuleFallbackInput) async throws -> HomeAutomationResolverResult

    public init(resolve: @escaping @Sendable (RuleFallbackInput) async throws -> HomeAutomationResolverResult) {
        self.resolve = resolve
    }

    public init(resolver: AgentRuleBasedResolver = AgentRuleBasedResolver()) {
        self.resolve = { input in
            try await resolver.resolve(
                input.text,
                executeLowRiskCommands: input.executeLowRiskCommands,
                memoryHints: input.memoryHints
            )
        }
    }

    public func run(_ input: RuleFallbackInput, context: ResolutionContext) async throws -> HomeAutomationResolverResult {
        try await resolve(input)
    }
}
