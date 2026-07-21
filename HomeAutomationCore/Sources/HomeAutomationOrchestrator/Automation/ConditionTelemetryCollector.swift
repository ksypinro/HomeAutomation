import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import OSLog

/// Collects and reports condition-specific telemetry for Phase 0 baseline.
public struct ConditionTelemetryCollector: Sendable {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "ConditionTelemetry")

    public init() {}

    /// Extract condition telemetry metrics from resolved condition results.
    public func collectMetrics(
        from conditionResults: [AutomationConditionClauseResolutionResult],
        tree: AutomationConditionTreeDescriptor?,
        triggerKind: String,
        deviceCount: Int,
        isOnCriticalPath: Bool
    ) -> [ConditionTelemetryMetrics] {
        guard !conditionResults.isEmpty else { return [] }

        let leafCount = conditionResults.count
        let treeNodeCount = treeNodeCount(from: tree) + leafCount
        let treeDepth = treeDepth(from: tree)
        let treeShape = treeShape(from: tree)

        return conditionResults.map { result in
            ConditionTelemetryMetrics(
                leafCount: leafCount,
                treeNodeCount: treeNodeCount,
                treeDepth: treeDepth,
                treeShape: treeShape,
                triggerKind: triggerKind,
                completeness: result.condition != nil ? "complete" : "incomplete",
                confidence: result.confidence,
                residualReasons: "", // populated by caller if needed
                resolutionMode: "unknown", // populated by caller (det/fm/unavailable)
                relevantDeviceCount: deviceCount,
                promptCharacters: 0, // populated by caller
                outputCharacters: 0, // populated by caller
                queueWaitMs: 0, // populated from FM gate
                serviceMs: 0, // populated from FM gate
                totalDurationMs: 0, // computed from timing
                isOnCriticalPath: isOnCriticalPath,
                componentID: result.id
            )
        }
    }

    /// Compute tree node count (and/or/not operators only, not leaves).
    private func treeNodeCount(from tree: AutomationConditionTreeDescriptor?) -> Int {
        guard let tree else { return 0 }
        switch tree {
        case .leaf:
            return 0
        case .and(let children), .or(let children):
            return 1 + children.map { treeNodeCount(from: $0) }.reduce(0, +)
        case .not(let child):
            return 1 + treeNodeCount(from: child)
        }
    }

    /// Compute maximum nesting depth.
    private func treeDepth(from tree: AutomationConditionTreeDescriptor?) -> Int {
        guard let tree else { return 0 }
        switch tree {
        case .leaf:
            return 1
        case .and(let children), .or(let children):
            return 1 + (children.map { treeDepth(from: $0) }.max() ?? 0)
        case .not(let child):
            return 1 + treeDepth(from: child)
        }
    }

    /// Classify tree shape.
    private func treeShape(from tree: AutomationConditionTreeDescriptor?) -> String {
        guard let tree else { return "none" }
        switch tree {
        case .leaf:
            return "leaf"
        case .and:
            return "and"
        case .or:
            return "or"
        case .not:
            return "not"
        }
    }
}
