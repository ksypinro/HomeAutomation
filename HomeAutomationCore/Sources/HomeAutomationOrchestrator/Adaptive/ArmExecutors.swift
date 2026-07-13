import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public enum PortfolioArmExecutionFallbackReason: String, Sendable, Codable, Hashable {
    case none
    case selectedArmNotEligible
    case missingVerifierLoopExecutor
    case missingTier1Registry
    case nonExecutableArm
}

public struct PortfolioArmExecutionPlan: Sendable, Codable, Hashable {
    public let selectedArm: FoundationModelCallArm
    public let executingArm: FoundationModelCallArm
    public let fallbackReason: PortfolioArmExecutionFallbackReason

    public init(
        selectedArm: FoundationModelCallArm,
        executingArm: FoundationModelCallArm,
        fallbackReason: PortfolioArmExecutionFallbackReason = .none
    ) {
        self.selectedArm = selectedArm
        self.executingArm = executingArm
        self.fallbackReason = fallbackReason
    }
}

public enum PortfolioArmExecutionOutput: Sendable {
    case graph(GraphArmExecutionOutput)
    case verifierLoop(VerifierLoopArmExecutionOutput)
}

public struct GraphArmExecutionOutput: Sendable {
    public let kind: GraphArmExecutionKind
    public let result: HomeAutomationResolverResult
    public let graphRun: GraphRunMetrics?
    public let fallbackUsed: Bool

    public init(
        kind: GraphArmExecutionKind,
        result: HomeAutomationResolverResult,
        graphRun: GraphRunMetrics?,
        fallbackUsed: Bool = false
    ) {
        self.kind = kind
        self.result = result
        self.graphRun = graphRun
        self.fallbackUsed = fallbackUsed
    }
}

public enum GraphArmExecutionKind: String, Sendable, Codable, Hashable {
    case directCommand
    case automationCreation
    case unsupported
}

public enum VerifierLoopArmExecutionOutput: Sendable {
    case finalized(HomeAutomationResolverResult, receipt: ResolutionFinalizationReceipt?)
    case nonActionable(HomeAutomationResolverResult)
    case escalated(DraftEnvelope, reason: EscalationReason, chain: [FoundationModelEscalationStep])
}

public protocol PortfolioArmExecuting: Sendable {
    var arm: FoundationModelCallArm { get }
}

public struct GraphArmExecutor: PortfolioArmExecuting {
    public let arm: FoundationModelCallArm

    public init(arm: FoundationModelCallArm = .graph) {
        self.arm = arm
    }

    public func executeDirectCommand(
        _ body: () async -> GraphArmExecutionOutput
    ) async -> GraphArmExecutionOutput {
        await body()
    }

    public func executeAutomationCreation(
        _ body: () async -> GraphArmExecutionOutput
    ) async -> GraphArmExecutionOutput {
        await body()
    }

    public func executeUnsupported(
        _ body: () async -> GraphArmExecutionOutput
    ) async -> GraphArmExecutionOutput {
        await body()
    }

    public func output(
        for kind: GraphArmExecutionKind,
        result: HomeAutomationResolverResult,
        graphRun: GraphRunMetrics?,
        fallbackUsed: Bool = false
    ) -> GraphArmExecutionOutput {
        GraphArmExecutionOutput(
            kind: kind,
            result: result,
            graphRun: graphRun,
            fallbackUsed: fallbackUsed
        )
    }
}

public struct VerifierLoopArmExecutor: PortfolioArmExecuting {
    public let arm: FoundationModelCallArm = .verifierLoop

    public init() {}

    public func execute(
        _ body: () async -> VerifierLoopArmExecutionOutput
    ) async -> VerifierLoopArmExecutionOutput {
        await body()
    }

    public func finalized(
        _ result: HomeAutomationResolverResult,
        receipt: ResolutionFinalizationReceipt?
    ) -> VerifierLoopArmExecutionOutput {
        .finalized(result, receipt: receipt)
    }

    public func nonActionable(
        _ result: HomeAutomationResolverResult
    ) -> VerifierLoopArmExecutionOutput {
        .nonActionable(result)
    }

    public func escalated(
        _ envelope: DraftEnvelope,
        reason: EscalationReason,
        chain: [FoundationModelEscalationStep]
    ) -> VerifierLoopArmExecutionOutput {
        .escalated(envelope, reason: reason, chain: chain)
    }
}
