import Foundation
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Portfolio feature snapshot")
struct PortfolioFeatureSnapshotTests {

    @Test("snapshot serializes deterministically and validates schema")
    func stableSerializationAndSchemaValidation() throws {
        let snapshot = makeSnapshot(extractionDurationMs: 12.5)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let first = try encoder.encode(snapshot)
        let second = try encoder.encode(snapshot)

        #expect(first == second)
        #expect(try JSONDecoder().decode(PortfolioFeatureSnapshot.self, from: first) == snapshot)
        #expect(throws: Never.self) {
            try snapshot.validateSchemaVersion()
        }
    }

    @Test("schema mismatch is explicit")
    func schemaMismatchIsExplicit() {
        let snapshot = makeSnapshot(featureSchemaVersion: PortfolioFeatureSchema.currentVersion + 1)

        #expect(throws: PortfolioFeatureSnapshotError.self) {
            try snapshot.validateSchemaVersion()
        }
    }

    @Test("missing flags distinguish unavailable from real zero")
    func missingFlagsDistinguishUnavailableFromZero() {
        let snapshot = PortfolioFeatureSnapshot(
            operation: .present(.unsupported, source: .deterministicParser),
            operationConfidence: .present(0.0, source: .deterministicParser),
            languageOODSignal: .present(.unknown, source: .fallbackDefault),
            textSizeBucket: .present(.empty, source: .deterministicParser),
            actionCount: .present(0, source: .deterministicDraftPipeline),
            conditionCount: .present(0, source: .deterministicDraftPipeline),
            minimumFieldConfidence: .missing(.notApplicable, source: .deterministicDraftPipeline),
            p50FieldConfidence: .missing(.notApplicable, source: .deterministicDraftPipeline),
            p90FieldConfidence: .missing(.notApplicable, source: .deterministicDraftPipeline),
            candidateCount: .present(0, source: .registrySnapshot),
            candidateTopTwoMargin: .present(0.0, source: .registrySnapshot),
            unsupportedFragmentCount: .present(0, source: .deterministicDraftPipeline),
            precedenceAmbiguity: .present(false, source: .deterministicDraftPipeline),
            riskFloor: .present(.low, source: .deterministicDraftPipeline),
            memoryReference: .present(false, source: .memoryDetector),
            exactTemplateMatch: .present(false, source: .deterministicDraftPipeline),
            foundationModelAvailability: .missing(.unavailable, source: .runtimeAvailability),
            ragAvailability: .present(.unavailable, source: .runtimeAvailability),
            gateDepth: .present(.none, source: .runtimeAvailability),
            warmStateHint: .present(.unknown, source: .runtimeAvailability),
            extractionDurationMs: 0
        )

        #expect(snapshot.actionCount.value == 0)
        #expect(snapshot.actionCount.missingReason == .notMissing)
        #expect(snapshot.foundationModelAvailability.value == nil)
        #expect(snapshot.foundationModelAvailability.missingReason == .unavailable)
    }

    private func makeSnapshot(
        featureSchemaVersion: Int = PortfolioFeatureSchema.currentVersion,
        extractionDurationMs: Double = 0
    ) -> PortfolioFeatureSnapshot {
        PortfolioFeatureSnapshot(
            featureSchemaVersion: featureSchemaVersion,
            operation: .present(.executeDeviceCommand, source: .deterministicParser),
            operationConfidence: .present(0.82, source: .deterministicParser),
            languageOODSignal: .present(.inDomain, source: .deterministicParser),
            textSizeBucket: .present(.short, source: .deterministicParser),
            actionCount: .present(1, source: .deterministicDraftPipeline),
            conditionCount: .present(0, source: .deterministicDraftPipeline),
            minimumFieldConfidence: .present(0.8, source: .deterministicDraftPipeline),
            p50FieldConfidence: .present(0.86, source: .deterministicDraftPipeline),
            p90FieldConfidence: .present(0.92, source: .deterministicDraftPipeline),
            candidateCount: .present(3, source: .registrySnapshot),
            candidateTopTwoMargin: .present(0.5, source: .registrySnapshot),
            unsupportedFragmentCount: .present(0, source: .deterministicDraftPipeline),
            precedenceAmbiguity: .present(false, source: .deterministicDraftPipeline),
            riskFloor: .present(.low, source: .deterministicDraftPipeline),
            memoryReference: .present(false, source: .memoryDetector),
            exactTemplateMatch: .present(true, source: .deterministicDraftPipeline),
            foundationModelAvailability: .present(.available, source: .runtimeAvailability),
            ragAvailability: .present(.unknown, source: .runtimeAvailability),
            gateDepth: .present(.unknown, source: .runtimeAvailability),
            warmStateHint: .present(.unknown, source: .runtimeAvailability),
            extractionDurationMs: extractionDurationMs
        )
    }
}
