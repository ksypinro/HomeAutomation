import Foundation
import OSLog

public actor OrchestratorMetricsCollector {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "OrchestratorMetricsCollector")
    private var last: OrchestratorMetrics?

    public init() {}

    public func store(_ metrics: OrchestratorMetrics) {
        last = metrics
        logger.info("Outcome: \(metrics.outcome)")
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
