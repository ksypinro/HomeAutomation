import Foundation
import HomeAutomationCore
import OSLog

public actor OrchestratorMetricsCollector {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "OrchestratorMetricsCollector")
    private var last: OrchestratorMetrics?

    public init() {}

    public func store(_ metrics: OrchestratorMetrics) async {
        var enrichedMetrics = metrics
        if enrichedMetrics.metricsV2 == nil {
            enrichedMetrics.metricsV2 = RunMetricsV2.derive(from: enrichedMetrics)
        }
        last = enrichedMetrics
        logger.info("Outcome: \(enrichedMetrics.outcome)")
        let metricsJSON: String
        if let data = try? JSONEncoder().encode(enrichedMetrics),
           let json = String(data: data, encoding: .utf8) {
            metricsJSON = json
        } else {
            metricsJSON = "<encoding failed>"
        }
        await HomeAutomationTelemetry.shared.log(
            "run.metrics",
            status: "completed",
            payload: [
                "outcome": enrichedMetrics.outcome,
                "metrics": metricsJSON
            ]
        )
    }

    public func lastJSON() -> String? {
        guard let metrics = last,
              let data = try? JSONEncoder().encode(metrics) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func lastMetrics() -> OrchestratorMetrics? {
        last
    }
}
