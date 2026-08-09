import Foundation

/// Condition-specific telemetry for latency and FM attribution.
public struct ConditionTelemetryMetrics: Sendable, Codable {
    /// Leaf-level (terminal clause) count in the condition tree.
    public let leafCount: Int

    /// Total boolean tree node count (leaves + AND/OR/NOT operators).
    public let treeNodeCount: Int

    /// Maximum nesting depth in the condition tree.
    public let treeDepth: Int

    /// Tree shape: "leaf" | "and" | "or" | "not" | "mixed".
    public let treeShape: String

    /// Trigger kind: "schedule" | "device" | "unknown".
    public let triggerKind: String

    /// Deterministic completeness: "complete" | "partial" | "ambiguous" | "unsupported".
    public let completeness: String

    /// Deterministic confidence (0.0-1.0).
    public let confidence: Double

    /// Comma-separated consumer-independent residual reasons (e.g., "targetAmbiguous,capabilityMissing").
    public let residualReasons: String

    /// Resolution mode for this condition batch.
    /// Values: "deterministicAccepted" | "singleFM" | "batchedFM" | "unavailableFallback" | "timedOutFallback" | "clarification".
    public let resolutionMode: String

    /// Relevant device count included in the condition prompt.
    public let relevantDeviceCount: Int

    /// Condition prompt character count.
    public let promptCharacters: Int

    /// Condition output (FM result) character count.
    public let outputCharacters: Int

    /// Queue wait time in milliseconds (time from enqueue to FM lease acquisition).
    public let queueWaitMs: Double

    /// Service time in milliseconds (time from lease acquisition to completion).
    public let serviceMs: Double

    /// Total duration (queue + service) in milliseconds.
    public let totalDurationMs: Double

    /// Whether this condition was on the critical path to assembly/finalization.
    public let isOnCriticalPath: Bool

    /// Condition component ID (for correlation with component fan-out events).
    public let componentID: String?

    public init(
        leafCount: Int,
        treeNodeCount: Int,
        treeDepth: Int,
        treeShape: String,
        triggerKind: String,
        completeness: String,
        confidence: Double,
        residualReasons: String,
        resolutionMode: String,
        relevantDeviceCount: Int,
        promptCharacters: Int,
        outputCharacters: Int,
        queueWaitMs: Double,
        serviceMs: Double,
        totalDurationMs: Double,
        isOnCriticalPath: Bool,
        componentID: String? = nil
    ) {
        self.leafCount = leafCount
        self.treeNodeCount = treeNodeCount
        self.treeDepth = treeDepth
        self.treeShape = treeShape
        self.triggerKind = triggerKind
        self.completeness = completeness
        self.confidence = confidence
        self.residualReasons = residualReasons
        self.resolutionMode = resolutionMode
        self.relevantDeviceCount = relevantDeviceCount
        self.promptCharacters = promptCharacters
        self.outputCharacters = outputCharacters
        self.queueWaitMs = queueWaitMs
        self.serviceMs = serviceMs
        self.totalDurationMs = totalDurationMs
        self.isOnCriticalPath = isOnCriticalPath
        self.componentID = componentID
    }
}

/// Orchestration strategy classification for Phase 0 baseline.
public enum OrchestrationStrategy: String, Sendable, Codable, Hashable {
    case graph
    case graphWithTier1
    case verifierLoop
    case adaptiveStatic
    case adaptiveShadow
}

/// Request-level telemetry for end-to-end timing and strategy attribution.
public struct RequestTelemetrySnapshot: Sendable, Codable {
    /// Orchestration strategy (Graph, Graph+Tier-1, Verifier Loop, Adaptive Static, Adaptive Shadow).
    public let strategy: OrchestrationStrategy

    /// Root-routing source: "normal" | "adaptive" | "prepared".
    public let rootRoutingSource: String

    /// Selected arm in portfolio routing: "graph" | "graphWithTier1" | "verifierLoop" | "unknown".
    public let selectedArm: String

    /// Actually executing arm (may differ in shadow mode).
    public let executingArm: String

    /// Router rule ID for routing decision (for debugging routing decisions).
    public let routerRuleID: String?

    /// Time from request start to routing decision in milliseconds.
    public let preparationDurationMs: Double

    /// Time from routing decision to outcome in milliseconds (actual operation execution).
    public let operationExecutionDurationMs: Double

    /// Total time from request start to outcome in milliseconds.
    public let requestToOutcomeDurationMs: Double

    /// Condition-specific metrics, if automation has conditions.
    public let conditionMetrics: [ConditionTelemetryMetrics]?

    /// Total FM calls attributed to this request.
    public let fmCallCount: Int

    public init(
        strategy: OrchestrationStrategy,
        rootRoutingSource: String,
        selectedArm: String,
        executingArm: String,
        routerRuleID: String? = nil,
        preparationDurationMs: Double,
        operationExecutionDurationMs: Double,
        requestToOutcomeDurationMs: Double,
        conditionMetrics: [ConditionTelemetryMetrics]? = nil,
        fmCallCount: Int
    ) {
        self.strategy = strategy
        self.rootRoutingSource = rootRoutingSource
        self.selectedArm = selectedArm
        self.executingArm = executingArm
        self.routerRuleID = routerRuleID
        self.preparationDurationMs = preparationDurationMs
        self.operationExecutionDurationMs = operationExecutionDurationMs
        self.requestToOutcomeDurationMs = requestToOutcomeDurationMs
        self.conditionMetrics = conditionMetrics
        self.fmCallCount = fmCallCount
    }
}
