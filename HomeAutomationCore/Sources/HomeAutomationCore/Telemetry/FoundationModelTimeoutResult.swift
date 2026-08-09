import Foundation

/// Typed result of a foundation model call with timeout awareness.
public enum FoundationModelTimeoutResult<Value: Sendable>: Sendable {
    case success(Value, serviceDurationMs: Double)
    case admissionTimeout
    case serviceTimeout
    case cancelled
}

/// Configuration for foundation model call timeouts.
public struct FoundationModelTimeoutConfiguration: Sendable {
    /// Queue admission deadline: max time waiting for a lease.
    public let admissionDeadlineMs: Double
    /// Service timeout: max time after lease acquired to complete.
    public let serviceTimeoutMs: Double

    public init(
        admissionDeadlineMs: Double = 3000,
        serviceTimeoutMs: Double = 8000
    ) {
        self.admissionDeadlineMs = admissionDeadlineMs
        self.serviceTimeoutMs = serviceTimeoutMs
    }

    public static let `default` = FoundationModelTimeoutConfiguration()
}
