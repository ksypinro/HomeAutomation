import Foundation

public struct FoundationModelBatchCoalescingDecision: Sendable, Codable, Hashable {
    public let shouldWait: Bool
    public let delayNanoseconds: UInt64
    public let reason: String

    public init(shouldWait: Bool, delayNanoseconds: UInt64, reason: String) {
        self.shouldWait = shouldWait
        self.delayNanoseconds = delayNanoseconds
        self.reason = reason
    }
}

public struct FoundationModelBatchCoalescer: Sendable {
    public let windowNanoseconds: UInt64

    public init(windowNanoseconds: UInt64 = 15_000_000) {
        self.windowNanoseconds = windowNanoseconds
    }

    public func decision(
        criticalPathSlackMs: Double?,
        isSafetyOrFinalization: Bool,
        hasPendingClarification: Bool = false
    ) -> FoundationModelBatchCoalescingDecision {
        if isSafetyOrFinalization {
            return FoundationModelBatchCoalescingDecision(
                shouldWait: false,
                delayNanoseconds: 0,
                reason: "safety_or_finalization"
            )
        }
        if hasPendingClarification {
            return FoundationModelBatchCoalescingDecision(
                shouldWait: false,
                delayNanoseconds: 0,
                reason: "pending_clarification"
            )
        }
        if let slack = criticalPathSlackMs, slack <= 0 {
            return FoundationModelBatchCoalescingDecision(
                shouldWait: false,
                delayNanoseconds: 0,
                reason: "zero_slack"
            )
        }
        return FoundationModelBatchCoalescingDecision(
            shouldWait: windowNanoseconds > 0,
            delayNanoseconds: windowNanoseconds,
            reason: "compatible_window"
        )
    }
}
