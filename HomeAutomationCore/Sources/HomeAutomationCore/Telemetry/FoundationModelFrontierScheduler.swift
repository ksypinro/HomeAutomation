import Foundation

public struct FMFrontierScore: Sendable, Codable, Hashable {
    public let requestID: UUID
    public let score: Double
    public let fallbackReason: FMAdmissionFallbackReason

    public init(requestID: UUID, score: Double, fallbackReason: FMAdmissionFallbackReason) {
        self.requestID = requestID
        self.score = score
        self.fallbackReason = fallbackReason
    }
}

public struct FoundationModelFrontierScheduler: Sendable {
    public init() {}

    public func rank(
        _ requests: [FMAdmissionRequest],
        nowNanoseconds: UInt64,
        lastPrefixAffinityKey: String? = nil,
        suppressedRunID: String? = nil
    ) -> [FMAdmissionRequest] {
        requests.sorted { lhs, rhs in
            let lhsScore = score(
                lhs,
                nowNanoseconds: nowNanoseconds,
                lastPrefixAffinityKey: lastPrefixAffinityKey,
                suppressedRunID: suppressedRunID
            )
            let rhsScore = score(
                rhs,
                nowNanoseconds: nowNanoseconds,
                lastPrefixAffinityKey: lastPrefixAffinityKey,
                suppressedRunID: suppressedRunID
            )
            switch (lhsScore, rhsScore) {
            case (.some(let lhsScore), .some(let rhsScore)):
                if lhsScore.score != rhsScore.score {
                    return lhsScore.score > rhsScore.score
                }
                return lhs.sequence < rhs.sequence
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.sequence < rhs.sequence
            }
        }
    }

    public func score(
        _ request: FMAdmissionRequest,
        nowNanoseconds: UInt64,
        lastPrefixAffinityKey: String? = nil,
        suppressedRunID: String? = nil
    ) -> FMFrontierScore? {
        guard request.hasFrontierMetadata,
              let criticalPathRemainingMs = request.criticalPathRemainingMs,
              let estimatedServiceMs = request.estimatedServiceMs
        else {
            return nil
        }

        let queueAgeMs = max(0, Double(nowNanoseconds.saturatingSubtracting(request.enqueuedAtNanoseconds)) / 1_000_000)
        let urgency = criticalPathRemainingMs / max(estimatedServiceMs, 1)
        let aging = min(queueAgeMs / 1_000, 5)
        let deadlineBoost: Double = switch request.deadlineClass {
        case .interactive: 1.25
        case .finalizer: 0.75
        case .pipeline, .unknown: 0
        }
        let cancellationPenalty: Double = switch request.cancellationClass {
        case .cancellationResistant: 0
        case .normal: 0.15
        case .bestEffort: 0.5
        case .unknown: 0.25
        }
        let prefixBoost = request.prefixAffinityKey != nil
            && request.prefixAffinityKey == lastPrefixAffinityKey ? 0.35 : 0
        let fairnessPenalty = request.runID != nil
            && request.runID == suppressedRunID ? 1.0 : 0

        return FMFrontierScore(
            requestID: request.requestID,
            score: urgency + aging + deadlineBoost + prefixBoost - cancellationPenalty - fairnessPenalty,
            fallbackReason: .none
        )
    }
}

private extension UInt64 {
    func saturatingSubtracting(_ other: UInt64) -> UInt64 {
        self >= other ? self - other : 0
    }
}
