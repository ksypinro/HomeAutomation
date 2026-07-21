import Foundation
import HomeAutomationCore

public struct PortfolioMetrics: Sendable, Codable, Equatable, Hashable {
    public let runID: String
    public let selectedArm: FoundationModelCallArm
    public let actualModelCallCount: Int
    public let failedModelCallCount: Int
    public let cancelledModelCallCount: Int
    public let fmQueueWaitTotalMs: Double
    public let fmServiceTotalMs: Double
    public let telemetryOverheadMs: Double
    public let promptCharacterCount: Int
    public let outputCharacterCount: Int
    public let preparationMs: Double?
    public let routerMs: Double?
    public let compilerFallbackMs: Double?
    public let schedulerWaitMs: Double?
    public let cancellationSavingsMs: Double?
    public let finalizerMs: Double?
    public let eligibleArms: [FoundationModelCallArm]?
    public let predictedUtility: Double?
    public let observedUtility: Double?

    public init(
        snapshot: FoundationModelUsageSnapshot,
        selectedArm: FoundationModelCallArm,
        preparationMs: Double? = nil,
        routerMs: Double? = nil,
        compilerFallbackMs: Double? = nil,
        schedulerWaitMs: Double? = nil,
        cancellationSavingsMs: Double? = nil,
        finalizerMs: Double? = nil,
        eligibleArms: [FoundationModelCallArm]? = nil,
        predictedUtility: Double? = nil,
        observedUtility: Double? = nil
    ) {
        self.runID = snapshot.runID
        self.selectedArm = selectedArm
        self.actualModelCallCount = snapshot.summary.actualCallCount
        self.failedModelCallCount = snapshot.summary.failedCallCount
        self.cancelledModelCallCount = snapshot.summary.cancelledCallCount
        self.fmQueueWaitTotalMs = snapshot.summary.queueWaitTotalMs
        self.fmServiceTotalMs = snapshot.summary.serviceTotalMs
        self.telemetryOverheadMs = snapshot.summary.telemetryOverheadMs
        self.promptCharacterCount = snapshot.summary.promptCharacterCount
        self.outputCharacterCount = snapshot.summary.outputCharacterCount
        self.preparationMs = preparationMs
        self.routerMs = routerMs
        self.compilerFallbackMs = compilerFallbackMs
        self.schedulerWaitMs = schedulerWaitMs
        self.cancellationSavingsMs = cancellationSavingsMs
        self.finalizerMs = finalizerMs
        self.eligibleArms = eligibleArms
        self.predictedUtility = predictedUtility
        self.observedUtility = observedUtility
    }
}
