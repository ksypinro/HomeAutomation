import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Static portfolio router")
struct StaticPortfolioRouterTests {

    @Test("strong low-risk direct command would choose verifier loop")
    func directCommandChoosesVerifierLoop() async {
        let decision = await decide(text: "turn on the bedroom lamp")

        #expect(decision.selectedArm == .verifierLoop)
        #expect(decision.ruleID == "static.direct.lowRisk.verifierLoop")
        #expect(decision.selectedArmIsEligible)
        #expect(everyArmConsideredOnce(decision))
    }

    @Test("simple schedule automation would choose Tier-1")
    func simpleScheduleChoosesTier1() async {
        let decision = await decide(text: "turn on the bedroom lamp every day at 7 PM")

        #expect(decision.selectedArm == .graphWithTier1)
        #expect(decision.ruleID == "static.automation.simpleSchedule.tier1")
        #expect(decision.selectedArmIsEligible)
    }

    @Test("device trigger would choose graph")
    func deviceTriggerChoosesGraph() async {
        let decision = await decide(text: "When the entry contact sensor opens, turn on the porch light")

        #expect(decision.selectedArm == .graph)
        #expect(decision.ruleID == "static.automation.deviceTrigger.graph")
        #expect(decision.selectedArmIsEligible)
    }

    @Test("explanation is bounded and privacy safe")
    func explanationIsPrivacySafe() async {
        let decision = await decide(text: "turn on the bedroom lamp every day at 7 PM")

        #expect(decision.explanation.contains("would choose"))
        #expect(!decision.explanation.contains("bedroom_lamp"))
        #expect(!decision.explanation.contains("Bedroom Lamp"))
        #expect(!decision.explanation.contains("turn on the bedroom lamp"))
    }

    private func decide(text: String) async -> PortfolioDecision {
        let prepared = await OrchestrationFeatureExtractor(registry: MockHomeDeviceRegistry())
            .prepare(.init(
                request: CommandRequest(text: text, executeLowRiskCommands: false),
                foundationModelAvailability: .available,
                ragAvailability: .unknown,
                gateDepth: .none,
                warmStateHint: .unknown
            ))
        return StaticPortfolioRouter().decide(prepared)
    }

    private func everyArmConsideredOnce(_ decision: PortfolioDecision) -> Bool {
        let arms = (decision.eligibleArms + decision.rejectedArms).map(\.arm)
        return Set(arms).count == arms.count && Set(arms) == Set([.graph, .graphWithTier1, .verifierLoop])
    }
}
