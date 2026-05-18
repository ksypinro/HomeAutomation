import Foundation
import HomeAutomationCore
import OSLog

public actor OrchestratorMetricsCollector {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "OrchestratorMetricsCollector")
    private var last: OrchestratorMetrics?

    public init() {}

    public func store(_ metrics: OrchestratorMetrics) async {
        last = metrics
        logger.info("Outcome: \(metrics.outcome)")
        let metricsJSON: String
        if let data = try? JSONEncoder().encode(metrics),
           let json = String(data: data, encoding: .utf8) {
            metricsJSON = json
        } else {
            metricsJSON = "<encoding failed>"
        }
        await HomeAutomationTelemetry.shared.log(
            "run.metrics",
            status: "completed",
            payload: [
                "outcome": metrics.outcome,
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
