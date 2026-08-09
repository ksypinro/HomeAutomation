import Foundation
import FoundationModels
import HomeAutomationCore
import HomeAutomationOrchestrator

/// Helper for Phase 0 harness to map orchestration mode/configuration to strategy.
public struct ConditionalLatencyHarnessSupport: Sendable {
    public init() {}

    /// Determine OrchestrationStrategy from mode and portfolio configuration.
    /// Used by harness to attribute results.
    public func strategyForMode(
        _ mode: OrchestrationMode,
        portfolioRolloutMode: PortfolioRolloutMode?
    ) -> OrchestrationStrategy {
        switch mode {
        case .graph:
            return .graph
        case .verifierLoop:
            return .verifierLoop
        case .adaptivePortfolio:
            switch portfolioRolloutMode {
            case .activeStatic:
                return .adaptiveStatic
            case .shadowStatic:
                return .adaptiveShadow
            case .disabled:
                return .graph
            case nil:
                // Fallback if rollout mode not specified
                return .adaptiveStatic
            case .activeLearned, .shadowLearned:
                // Phase 0 focuses on static routing
                return .adaptiveStatic
            @unknown default:
                return .adaptiveStatic
            }
        }
    }

    /// Aggregate condition telemetry from fan-out events.
    /// Collects all condition-specific metrics emitted during component resolution.
    public func aggregateConditionMetrics(
        from fanOutTelemetry: [String: String]?
    ) -> ConditionTelemetryMetrics? {
        guard let telemetry = fanOutTelemetry else { return nil }

        let leafCount = Int(telemetry["conditionLeafCount"] ?? "0") ?? 0
        let treeNodeCount = Int(telemetry["conditionTreeNodeCount"] ?? "0") ?? 0
        let treeDepth = Int(telemetry["conditionTreeDepth"] ?? "0") ?? 0
        let treeShape = telemetry["conditionTreeShape"] ?? "none"
        let completeness = telemetry["conditionCompleteness"] ?? "unknown"
        let confidence = Double(telemetry["conditionConfidence"] ?? "0") ?? 0

        guard leafCount > 0 else { return nil }

        return ConditionTelemetryMetrics(
            leafCount: leafCount,
            treeNodeCount: treeNodeCount,
            treeDepth: treeDepth,
            treeShape: treeShape,
            triggerKind: telemetry["triggerKind"] ?? "schedule",
            completeness: completeness,
            confidence: confidence,
            residualReasons: "",
            resolutionMode: "unknown",
            relevantDeviceCount: 0,
            promptCharacters: 0,
            outputCharacters: 0,
            queueWaitMs: 0,
            serviceMs: 0,
            totalDurationMs: 0,
            isOnCriticalPath: true
        )
    }

    /// Validate model availability for live evaluation.
    /// Returns true only if the foundation model is available.
    public func isModelAvailableForLiveEvaluation() -> Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Create a paired test case runner for base + conditioned commands.
    /// Returns a tuple of (baseCommand, conditionedCommand) from the corpus.
    public func getPairedCase(id: String) -> (base: String, conditioned: String)? {
        guard let case_ = ConditionalLatencyV1Corpus.cases.first(where: { $0.id == id }) else {
            return nil
        }
        return (base: case_.baseCommand, conditioned: case_.conditionedCommand)
    }
}
