import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public enum FinalizationReceiptStatus: String, Sendable, Hashable, Codable {
    case completed
    case incomplete
    case failed
}

public struct FinalizationGateRecord: Sendable, Hashable, Codable {
    public let gateID: String
    public let status: String

    public init(gateID: String, status: String) {
        self.gateID = gateID
        self.status = status
    }
}

public struct ResolutionFinalizationReceipt: Sendable, Hashable, Codable {
    public let status: FinalizationReceiptStatus
    public let graphID: String?
    public let policyVersion: String
    public let requiredGateIDs: [String]
    public let gateRecords: [FinalizationGateRecord]
    public let missingGateIDs: [String]
    public let failedGateID: String?

    public init(
        status: FinalizationReceiptStatus,
        graphID: String?,
        policyVersion: String = "phase1-finalizer-receipt-v1",
        requiredGateIDs: [String],
        gateRecords: [FinalizationGateRecord],
        missingGateIDs: [String],
        failedGateID: String?
    ) {
        self.status = status
        self.graphID = graphID
        self.policyVersion = policyVersion
        self.requiredGateIDs = requiredGateIDs
        self.gateRecords = gateRecords
        self.missingGateIDs = missingGateIDs
        self.failedGateID = failedGateID
    }

    public static func directCommand(
        graphRun: GraphRunMetrics?,
        resolution: HomeCommandResolution
    ) -> ResolutionFinalizationReceipt? {
        guard case .readyToExecute = resolution else {
            if case .executed = resolution {
                return make(
                    graphRun: graphRun,
                    requiredGateIDs: directMutationGateIDs
                )
            }
            if case .requiresConfirmation = resolution {
                return make(
                    graphRun: graphRun,
                    requiredGateIDs: directConfirmationGateIDs
                )
            }
            return nil
        }

        return make(
            graphRun: graphRun,
            requiredGateIDs: directMutationGateIDs,
            skippedGateIDsAllowed: [AgentID.mockExecution.rawValue]
        )
    }

    public static func automationCreation(
        graphRun: GraphRunMetrics?,
        resolution: HomeCommandResolution
    ) -> ResolutionFinalizationReceipt? {
        switch resolution {
        case .automationDrafted:
            return make(
                graphRun: graphRun,
                requiredGateIDs: automationDraftGateIDs,
                skippedGateIDsAllowed: [AgentID.smartThingsRuleCreation.rawValue]
            )
        case .automationRequiresConfirmation:
            return make(
                graphRun: graphRun,
                requiredGateIDs: automationConfirmationGateIDs
            )
        default:
            return nil
        }
    }

    private static let directConfirmationGateIDs = [
        AgentID.safetyValidation.rawValue,
        AgentID.parameterValidation.rawValue,
        AgentID.confirmationPolicy.rawValue
    ]

    private static let directMutationGateIDs = directConfirmationGateIDs + [
        AgentID.executionPlanning.rawValue,
        AgentID.mockExecution.rawValue
    ]

    private static let automationConfirmationGateIDs = [
        AgentID.automationValidation.rawValue
    ]

    private static let automationDraftGateIDs = automationConfirmationGateIDs + [
        AgentID.smartThingsCompilation.rawValue,
        AgentID.smartThingsRuleCreation.rawValue,
        AgentID.automationResultAssembly.rawValue
    ]

    private static func make(
        graphRun: GraphRunMetrics?,
        requiredGateIDs: [String],
        skippedGateIDsAllowed: Set<String> = []
    ) -> ResolutionFinalizationReceipt {
        let statuses = graphRun?.nodeStatuses ?? [:]
        let gateRecords = requiredGateIDs.compactMap { gateID -> FinalizationGateRecord? in
            guard let status = statuses[gateID] else { return nil }
            return FinalizationGateRecord(gateID: gateID, status: status.rawValue)
        }
        let missingGateIDs = requiredGateIDs.filter { statuses[$0] == nil }
        let failedGateID = requiredGateIDs.first { statuses[$0] == .failed }
        let incompleteGateID = requiredGateIDs.first { gateID in
            guard let status = statuses[gateID] else { return true }
            if status == .completed { return false }
            return !(status == .skipped && skippedGateIDsAllowed.contains(gateID))
        }

        let status: FinalizationReceiptStatus
        if failedGateID != nil {
            status = .failed
        } else if incompleteGateID != nil {
            status = .incomplete
        } else {
            status = .completed
        }

        return ResolutionFinalizationReceipt(
            status: status,
            graphID: graphRun?.graphID,
            requiredGateIDs: requiredGateIDs,
            gateRecords: gateRecords,
            missingGateIDs: missingGateIDs,
            failedGateID: failedGateID
        )
    }
}
