import Foundation
import HomeAutomationCore

// MARK: - RepairSpecialistID

public enum RepairSpecialistID: String, Sendable, Hashable, Codable {
    case operationDetection
    case fragmentNLU
    case target
    case capability
    case riskRaise
    case trigger
    case conditionClause
    case segmentation
    case holisticDraft
}

// MARK: - RepairPlanner

public struct RepairPlanner: Sendable {

    public struct Plan: Sendable, Equatable {
        public let steps: [RepairStep]
        public let deferred: [DraftDispute]

        public init(steps: [RepairStep], deferred: [DraftDispute]) {
            self.steps = steps
            self.deferred = deferred
        }
    }

    public struct RepairStep: Sendable, Equatable {
        public let specialist: RepairSpecialistID
        public let fieldIDs: [FieldID]
        public let disputes: [DraftDispute]

        public init(specialist: RepairSpecialistID, fieldIDs: [FieldID], disputes: [DraftDispute]) {
            self.specialist = specialist
            self.fieldIDs = fieldIDs
            self.disputes = disputes
        }
    }

    public init() {}

    public func plan(
        disputes: [DraftDispute],
        envelope: DraftEnvelope,
        latchedFieldIDs: Set<FieldID>,
        maxRepairCalls: Int
    ) -> Plan {
        var scheduled: [RepairStep] = []
        var deferred: [DraftDispute] = []

        let grouped = groupBySpecialist(disputes, envelope: envelope)

        let ordered = grouped.sorted { priority(of: $0.key) < priority(of: $1.key) }

        for (specialist, groupDisputes) in ordered {
            let latchedDisputes = groupDisputes.filter { latchedFieldIDs.contains(FieldID(rawValue: $0.fieldID)) }
            let activeDisputes = groupDisputes.filter { !latchedFieldIDs.contains(FieldID(rawValue: $0.fieldID)) }

            if !latchedDisputes.isEmpty {
                deferred.append(contentsOf: latchedDisputes)
            }

            guard !activeDisputes.isEmpty else { continue }

            let activeFieldIDs = activeDisputes.map { FieldID(rawValue: $0.fieldID) }

            if specialist == .riskRaise {
                scheduled.append(RepairStep(
                    specialist: specialist,
                    fieldIDs: activeFieldIDs,
                    disputes: activeDisputes
                ))
                continue
            }

            if scheduled.count(where: { $0.specialist != .riskRaise }) < maxRepairCalls {
                scheduled.append(RepairStep(
                    specialist: specialist,
                    fieldIDs: activeFieldIDs,
                    disputes: activeDisputes
                ))
            } else {
                deferred.append(contentsOf: activeDisputes)
            }
        }

        return Plan(steps: scheduled, deferred: deferred)
    }

    // MARK: - Specialist dispatch

    private func groupBySpecialist(
        _ disputes: [DraftDispute],
        envelope: DraftEnvelope
    ) -> [RepairSpecialistID: [DraftDispute]] {
        var groups: [RepairSpecialistID: [DraftDispute]] = [:]
        for dispute in disputes {
            let specialist = routeToSpecialist(dispute, envelope: envelope)
            groups[specialist, default: []].append(dispute)
        }
        return groups
    }

    private func routeToSpecialist(
        _ dispute: DraftDispute,
        envelope: DraftEnvelope
    ) -> RepairSpecialistID {
        let fieldID = dispute.fieldID

        if fieldID == FieldID.operation.rawValue {
            return .operationDetection
        }

        if dispute.kind == .wrongOperation {
            return .operationDetection
        }

        if dispute.kind == .wrongGrouping {
            return .segmentation
        }

        if fieldID == FieldID.riskLevel.rawValue {
            return .riskRaise
        }

        if fieldID.hasPrefix("automation.trigger.") {
            return .trigger
        }

        if fieldID.hasPrefix("automation.conditionLeaves[") {
            return .conditionClause
        }

        if fieldID.hasPrefix("automation.conditionTree.") {
            return .segmentation
        }

        if fieldID.contains(".targetDeviceID") {
            return .target
        }

        if fieldID.contains(".capability") || fieldID.contains(".commandName") || fieldID.contains(".parameters") {
            return .capability
        }

        if fieldID.contains(".room") {
            return .target
        }

        return .fragmentNLU
    }

    private func priority(of specialist: RepairSpecialistID) -> Int {
        switch specialist {
        case .operationDetection: return 0
        case .segmentation: return 1
        case .fragmentNLU: return 2
        case .target: return 3
        case .trigger: return 3
        case .capability: return 4
        case .conditionClause: return 4
        case .riskRaise: return 5
        case .holisticDraft: return 6
        }
    }
}
