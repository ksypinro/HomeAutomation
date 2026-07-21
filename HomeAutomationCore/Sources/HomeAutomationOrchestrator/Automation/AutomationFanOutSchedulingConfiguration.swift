import Foundation
import HomeAutomationCore

/// Configuration for automation component fan-out scheduling.
/// Defines order of operations and concurrency caps for trigger/condition/action resolution.
public struct AutomationFanOutSchedulingConfiguration: Sendable {
    /// Maximum concurrent condition resolution operations per automation.
    public let maxConcurrentConditions: Int
    /// Maximum concurrent action resolution operations per automation (Graph pipelines).
    public let maxConcurrentGraphActions: Int
    /// Maximum concurrent action resolution for Tier-1 mini-pipelines.
    public let maxConcurrentTier1Actions: Int
    /// Global FM gate concurrency (shared across all automations).
    public let globalFMGateConcurrency: Int

    /// Execution order:
    /// 1. Trigger (1 operation, fastest)
    /// 2. Conditions (residuals batched, interactive priority)
    /// 3. Actions (under per-kind caps, pipeline priority for nested graphs)
    ///
    /// This ordering ensures conditions run early while FM gate has capacity,
    /// reducing queue contention with action pipelines.
    public let executionOrder: [ComponentKind] = [.trigger, .condition, .action]

    public enum ComponentKind: String, Sendable {
        case trigger
        case condition
        case action
    }

    public init(
        maxConcurrentConditions: Int = 1,
        maxConcurrentGraphActions: Int = 2,
        maxConcurrentTier1Actions: Int = 4,
        globalFMGateConcurrency: Int = 6
    ) {
        self.maxConcurrentConditions = maxConcurrentConditions
        self.maxConcurrentGraphActions = maxConcurrentGraphActions
        self.maxConcurrentTier1Actions = maxConcurrentTier1Actions
        self.globalFMGateConcurrency = globalFMGateConcurrency
    }

    public static let `default` = AutomationFanOutSchedulingConfiguration()
}

/// Guidance for FM call deadline class based on component type.
public enum FoundationModelComponentDeadlineClass: String, Sendable {
    /// Condition resolution and verifier loop calls: interactive deadline (reserved slot).
    case interactive
    /// Nested Graph action subgraph FM calls: pipeline deadline (best-effort).
    case pipeline
}

extension FoundationModelComponentDeadlineClass {
    /// Map to FM admission deadline class for request metadata.
    public func admissionDeadlineClass() -> FMAdmissionDeadlineClass {
        switch self {
        case .interactive:
            return .interactive
        case .pipeline:
            return .pipeline
        }
    }
}
