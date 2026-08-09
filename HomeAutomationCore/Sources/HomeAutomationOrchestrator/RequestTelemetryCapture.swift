import Foundation
import HomeAutomationCore
import OSLog

/// Captures and logs request-level telemetry for Phase 0 baseline.
public struct RequestTelemetryCapture: Sendable {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "RequestTelemetry")

    public init() {}

    /// Capture and log a request telemetry snapshot.
    /// Call this after resolution completes to record end-to-end timing and strategy attribution.
    public func captureAndLog(
        snapshot: RequestTelemetrySnapshot,
        context: HomeAutomationTelemetryContext?
    ) async {
        let payload: [String: String] = [
            "strategy": snapshot.strategy.rawValue,
            "rootRoutingSource": snapshot.rootRoutingSource,
            "selectedArm": snapshot.selectedArm,
            "executingArm": snapshot.executingArm,
            "routerRuleID": snapshot.routerRuleID ?? "unknown",
            "preparationDurationMs": String(format: "%.0f", snapshot.preparationDurationMs),
            "operationExecutionDurationMs": String(format: "%.0f", snapshot.operationExecutionDurationMs),
            "requestToOutcomeDurationMs": String(format: "%.0f", snapshot.requestToOutcomeDurationMs),
            "fmCallCount": String(snapshot.fmCallCount),
            "conditionMetricsCount": String(snapshot.conditionMetrics?.count ?? 0),
        ]

        let logContext = context ?? HomeAutomationTelemetryContext()

        await HomeAutomationTelemetry.shared.log(
            "request.telemetry.captured",
            context: logContext,
            status: .completed,
            payload: TelemetryPayload(values: payload.mapValues { .string($0) })
        )

        logger.info("Request telemetry: strategy=\(snapshot.strategy.rawValue) arm=\(snapshot.executingArm) duration=\(snapshot.requestToOutcomeDurationMs, format: .fixed(precision: 0))ms fm=\(snapshot.fmCallCount)")
    }

    /// Create a request telemetry snapshot from orchestration state.
    /// This is a simplified builder; fuller integration occurs when strategy routing is explicit.
    public static func makeSnapshot(
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
    ) -> RequestTelemetrySnapshot {
        RequestTelemetrySnapshot(
            strategy: strategy,
            rootRoutingSource: rootRoutingSource,
            selectedArm: selectedArm,
            executingArm: executingArm,
            routerRuleID: routerRuleID,
            preparationDurationMs: preparationDurationMs,
            operationExecutionDurationMs: operationExecutionDurationMs,
            requestToOutcomeDurationMs: requestToOutcomeDurationMs,
            conditionMetrics: conditionMetrics,
            fmCallCount: fmCallCount
        )
    }
}
