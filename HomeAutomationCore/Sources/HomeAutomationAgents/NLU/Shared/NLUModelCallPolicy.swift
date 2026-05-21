import Foundation
import HomeAutomationCore

public enum NLUWorkerTask: String, Sendable, Hashable, Codable {
    case semanticNLU
    case slotExtraction
    case riskClassification
    case operationDetection
}

/// Controls when Foundation Model calls are made vs. relying on deterministic results.
public enum NLUModelCallMode: String, Sendable, Hashable, Codable {
    /// Current legacy behavior: skip model when deterministic confidence exceeds threshold.
    case thresholdGated
    /// Always call model when available; provide deterministic result as hint when confident.
    case modelFirstWithHint
    /// Always call model when available; do not provide deterministic hint.
    case alwaysModel
}

public struct NLUModelCallPolicy: Sendable {
    public let mode: NLUModelCallMode
    public let semanticNLUThreshold: Double
    public let slotExtractionThreshold: Double
    public let riskThreshold: Double
    public let operationDetectionThreshold: Double

    public init(
        mode: NLUModelCallMode = .modelFirstWithHint,
        semanticNLUThreshold: Double = 0.78,
        slotExtractionThreshold: Double = 0.78,
        riskThreshold: Double = 0.85,
        operationDetectionThreshold: Double = 0.80
    ) {
        self.mode = mode
        self.semanticNLUThreshold = semanticNLUThreshold
        self.slotExtractionThreshold = slotExtractionThreshold
        self.riskThreshold = riskThreshold
        self.operationDetectionThreshold = operationDetectionThreshold
    }

    public static let `default` = NLUModelCallPolicy()

    /// Legacy default that preserves original threshold-gated behavior.
    public static let legacy = NLUModelCallPolicy(mode: .thresholdGated)

    /// Whether the Foundation Model should be invoked for this task.
    /// In `modelFirstWithHint` and `alwaysModel` modes, always returns `true`.
    /// In `thresholdGated` mode, returns `true` only when deterministic confidence is below threshold.
    public func shouldUseModel(task: NLUWorkerTask, deterministicState: HomeResolutionState) -> Bool {
        switch mode {
        case .modelFirstWithHint, .alwaysModel:
            return true
        case .thresholdGated:
            return thresholdGatedShouldUseModel(task: task, deterministicState: deterministicState)
        }
    }

    /// Whether the deterministic result is confident enough to serve as a reliable hint to the model.
    /// Returns `false` in `alwaysModel` mode (no hints) and `thresholdGated` mode (not applicable).
    public func shouldProvideHint(task: NLUWorkerTask, deterministicState: HomeResolutionState) -> Bool {
        guard mode == .modelFirstWithHint else { return false }
        return !thresholdGatedShouldUseModel(task: task, deterministicState: deterministicState)
    }

    // MARK: - Private

    private func thresholdGatedShouldUseModel(task: NLUWorkerTask, deterministicState: HomeResolutionState) -> Bool {
        switch task {
        case .semanticNLU:
            return min(deterministicState.intent.confidence, deterministicState.deviceType.confidence) < semanticNLUThreshold
        case .slotExtraction:
            return deterministicState.slots.confidence < slotExtractionThreshold
        case .riskClassification:
            if deterministicState.risk.riskLevel == .high || deterministicState.risk.riskLevel == .critical {
                return false
            }
            return deterministicState.risk.confidence < riskThreshold
        case .operationDetection:
            return true
        }
    }
}
