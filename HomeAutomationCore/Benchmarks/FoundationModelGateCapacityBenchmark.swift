import Foundation
import HomeAutomationCore

/// Lightweight local harness for Phase 7 capacity comparisons.
///
/// Run from `HomeAutomationCore` with:
///
/// ```bash
/// swift run FoundationModelGateCapacityBenchmark
/// ```
///
/// This intentionally uses simulated service work rather than real Foundation
/// Model inference so it can be run in CI/developer environments. Device-level
/// release benchmarking should repeat the same scenarios with actual model
/// calls and record TTFT/accuracy/safety externally.
@main
struct FoundationModelGateCapacityBenchmark {
    struct ScenarioResult {
        let maxConcurrent: Int
        let totalCalls: Int
        let p50QueueWaitMs: Double
        let p95QueueWaitMs: Double
        let p50TotalLatencyMs: Double
        let p95TotalLatencyMs: Double
        let cancellations: Int
        let failures: Int
    }

    static func main() async {
        let scenarios = [1, 2]
        for capacity in scenarios {
            let result = await runScenario(maxConcurrent: capacity)
            print("""
            capacity=\(result.maxConcurrent) calls=\(result.totalCalls) \
            p50_queue_ms=\(String(format: "%.2f", result.p50QueueWaitMs)) \
            p95_queue_ms=\(String(format: "%.2f", result.p95QueueWaitMs)) \
            p50_total_ms=\(String(format: "%.2f", result.p50TotalLatencyMs)) \
            p95_total_ms=\(String(format: "%.2f", result.p95TotalLatencyMs)) \
            cancellations=\(result.cancellations) failures=\(result.failures)
            """)
        }
    }

    private static func runScenario(maxConcurrent: Int) async -> ScenarioResult {
        let gate = FoundationModelGate(maxConcurrent: maxConcurrent)
        let totalCalls = 40
        let queueWaits = LockedArray<Double>()
        let totalLatencies = LockedArray<Double>()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<totalCalls {
                group.addTask {
                    let started = DispatchTime.now().uptimeNanoseconds
                    let priority: FMPriority = index.isMultiple(of: 3) ? .interactive : .pipeline
                    let wait = await gate.admit(priority: priority) * 1_000
                    queueWaits.append(wait)
                    try? await Task.sleep(nanoseconds: UInt64(priority == .interactive ? 8_000_000 : 18_000_000))
                    await gate.release()
                    let ended = DispatchTime.now().uptimeNanoseconds
                    totalLatencies.append(Double(ended - started) / 1_000_000)
                }
            }
        }

        let waits = queueWaits.values.sorted()
        let latencies = totalLatencies.values.sorted()
        return ScenarioResult(
            maxConcurrent: maxConcurrent,
            totalCalls: totalCalls,
            p50QueueWaitMs: percentile(0.50, in: waits),
            p95QueueWaitMs: percentile(0.95, in: waits),
            p50TotalLatencyMs: percentile(0.50, in: latencies),
            p95TotalLatencyMs: percentile(0.95, in: latencies),
            cancellations: 0,
            failures: 0
        )
    }

    private static func percentile(_ p: Double, in values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        guard values.count > 1 else { return values[0] }
        let index = min(values.count - 1, max(0, Int((Double(values.count - 1) * p).rounded())))
        return values[index]
    }
}

private final class LockedArray<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    var values: [Element] {
        lock.withLock { storage }
    }

    func append(_ value: Element) {
        lock.withLock {
            storage.append(value)
        }
    }
}
