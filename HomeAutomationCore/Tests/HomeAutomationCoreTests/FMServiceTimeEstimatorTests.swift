import HomeAutomationCore
import Testing

@Suite("Foundation Model service-time estimator")
struct FMServiceTimeEstimatorTests {

    @Test("Estimator reports percentile summaries from service samples")
    func estimatorReportsPercentiles() async {
        let estimator = FMServiceTimeEstimator(fallbackMs: 99)
        let key = FMServiceTimeEstimatorKey(
            agentID: "semanticNLU",
            jobKind: .semanticNLU,
            priority: .interactive
        )

        await estimator.recordServiceTime(milliseconds: 10, key: key)
        await estimator.recordServiceTime(milliseconds: 20, key: key)
        await estimator.recordServiceTime(milliseconds: 30, key: key)
        await estimator.recordServiceTime(milliseconds: 40, key: key)

        let estimate = await estimator.estimate(for: key)
        #expect(estimate.sampleCount == 4)
        #expect(!estimate.usedFallback)
        #expect(estimate.p50Ms == 25)
        #expect(estimate.p75Ms == 32.5)
        #expect(estimate.p90Ms == 37)
    }

    @Test("Estimator uses fallback when no service samples exist")
    func estimatorUsesFallbackWithoutSamples() async {
        let estimator = FMServiceTimeEstimator(fallbackMs: 123)
        let estimate = await estimator.estimate(for: FMServiceTimeEstimatorKey(
            agentID: "draftVerifier",
            jobKind: .verifier,
            priority: .pipeline
        ))

        #expect(estimate.usedFallback)
        #expect(estimate.sampleCount == 0)
        #expect(estimate.p90Ms == 123)
    }
}
