import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Learned portfolio router")
struct LearnedPortfolioRouterTests {

    @Test("selects highest utility eligible arm")
    func selectsHighestUtilityEligibleArm() async {
        let prepared = await prepared(text: "turn on the bedroom lamp")
        let artifact = artifact(graph: 0.2, tier1: 0.1, verifier: 0.95)

        let decision = LearnedPortfolioRouter(artifact: artifact).decide(prepared)

        #expect(decision.selectedArm == .verifierLoop)
        #expect(decision.ruleID == "learned.utility.bestEligible")
        #expect(decision.selectedArmIsEligible)
    }

    @Test("falls back on OOD features")
    func fallsBackOnOODFeatures() async {
        let base = await prepared(text: "turn on the bedroom lamp")
        let snapshot = PortfolioModelArtifactTests.features(language: .unsupportedLanguage)
        let ood = PreparedOrchestrationRequest(
            request: base.request,
            featureSnapshot: snapshot,
            deterministicEnvelope: base.deterministicEnvelope,
            deviceSnapshot: base.deviceSnapshot,
            memoryReferenceDetected: base.memoryReferenceDetected,
            memoryHints: base.memoryHints,
            resolutionState: base.resolutionState,
            candidateIDs: base.candidateIDs
        )

        let decision = LearnedPortfolioRouter(artifact: artifact(graph: 0.2, tier1: 0.1, verifier: 0.95)).decide(ood)

        #expect(decision.ruleID == "learned.fallback.ood")
        #expect(decision.selectedArm == .graph)
    }

    @Test("low learned margin falls back to static decision")
    func lowMarginFallsBack() async {
        let prepared = await prepared(text: "turn on the bedroom lamp")
        let decision = LearnedPortfolioRouter(
            artifact: artifact(graph: 0.70, tier1: 0.69, verifier: 0.68, minimumMargin: 0.1)
        ).decide(prepared)

        #expect(decision.ruleID == "learned.fallback.lowMargin")
        #expect(decision.selectedArm == .verifierLoop)
    }

    private func prepared(text: String) async -> PreparedOrchestrationRequest {
        await OrchestrationFeatureExtractor(registry: MockHomeDeviceRegistry())
            .prepare(.init(
                request: CommandRequest(text: text, executeLowRiskCommands: false),
                foundationModelAvailability: .available,
                ragAvailability: .unknown,
                gateDepth: .none,
                warmStateHint: .unknown
            ))
    }

    private func artifact(
        graph: Double,
        tier1: Double,
        verifier: Double,
        minimumMargin: Double = 0.05
    ) -> PortfolioModelArtifact {
        PortfolioModelArtifact(
            modelVersion: "test-router",
            trainingDatasetID: "dataset",
            minimumUtilityMargin: minimumMargin,
            armModels: [
                PortfolioArmModel(arm: .graph, coefficients: .init(intercept: graph)),
                PortfolioArmModel(arm: .graphWithTier1, coefficients: .init(intercept: tier1)),
                PortfolioArmModel(arm: .verifierLoop, coefficients: .init(intercept: verifier)),
            ]
        )
    }
}
