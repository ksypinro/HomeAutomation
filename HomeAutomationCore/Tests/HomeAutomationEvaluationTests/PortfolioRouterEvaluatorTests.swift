import Foundation
import HomeAutomationCore
import HomeAutomationEvaluation
import HomeAutomationOrchestrator
import Testing

@Suite("Portfolio router evaluator")
struct PortfolioRouterEvaluatorTests {

    @Test("computes regret against best eligible oracle")
    func computesRegret() {
        let features = Self.features()
        let dataset = PortfolioTrainingDataset(
            datasetID: "dataset",
            rows: [
                row(caseID: "case-1", arm: .graph, features: features, utility: 0.4),
                row(caseID: "case-1", arm: .verifierLoop, features: features, utility: 0.9),
            ]
        )
        let artifact = PortfolioModelArtifact(
            modelVersion: "artifact",
            trainingDatasetID: "dataset",
            armModels: [
                PortfolioArmModel(arm: .graph, coefficients: .init(intercept: 1.0)),
                PortfolioArmModel(arm: .verifierLoop, coefficients: .init(intercept: 0.5)),
            ]
        )

        let report = PortfolioRouterEvaluator(artifact: artifact).evaluate(dataset)

        #expect(report.caseCount == 1)
        #expect(report.cases.first?.selectedArm == .graph)
        #expect(report.cases.first?.oracleArm == .verifierLoop)
        #expect(abs((report.cases.first?.regret ?? 0) - 0.5) < 0.0001)
        #expect(report.slices.contains { $0.name == "operation:executeDeviceCommand" })
    }

    @Test("safety failure makes row ineligible")
    func safetyFailureIneligible() {
        let features = Self.features()
        let dataset = PortfolioTrainingDataset(
            datasetID: "dataset",
            rows: [
                row(caseID: "case-1", arm: .graph, features: features, utility: 0.4),
                row(caseID: "case-1", arm: .verifierLoop, features: features, eligible: false, safetyFailure: true, utility: .infinity),
            ]
        )
        let artifact = PortfolioModelArtifact(
            modelVersion: "artifact",
            trainingDatasetID: "dataset",
            armModels: [
                PortfolioArmModel(arm: .graph, coefficients: .init(intercept: 0.1)),
                PortfolioArmModel(arm: .verifierLoop, coefficients: .init(intercept: 1.0)),
            ]
        )

        let report = PortfolioRouterEvaluator(artifact: artifact).evaluate(dataset)

        #expect(report.cases.first?.selectedArm == .graph)
        #expect(report.cases.first?.oracleArm == .graph)
    }

    private func row(
        caseID: String,
        arm: FoundationModelCallArm,
        features: PortfolioFeatureSnapshot,
        eligible: Bool = true,
        safetyFailure: Bool = false,
        utility: Double
    ) -> PortfolioTrainingRow {
        PortfolioTrainingRow(
            datasetID: "dataset",
            caseID: caseID,
            arm: arm,
            features: features,
            eligible: eligible,
            rejectionReasons: safetyFailure ? [.finalizerReadinessUnknown] : [],
            correctness: utility > 0 ? 1 : 0,
            durationMs: 10,
            durationP95Ms: 10,
            actualModelCalls: 0,
            queueWaitMs: 0,
            escalated: false,
            clarification: false,
            confirmation: false,
            failed: false,
            safetyFailure: safetyFailure,
            utility: utility
        )
    }

    private static func features() -> PortfolioFeatureSnapshot {
        PortfolioFeatureSnapshot(
            operation: .present(.executeDeviceCommand, source: .injectedFixture),
            operationConfidence: .present(0.9, source: .injectedFixture),
            languageOODSignal: .present(.inDomain, source: .injectedFixture),
            textSizeBucket: .present(.short, source: .injectedFixture),
            actionCount: .present(1, source: .injectedFixture),
            conditionCount: .present(0, source: .injectedFixture),
            minimumFieldConfidence: .present(0.85, source: .injectedFixture),
            p50FieldConfidence: .present(0.88, source: .injectedFixture),
            p90FieldConfidence: .present(0.95, source: .injectedFixture),
            candidateCount: .present(1, source: .injectedFixture),
            candidateTopTwoMargin: .present(0.5, source: .injectedFixture),
            unsupportedFragmentCount: .present(0, source: .injectedFixture),
            precedenceAmbiguity: .present(false, source: .injectedFixture),
            riskFloor: .present(.low, source: .injectedFixture),
            memoryReference: .present(false, source: .injectedFixture),
            exactTemplateMatch: .present(true, source: .injectedFixture),
            foundationModelAvailability: .present(.available, source: .injectedFixture),
            ragAvailability: .present(.unknown, source: .injectedFixture),
            gateDepth: .present(.none, source: .injectedFixture),
            warmStateHint: .present(.likelyWarm, source: .injectedFixture),
            extractionDurationMs: 0
        )
    }
}
