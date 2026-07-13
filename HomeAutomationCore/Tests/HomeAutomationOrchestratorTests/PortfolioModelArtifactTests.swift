import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Portfolio model artifact")
struct PortfolioModelArtifactTests {

    @Test("scores deterministic linear utility from feature values")
    func scoresLinearUtility() throws {
        let artifact = PortfolioModelArtifact(
            modelVersion: "test-v1",
            trainingDatasetID: "dataset",
            armModels: [
                PortfolioArmModel(
                    arm: .graph,
                    coefficients: PortfolioLinearUtilityCoefficients(
                        intercept: 0.2,
                        operationWeights: [HomeAutomationOperationKind.executeDeviceCommand.rawValue: 0.1],
                        confidenceWeight: 0.5,
                        exactTemplateWeight: 0.1
                    )
                )
            ]
        )

        let score = try artifact.model(for: .graph).score(Self.features())

        #expect(abs(score - 0.85) < 0.0001)
        #expect(artifact.stableFingerprint.contains("test-v1"))
    }

    @Test("rejects incompatible feature schema")
    func rejectsSchemaMismatch() {
        let artifact = PortfolioModelArtifact(
            modelVersion: "test-v1",
            featureSchemaVersion: 99,
            trainingDatasetID: "dataset",
            armModels: []
        )

        #expect(throws: PortfolioModelArtifactError.self) {
            try artifact.validate()
        }
    }

    static func features(
        operationConfidence: Double = 0.9,
        language: PortfolioOODSignal = .inDomain,
        risk: HomeAutomationRiskLevel = .low
    ) -> PortfolioFeatureSnapshot {
        PortfolioFeatureSnapshot(
            operation: .present(.executeDeviceCommand, source: .injectedFixture),
            operationConfidence: .present(operationConfidence, source: .injectedFixture),
            languageOODSignal: .present(language, source: .injectedFixture),
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
            riskFloor: .present(risk, source: .injectedFixture),
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
