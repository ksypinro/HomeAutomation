import Foundation
import HomeAutomationCore

public struct ExpectedMetricsContractFactory: Sendable {
    public init() {}

    public func makeContracts(for cases: [GeneratedEvaluationCase]) -> [ExpectedMetricsContract] {
        cases.map(makeContract(for:))
    }

    public func makeContract(for testCase: GeneratedEvaluationCase) -> ExpectedMetricsContract {
        let isAutomation = testCase.expected.operation == .automationCreation
        let isUnsupported = testCase.expected.allowedOutcome == .unsupported
        return ExpectedMetricsContract(
            id: testCase.metricsContractID,
            caseID: testCase.id,
            maxDurationMs: isAutomation ? 45_000 : 30_000,
            maxModelCallCount: isUnsupported ? 8 : (isAutomation ? 48 : 24),
            maxSkippedModelCallCount: nil,
            maxToolCallCount: isAutomation ? 96 : 48,
            maxContextWindowFailures: 0,
            minCandidateRecallAt1: testCase.expected.expectedDeviceIDs.isEmpty ? nil : 0,
            minCandidateRecallAt3: testCase.expected.expectedDeviceIDs.isEmpty ? nil : 0,
            minCandidateRecallAt5: testCase.expected.expectedDeviceIDs.isEmpty ? nil : 0,
            expectedRetrievedCandidateContains: testCase.expected.expectedDeviceIDs,
            expectedHydratedCandidateContains: testCase.expected.expectedDeviceIDs,
            expectedSelectedCandidateIDs: testCase.expected.expectedDeviceIDs,
            expectedActionCount: testCase.expected.actionCount,
            expectedConditionCount: testCase.expected.conditionCount
        )
    }
}
