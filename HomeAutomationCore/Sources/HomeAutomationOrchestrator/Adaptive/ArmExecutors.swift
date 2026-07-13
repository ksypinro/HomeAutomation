import Foundation
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

public protocol PortfolioArmExecuting: Sendable {
    var arm: FoundationModelCallArm { get }
}

public struct GraphArmExecutor: PortfolioArmExecuting {
    public let arm: FoundationModelCallArm

    public init(arm: FoundationModelCallArm = .graph) {
        self.arm = arm
    }
}

public struct VerifierLoopArmExecutor: PortfolioArmExecuting {
    public let arm: FoundationModelCallArm = .verifierLoop

    public init() {}
}
