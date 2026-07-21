import HomeAutomationEvaluation
import Testing

@Suite("Adaptive release gate report")
struct AdaptiveReleaseGateReportTests {

    @Test("fails closed when hardware or rollback evidence is missing")
    func failsClosedWithoutEvidence() {
        let report = AdaptiveReleaseGateReport.make(
            configVersion: "phase10",
            rolloutMode: "activeLearned",
            rollbackDrillPassed: false,
            hardwareGatePassed: false
        )

        #expect(!report.passed)
        #expect(report.results.contains { $0.kind == .rollbackDrill && !$0.passed })
        #expect(report.results.contains { $0.kind == .hardwareColdWarm && !$0.passed })
    }

    @Test("shadow rollout satisfies holdback gate")
    func shadowRolloutSatisfiesHoldback() {
        let report = AdaptiveReleaseGateReport.make(
            configVersion: "phase10",
            rolloutMode: "shadowLearned",
            rollbackDrillPassed: true,
            hardwareGatePassed: true
        )

        #expect(report.results.first { $0.kind == .canaryHoldback }?.passed == true)
    }
}
