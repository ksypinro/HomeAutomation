import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Portfolio eligibility policy")
struct PortfolioEligibilityPolicyTests {

    @Test("memory reference rejects non-graph arms")
    func memoryReferenceRejectsNonGraphArms() async {
        let prepared = await prepared(
            text: "turn it off",
            memoryHints: [MemoryHint(deviceID: "bedroom_lamp", capability: "switch", confidence: 0.9, reason: "previous turn")]
        )
        let policy = PortfolioEligibilityPolicy()
        let records = policy.records(for: prepared)

        #expect(records.first { $0.arm == .graph }?.isEligible == true)
        #expect(records.first { $0.arm == .verifierLoop }?.rejectionReasons.contains(.memoryUnsupported) == true)
        #expect(records.first { $0.arm == .graphWithTier1 }?.rejectionReasons.contains(.memoryUnsupported) == true)
    }

    @Test("high risk rejects shortcuts")
    func highRiskRejectsShortcuts() async {
        let prepared = await prepared(text: "unlock the front door")
        let policy = PortfolioEligibilityPolicy()
        let records = policy.records(for: prepared)

        #expect(records.first { $0.arm == .graph }?.isEligible == true)
        #expect(records.first { $0.arm == .verifierLoop }?.rejectionReasons.contains(.highRiskPolicy) == true)
        #expect(records.first { $0.arm == .graphWithTier1 }?.rejectionReasons.contains(.highRiskPolicy) == true)
    }

    @Test("missing required feature fails closed")
    func missingRequiredFeatureFailsClosed() async {
        let original = await prepared(text: "turn on the bedroom lamp")
        let snapshot = PortfolioFeatureSnapshot(
            operation: .missing(.unknown, source: .fallbackDefault),
            operationConfidence: original.featureSnapshot.operationConfidence,
            languageOODSignal: original.featureSnapshot.languageOODSignal,
            textSizeBucket: original.featureSnapshot.textSizeBucket,
            actionCount: original.featureSnapshot.actionCount,
            conditionCount: original.featureSnapshot.conditionCount,
            minimumFieldConfidence: original.featureSnapshot.minimumFieldConfidence,
            p50FieldConfidence: original.featureSnapshot.p50FieldConfidence,
            p90FieldConfidence: original.featureSnapshot.p90FieldConfidence,
            candidateCount: original.featureSnapshot.candidateCount,
            candidateTopTwoMargin: original.featureSnapshot.candidateTopTwoMargin,
            unsupportedFragmentCount: original.featureSnapshot.unsupportedFragmentCount,
            precedenceAmbiguity: original.featureSnapshot.precedenceAmbiguity,
            riskFloor: original.featureSnapshot.riskFloor,
            memoryReference: original.featureSnapshot.memoryReference,
            exactTemplateMatch: original.featureSnapshot.exactTemplateMatch,
            foundationModelAvailability: original.featureSnapshot.foundationModelAvailability,
            ragAvailability: original.featureSnapshot.ragAvailability,
            gateDepth: original.featureSnapshot.gateDepth,
            warmStateHint: original.featureSnapshot.warmStateHint,
            extractionDurationMs: original.featureSnapshot.extractionDurationMs
        )
        let mutated = PreparedOrchestrationRequest(
            request: original.request,
            featureSnapshot: snapshot,
            deterministicEnvelope: original.deterministicEnvelope,
            deviceSnapshot: original.deviceSnapshot,
            memoryReferenceDetected: original.memoryReferenceDetected,
            memoryHints: original.memoryHints,
            resolutionState: original.resolutionState,
            candidateIDs: original.candidateIDs
        )

        let records = PortfolioEligibilityPolicy().records(for: mutated)

        #expect(records.allSatisfy { $0.rejectionReasons.contains(.featureMissing) })
    }

    private func prepared(
        text: String,
        memoryHints: [MemoryHint] = []
    ) async -> PreparedOrchestrationRequest {
        await OrchestrationFeatureExtractor(registry: MockHomeDeviceRegistry())
            .prepare(.init(
                request: CommandRequest(text: text, executeLowRiskCommands: false),
                memoryHints: memoryHints,
                foundationModelAvailability: .available,
                ragAvailability: .unknown,
                gateDepth: .none,
                warmStateHint: .unknown
            ))
    }
}
