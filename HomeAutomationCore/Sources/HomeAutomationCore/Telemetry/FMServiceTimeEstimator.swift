import Foundation

public struct FMServiceTimeEstimatorKey: Sendable, Codable, Hashable {
    public let agentID: String
    public let jobKind: FoundationModelJobKind
    public let priority: FMPriority

    public init(agentID: String, jobKind: FoundationModelJobKind, priority: FMPriority) {
        self.agentID = agentID
        self.jobKind = jobKind
        self.priority = priority
    }
}

public struct FMServiceTimeEstimate: Sendable, Codable, Hashable {
    public let p50Ms: Double
    public let p75Ms: Double
    public let p90Ms: Double
    public let sampleCount: Int
    public let usedFallback: Bool

    public init(p50Ms: Double, p75Ms: Double, p90Ms: Double, sampleCount: Int, usedFallback: Bool) {
        self.p50Ms = p50Ms
        self.p75Ms = p75Ms
        self.p90Ms = p90Ms
        self.sampleCount = sampleCount
        self.usedFallback = usedFallback
    }
}

public actor FMServiceTimeEstimator {
    public static let shared = FMServiceTimeEstimator()

    private let maxSamplesPerKey: Int
    private let fallbackMs: Double
    private var samplesByKey: [FMServiceTimeEstimatorKey: [Double]] = [:]

    public init(maxSamplesPerKey: Int = 256, fallbackMs: Double = 250) {
        self.maxSamplesPerKey = max(8, maxSamplesPerKey)
        self.fallbackMs = max(1, fallbackMs)
    }

    public func recordServiceTime(milliseconds: Double, key: FMServiceTimeEstimatorKey) {
        guard milliseconds.isFinite, milliseconds > 0 else { return }
        var samples = samplesByKey[key, default: []]
        samples.append(milliseconds)
        if samples.count > maxSamplesPerKey {
            samples.removeFirst(samples.count - maxSamplesPerKey)
        }
        samplesByKey[key] = samples
    }

    public func estimate(for key: FMServiceTimeEstimatorKey) -> FMServiceTimeEstimate {
        guard let samples = samplesByKey[key], !samples.isEmpty else {
            return FMServiceTimeEstimate(
                p50Ms: fallbackMs,
                p75Ms: fallbackMs,
                p90Ms: fallbackMs,
                sampleCount: 0,
                usedFallback: true
            )
        }
        let sorted = samples.sorted()
        return FMServiceTimeEstimate(
            p50Ms: percentile(0.50, in: sorted),
            p75Ms: percentile(0.75, in: sorted),
            p90Ms: percentile(0.90, in: sorted),
            sampleCount: sorted.count,
            usedFallback: false
        )
    }

    private func percentile(_ p: Double, in sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return fallbackMs }
        guard sorted.count > 1 else { return sorted[0] }
        let clamped = min(max(p, 0), 1)
        let position = clamped * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        if lower == upper { return sorted[lower] }
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }
}
