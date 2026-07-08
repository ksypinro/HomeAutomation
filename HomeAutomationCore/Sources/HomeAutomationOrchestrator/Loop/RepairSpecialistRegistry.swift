import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public struct RepairSpecialistRegistry: Sendable {
    public let execute: @Sendable (RepairPlanner.RepairStep, DraftEnvelope) async -> RepairResult?

    public init(
        execute: @escaping @Sendable (RepairPlanner.RepairStep, DraftEnvelope) async -> RepairResult?
    ) {
        self.execute = execute
    }

    public init(
        fragmentNLU: FragmentNLUWorkerSession,
        targetResolver: ActionTargetResolver,
        riskAssessor: AutomationRiskAssessor,
        operationDetection: @escaping @Sendable (String) async -> HomeOperationDetectionResult?
    ) {
        self.execute = { @Sendable step, envelope in
            switch step.specialist {
            case .operationDetection:
                guard let result = await operationDetection(envelope.userText) else { return nil }
                return .operation(result)

            case .fragmentNLU:
                let actionIndex = step.fieldIDs.first.flatMap { fieldID -> Int? in
                    guard let match = fieldID.rawValue.firstMatch(of: /automation\.actions\[(\d+)\]/) else { return nil }
                    return Int(match.output.1)
                }
                let text: String
                if let idx = actionIndex, let auto = envelope.automation, idx < auto.actions.count {
                    text = auto.actions[idx].rawText
                } else {
                    text = envelope.userText
                }
                guard let output = try? await fragmentNLU.analyze(text) else { return nil }
                return .fragmentNLU(actionIndex: actionIndex, output)

            case .target:
                guard let fieldID = step.fieldIDs.first else { return nil }
                let hint = step.disputes.first?.suggestedValue
                let candidates: [CompactCandidate]
                let fragmentText: String

                if fieldID.rawValue.hasPrefix("command.") {
                    candidates = envelope.command?.candidateTable ?? []
                    fragmentText = envelope.userText
                } else if let match = fieldID.rawValue.firstMatch(of: /automation\.actions\[(\d+)\]/),
                          let idx = Int(match.output.1),
                          let auto = envelope.automation, idx < auto.actions.count {
                    candidates = auto.actions[idx].command.candidateTable
                    fragmentText = auto.actions[idx].rawText
                } else {
                    return nil
                }

                let result = await targetResolver.resolve(
                    fragmentText: fragmentText,
                    candidates: candidates,
                    hint: hint
                )
                return .target(fieldID: fieldID, result)

            case .capability:
                return nil

            case .riskRaise:
                let risk = riskAssessor.assess(envelope: envelope)
                let result = HomeRiskClassificationResult(
                    riskLevel: risk.level,
                    requiresConfirmation: risk.level == .high || risk.level == .critical,
                    reason: risk.floorReason,
                    confidence: 0.9
                )
                return .riskRaise(result)

            case .trigger, .conditionClause, .segmentation, .holisticDraft:
                return nil
            }
        }
    }
}
