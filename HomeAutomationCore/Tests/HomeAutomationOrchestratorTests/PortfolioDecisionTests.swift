import Foundation
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Portfolio decision")
struct PortfolioDecisionTests {

    @Test("decision JSON round trips deterministically")
    func decisionRoundTrip() throws {
        let decision = PortfolioDecision(
            decisionID: "static-1-1-executeDeviceCommand-registry",
            policyVersion: 1,
            rolloutMode: .shadowStatic,
            selectedArm: .verifierLoop,
            ruleID: "static.direct.lowRisk.verifierLoop",
            explanation: "would choose verifier loop: strong low-risk direct command, one action, no memory",
            eligibleArms: [
                PortfolioArmDecisionRecord(
                    arm: .verifierLoop,
                    isEligible: true,
                    selectionReasons: [.directLowRisk],
                    utility: PortfolioUtilityComponents(
                        correctnessPrior: 0.8,
                        latencyPrior: 0.7,
                        modelCallPrior: 0.6,
                        escalationRisk: 0.2,
                        uncertainty: 0.1,
                        safetyPenalty: 0
                    )
                )
            ],
            rejectedArms: [
                PortfolioArmDecisionRecord(
                    arm: .graphWithTier1,
                    isEligible: false,
                    rejectionReasons: [.unsupportedOperation],
                    utility: PortfolioUtilityComponents(
                        correctnessPrior: 0.5,
                        latencyPrior: 0.5,
                        modelCallPrior: 0.5,
                        escalationRisk: 0.5,
                        uncertainty: 0.5,
                        safetyPenalty: 1
                    )
                )
            ],
            uncertainty: 0.1,
            featureSchemaVersion: PortfolioFeatureSchema.currentVersion,
            registryVersion: "registry",
            registryFreshness: .fresh
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let first = try encoder.encode(decision)
        let second = try encoder.encode(decision)
        let decoded = try JSONDecoder().decode(PortfolioDecision.self, from: first)

        #expect(first == second)
        #expect(decoded == decision)
        #expect(decoded.selectedArmIsEligible)
    }
}
