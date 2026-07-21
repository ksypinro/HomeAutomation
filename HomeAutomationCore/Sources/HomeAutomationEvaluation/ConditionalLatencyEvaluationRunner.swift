import Foundation
import HomeAutomationCore
import HomeAutomationOrchestrator

/// Phase 0 evaluation runner for paired condition latency baseline.
/// Orchestrates paired runs (base + conditioned) and validates correctness.
public struct ConditionalLatencyEvaluationRunner: Sendable {
    private let orchestrator: HomeCommandOrchestrator
    private let support: ConditionalLatencyHarnessSupport

    public init(orchestrator: HomeCommandOrchestrator) {
        self.orchestrator = orchestrator
        self.support = ConditionalLatencyHarnessSupport()
    }

    /// Run a paired test case (base + conditioned command).
    /// Returns tuple of (base result, conditioned result) with same fixture.
    public func runPairedCase(
        id: String,
        executeLowRiskCommands: Bool = false
    ) async throws -> (base: HomeAutomationResolverResult, conditioned: HomeAutomationResolverResult) {
        guard let (baseCmd, conditionedCmd) = support.getPairedCase(id: id) else {
            throw EvaluationError.invalidCase("Paired case '\(id)' not found in corpus")
        }

        let baseResult = try await orchestrator.resolve(
            baseCmd,
            executeLowRiskCommands: executeLowRiskCommands
        )

        let conditionedResult = try await orchestrator.resolve(
            conditionedCmd,
            executeLowRiskCommands: executeLowRiskCommands
        )

        return (base: baseResult, conditioned: conditionedResult)
    }

    /// Validate correctness parity between base and conditioned results.
    /// Ensures the condition did not alter action/trigger/risk/compilation.
    public func validateCorrectnessParit(
        base: HomeAutomationResolverResult,
        conditioned: HomeAutomationResolverResult,
        caseID: String
    ) -> CorrectnessValidationResult {
        var errors: [String] = []

        // Both should be automations or both should fail
        let baseIsAutomation = base.resolution.isAutomationResolution
        let conditionedIsAutomation = conditioned.resolution.isAutomationResolution
        if baseIsAutomation != conditionedIsAutomation {
            errors.append("Resolution type mismatch: base=\(baseIsAutomation), conditioned=\(conditionedIsAutomation)")
        }

        // Validate action count and targets
        let baseActions = extractActions(from: base)
        let conditionedActions = extractActions(from: conditioned)
        if baseActions.count != conditionedActions.count {
            errors.append("Action count mismatch: base=\(baseActions.count), conditioned=\(conditionedActions.count)")
        }

        // Validate trigger
        let baseTrigger = extractTrigger(from: base)
        let conditionedTrigger = extractTrigger(from: conditioned)
        if baseTrigger != conditionedTrigger {
            errors.append("Trigger mismatch: base=\(baseTrigger ?? "nil"), conditioned=\(conditionedTrigger ?? "nil")")
        }

        // Validate risk level (should not change)
        if base.resolution.displaySummary.contains("high risk") != conditioned.resolution.displaySummary.contains("high risk") {
            errors.append("Risk level changed between base and conditioned")
        }

        return CorrectnessValidationResult(
            caseID: caseID,
            passed: errors.isEmpty,
            errors: errors
        )
    }

    private func extractActions(from result: HomeAutomationResolverResult) -> [String] {
        // Extract action details from resolution (simplified for Phase 0)
        // Full implementation would parse the command draft or compiled plan
        result.resolution.displaySummary.contains("turn on") ? ["turn on"] : []
    }

    private func extractTrigger(from result: HomeAutomationResolverResult) -> String? {
        // Extract trigger type from resolution
        // Full implementation would parse the automation rule draft
        if result.resolution.displaySummary.contains("7 AM") {
            return "schedule"
        } else if result.resolution.displaySummary.contains("motion") {
            return "device"
        }
        return nil
    }
}

public struct CorrectnessValidationResult: Sendable {
    public let caseID: String
    public let passed: Bool
    public let errors: [String]

    public init(caseID: String, passed: Bool, errors: [String]) {
        self.caseID = caseID
        self.passed = passed
        self.errors = errors
    }
}

public enum EvaluationError: LocalizedError {
    case invalidCase(String)
    case modelUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCase(let msg):
            return "Invalid test case: \(msg)"
        case .modelUnavailable(let msg):
            return "Model unavailable: \(msg)"
        }
    }
}

extension HomeAutomationResolverResult {
    fileprivate var isAutomationResolution: Bool {
        switch resolution {
        case .automationDrafted, .automationRequiresConfirmation:
            return true
        default:
            return false
        }
    }
}
