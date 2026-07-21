import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import os

public struct BatchedActionCapabilityRequest: Sendable {
    public let itemID: FoundationModelBatchItemID
    public let input: CapabilityResolutionInput

    public init(itemID: FoundationModelBatchItemID, input: CapabilityResolutionInput) {
        self.itemID = itemID
        self.input = input
    }
}

public struct BatchedActionCapabilityResolver: Sendable {
    private let worker: CapabilityResolutionWorker
    private let resolveBatch: (@Sendable ([BatchedActionCapabilityRequest]) async throws -> [FoundationModelBatchItemID: HomeCapabilityDecision])?
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "BatchedActionCapability")

    public init(
        worker: CapabilityResolutionWorker,
        resolveBatch: (@Sendable ([BatchedActionCapabilityRequest]) async throws -> [FoundationModelBatchItemID: HomeCapabilityDecision])? = nil
    ) {
        self.worker = worker
        self.resolveBatch = resolveBatch
    }

    public func resolveAll(
        _ requests: [BatchedActionCapabilityRequest]
    ) async -> [FoundationModelBatchItemID: HomeCapabilityDecision] {
        guard !requests.isEmpty else { return [:] }
        guard requests.count > 1, let resolveBatch else {
            return await resolveIndividually(requests)
        }

        do {
            let compatibility = FoundationModelBatchCompatibilityKey(
                runID: HomeAutomationTelemetryScope.current?.runID,
                instructionDigest: FoundationModelBatchCompatibilityKey.stableDigest("CapabilityResolutionWorker.instructions"),
                responseSchemaDigest: FoundationModelBatchCompatibilityKey.stableDigest("BatchedActionCapability.v1.itemID"),
                toolSetDigest: FoundationModelBatchCompatibilityKey.stableDigest("capabilityCandidateDeviceDetails|getAllCapabilities"),
                privacyClass: .privateUserData,
                workflowScopeID: FMAdmissionContextScope.current?.workflowScopeID
            )
            let context = FoundationModelBatchContext(
                batchID: "action-capability-\(UUID().uuidString)",
                itemCount: requests.count,
                compatibilityDigest: compatibility.digest
            )
            let batched = try await FoundationModelBatchContextScope.$current.withValue(context) {
                try await resolveBatch(requests)
            }

            var output: [FoundationModelBatchItemID: HomeCapabilityDecision] = [:]
            var fallbackRequests: [BatchedActionCapabilityRequest] = []
            for request in requests {
                if let decision = batched[request.itemID] {
                    output[request.itemID] = decision
                } else {
                    fallbackRequests.append(request)
                }
            }
            if !fallbackRequests.isEmpty {
                logger.debug("[BatchedActionCapability] Falling back \(fallbackRequests.count, privacy: .public) missing item(s).")
                let fallback = await resolveIndividually(fallbackRequests)
                output.merge(fallback) { current, _ in current }
            }
            return output
        } catch {
            logger.error("[BatchedActionCapability] Batch failed: \(error.localizedDescription, privacy: .public); falling back per item.")
            return await resolveIndividually(requests)
        }
    }

    private func resolveIndividually(
        _ requests: [BatchedActionCapabilityRequest]
    ) async -> [FoundationModelBatchItemID: HomeCapabilityDecision] {
        var output: [FoundationModelBatchItemID: HomeCapabilityDecision] = [:]
        for request in requests {
            if let decision = try? await worker.resolve(request.input) {
                output[request.itemID] = decision
            }
        }
        return output
    }
}
