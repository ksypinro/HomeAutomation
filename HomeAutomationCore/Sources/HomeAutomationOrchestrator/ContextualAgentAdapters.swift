import Foundation
import FoundationModels
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationRAG
import OSLog

internal struct AgentContextInputError: LocalizedError, Sendable {
    let agentID: AgentID
    let message: String

    var errorDescription: String? {
        "\(agentID.rawValue): \(message)"
    }
}

internal final class AgentRegistryBox: @unchecked Sendable {
    var registry: AgentRegistry?
}

/// A generic wrapper that adapts an agent's specific input/output types into the unified `ResolutionContext`.
///
/// This allows the orchestrator to treat all agents uniformly (`AnyHomeAgent`), while still
/// allowing individual agents to define strict input dependencies and typed outputs.
public struct ContextualHomeAgent<Agent: HomeAgent>: AnyHomeAgent {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "ContextualHomeAgent")
    public let agent: Agent
    private let makeInput: @Sendable (ResolutionContext) throws -> Agent.Input
    private let makePatch: @Sendable (Agent.Output, ResolutionContext) -> ResolutionContextPatch

    public var id: AgentID { agent.id }
    public var capabilities: Set<AgentCapability> { agent.capabilities }
    public var manifest: AgentManifest { agent.manifest }
    public var timeoutNanoseconds: UInt64 { agent.timeoutNanoseconds }

    public init(
        agent: Agent,
        makeInput: @escaping @Sendable (ResolutionContext) throws -> Agent.Input,
        makePatch: @escaping @Sendable (Agent.Output, ResolutionContext) -> ResolutionContextPatch
    ) {
        self.agent = agent
        self.makeInput = makeInput
        self.makePatch = makePatch
    }

    /// Executes the underlying agent by converting the context into its required input,
    /// and then mapping its output back to a `ResolutionContextPatch`.
    public func run(context: ResolutionContext) async -> AgentRunResult {
        let startedAt = Date()
        do {
            logger.debug("Generating input for agent: \(self.id.rawValue, privacy: .public)")
            let input = try makeInput(context)
            await HomeAutomationTelemetry.shared.logAgentInput(
                String(describing: input),
                inputType: String(reflecting: Agent.Input.self)
            )
            
            logger.debug("Running agent: \(self.id.rawValue, privacy: .public)")
            let output = try await agent.run(input, context: context)
            let evaluationPayload = Self.evaluationPayload(for: output)
            await HomeAutomationTelemetry.shared.logAgentOutput(
                String(describing: output),
                outputType: String(reflecting: Agent.Output.self),
                durationMs: Date().timeIntervalSince(startedAt) * 1_000
            )
            if !evaluationPayload.isEmpty {
                await HomeAutomationTelemetry.shared.log(
                    "agent.evaluationOutput",
                    status: "completed",
                    durationMs: Date().timeIntervalSince(startedAt) * 1_000,
                    payload: evaluationPayload
                )
            }
            
            let patch = makePatch(output, context)
            await HomeAutomationTelemetry.shared.log(
                "agent.patch",
                payload: Self.patchEvaluationPayload(for: patch).merging(
                    ["patch": String(describing: patch)],
                    uniquingKeysWith: { current, _ in current }
                )
            )
            logger.debug("Agent \(self.id.rawValue, privacy: .public) produced patch successfully.")
            return .success(patch)
        } catch {
            await HomeAutomationTelemetry.shared.log(
                "agent.failed",
                status: "failed",
                durationMs: Date().timeIntervalSince(startedAt) * 1_000,
                payload: [
                    "error": error.localizedDescription
                ]
            )
            logger.error("Agent \(self.id.rawValue, privacy: .public) failed with error: \(error.localizedDescription, privacy: .public)")
            return .terminalFailure(
                AgentFailure(
                    agentID: id,
                    reason: error.localizedDescription,
                    isRetryable: false
                )
            )
        }
    }
}
