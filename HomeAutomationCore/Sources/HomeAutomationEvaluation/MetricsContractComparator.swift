import Foundation

public struct MetricsContractComparator: Sendable {
    public init() {}

    public func compare(
        _ contract: ExpectedMetricsContract,
        actual trace: NormalizedTrace,
        durationMs: Double? = nil
    ) -> [String] {
        var failures: [String] = []
        if let maxDurationMs = contract.maxDurationMs,
           let durationMs,
           durationMs > maxDurationMs {
            failures.append("Duration \(durationMs)ms exceeded \(maxDurationMs)ms")
        }
        if let maxModelCallCount = contract.maxModelCallCount,
           trace.modelCallCount > maxModelCallCount {
            failures.append("Model calls \(trace.modelCallCount) exceeded \(maxModelCallCount)")
        }
        if let maxToolCallCount = contract.maxToolCallCount,
           trace.toolCallCount > maxToolCallCount {
            failures.append("Tool calls \(trace.toolCallCount) exceeded \(maxToolCallCount)")
        }
        if trace.contextWindowFailureCount > contract.maxContextWindowFailures {
            failures.append("Context-window failures \(trace.contextWindowFailureCount) exceeded \(contract.maxContextWindowFailures)")
        }
        if !contract.expectedSelectedCandidateIDs.isEmpty {
            let actualIDs = Set(trace.selectedDeviceIDs + [trace.targetDeviceID].compactMap { $0 })
            let missing = contract.expectedSelectedCandidateIDs.filter { !actualIDs.contains($0) }
            if !missing.isEmpty {
                failures.append("Missing selected candidate IDs: \(missing.joined(separator: ","))")
            }
        }
        if let expectedActionCount = contract.expectedActionCount {
            let actualActionCount = Set(trace.spans.compactMap { span -> String? in
                guard span.componentKind == "action" || span.actionID != nil else { return nil }
                return span.componentID ?? span.actionID
            }).count
            if actualActionCount != expectedActionCount {
                failures.append("Expected \(expectedActionCount) action component(s), got \(actualActionCount)")
            }
        }
        if let expectedConditionCount = contract.expectedConditionCount {
            let actualConditionCount = Set(trace.spans.compactMap { span -> String? in
                guard span.componentKind == "condition" || span.conditionID != nil else { return nil }
                return span.componentID ?? span.conditionID
            }).count
            if actualConditionCount != expectedConditionCount {
                failures.append("Expected \(expectedConditionCount) condition component(s), got \(actualConditionCount)")
            }
        }
        return failures
    }
}
