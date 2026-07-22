import Foundation
import HomeAutomationCore

public struct StaticPortfolioRouter: Sendable {
    public let policy: PortfolioEligibilityPolicy
    public let rolloutMode: PortfolioRolloutMode
    public let minimumUtilityMargin: Double

    public init(
        policy: PortfolioEligibilityPolicy = PortfolioEligibilityPolicy(),
        rolloutMode: PortfolioRolloutMode = .shadowStatic,
        minimumUtilityMargin: Double = 0.08
    ) {
        self.policy = policy
        self.rolloutMode = rolloutMode
        self.minimumUtilityMargin = minimumUtilityMargin
    }

    public func decide(_ prepared: PreparedOrchestrationRequest) -> PortfolioDecision {
        let records = policy.records(for: prepared)
        let eligible = records.filter(\.isEligible)
        let rejected = records.filter { !$0.isEligible }
        let uncertainty = policy.uncertainty(for: prepared)

        let selection = selectArm(
            prepared: prepared,
            eligible: eligible,
            uncertainty: uncertainty
        )
        let selectedRecord = selection.arm.flatMap { selected in
            eligible.first { $0.arm == selected }
        }

        let selectedArm = selectedRecord?.arm ?? .graph
        let ruleID = selection.ruleID
        let explanation = explanation(
            selectedArm: selectedArm,
            ruleID: ruleID,
            prepared: prepared,
            uncertainty: uncertainty
        )

        let finalEligible: [PortfolioArmDecisionRecord]
        let finalRejected: [PortfolioArmDecisionRecord]
        if eligible.isEmpty {
            let fallbackRecord = PortfolioArmDecisionRecord(
                arm: .graph,
                isEligible: true,
                selectionReasons: [.noEligibleArm],
                utility: policy.utility(for: .graph, prepared: prepared, rejected: false)
            )
            finalEligible = [fallbackRecord]
            finalRejected = rejected.filter { $0.arm != .graph }
        } else {
            finalEligible = eligible.map { record in
                guard record.arm == selectedArm else { return record }
                return PortfolioArmDecisionRecord(
                    arm: record.arm,
                    isEligible: record.isEligible,
                    rejectionReasons: record.rejectionReasons,
                    selectionReasons: [selection.reason],
                    utility: record.utility
                )
            }
            finalRejected = rejected
        }

        return PortfolioDecision(
            decisionID: decisionID(for: prepared),
            policyVersion: policy.policyVersion,
            rolloutMode: rolloutMode,
            selectedArm: selectedArm,
            safeFallbackArm: .graph,
            ruleID: ruleID,
            explanation: explanation,
            eligibleArms: finalEligible,
            rejectedArms: finalRejected,
            uncertainty: uncertainty,
            featureSchemaVersion: prepared.featureSnapshot.featureSchemaVersion,
            registryVersion: prepared.registryVersion,
            registryFreshness: prepared.registryFreshness(comparedTo: prepared.deviceSnapshot)
        )
    }

    private func selectArm(
        prepared: PreparedOrchestrationRequest,
        eligible: [PortfolioArmDecisionRecord],
        uncertainty: Double
    ) -> (arm: FoundationModelCallArm?, ruleID: String, reason: PortfolioSelectionReason) {
        guard !eligible.isEmpty else {
            return (.graph, "static.noEligible.graphFallback", .noEligibleArm)
        }

        if policy.isStrongLowRiskDirectCommand(prepared.featureSnapshot),
           eligible.contains(where: { $0.arm == .verifierLoop }) {
            return (.verifierLoop, "static.direct.lowRisk.verifierLoop", .directLowRisk)
        }

        if policy.isSimpleConfidentAutomation(prepared),
           eligible.contains(where: { $0.arm == .graphWithTier1 }) {
            return (.graphWithTier1, "static.automation.simpleSchedule.tier1", .simpleScheduleAutomation)
        }

        // Phase 3: a narrowly eligible one-condition schedule automation may use Graph + Tier-1.
        // Must run before the device-trigger and generic `conditionCount > 0 → graph` fallbacks.
        if policy.isEligibleConditionalTier1Automation(prepared),
           eligible.contains(where: { $0.arm == .graphWithTier1 }) {
            return (.graphWithTier1, "static.automation.conditionalSchedule.tier1", .conditionalScheduleAutomation)
        }

        if prepared.deterministicEnvelope.automation?.trigger?.type == .device {
            return (.graph, "static.automation.deviceTrigger.graph", .graphFallback)
        }

        if uncertainty >= 0.65 {
            return (.graph, "static.uncertain.graphFallback", .highUncertainty)
        }

        if prepared.featureSnapshot.precedenceAmbiguity.value == true ||
            (prepared.featureSnapshot.conditionCount.value ?? 0) > 0 ||
            prepared.featureSnapshot.memoryReference.value == true {
            return (.graph, "static.complexOrMemory.graphFallback", .graphFallback)
        }

        let sorted = eligible.sorted {
            if $0.utility.total == $1.utility.total {
                return armPriority($0.arm) < armPriority($1.arm)
            }
            return $0.utility.total > $1.utility.total
        }
        guard let best = sorted.first else {
            return (.graph, "static.noEligible.graphFallback", .noEligibleArm)
        }
        let second = sorted.dropFirst().first
        if let second, best.utility.total - second.utility.total < minimumUtilityMargin {
            return (.graph, "static.lowMargin.graphFallback", .highUncertainty)
        }
        return (best.arm, "static.utility.bestEligible", .graphFallback)
    }

    private func explanation(
        selectedArm: FoundationModelCallArm,
        ruleID: String,
        prepared: PreparedOrchestrationRequest,
        uncertainty: Double
    ) -> String {
        let features = prepared.featureSnapshot
        switch selectedArm {
        case .verifierLoop:
            return "would choose verifier loop: strong low-risk direct command, one action, no memory"
        case .graphWithTier1:
            let actions = features.actionCount.value ?? 0
            if ruleID == "static.automation.conditionalSchedule.tier1" {
                return "would choose Tier-1: eligible schedule with one complete condition, \(actions) confident actions, no memory, low/medium risk"
            }
            return "would choose Tier-1: simple schedule, \(actions) confident actions, no memory, low risk"
        case .graph:
            if ruleID == "static.uncertain.graphFallback" {
                return "would choose graph: high uncertainty \(String(format: "%.2f", uncertainty))"
            }
            if prepared.deterministicEnvelope.automation?.trigger?.type == .device {
                return "would choose graph: device trigger requires graph coverage"
            }
            if features.precedenceAmbiguity.value == true {
                return "would choose graph: precedence ambiguity"
            }
            if features.memoryReference.value == true {
                return "would choose graph: memory reference"
            }
            return "would choose graph: safe fallback"
        default:
            return "would choose graph: non-executable arm rejected"
        }
    }

    private func decisionID(for prepared: PreparedOrchestrationRequest) -> String {
        [
            "static",
            String(policy.policyVersion),
            String(prepared.featureSnapshot.featureSchemaVersion),
            prepared.featureSnapshot.operation.value?.rawValue ?? "unknown",
            prepared.registryVersion
        ].joined(separator: "-")
    }

    private func armPriority(_ arm: FoundationModelCallArm) -> Int {
        switch arm {
        case .graph: return 0
        case .graphWithTier1: return 1
        case .verifierLoop: return 2
        default: return 99
        }
    }
}
