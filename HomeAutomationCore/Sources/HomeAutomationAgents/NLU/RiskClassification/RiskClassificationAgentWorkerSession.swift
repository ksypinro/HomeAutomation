import Foundation
import FoundationModels
import HomeAutomationCore
import os

public struct RiskClassificationAgentWorkerSession: Sendable {
    private let classify: (@Sendable (String) async throws -> HomeRiskClassificationResult)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let modelCallPolicy: NLUModelCallPolicy
    private let logger = Logger(subsystem: "HomeAutomation", category: "NLU.RiskClassificationAgent")

    public init(
        classify: (@Sendable (String) async throws -> HomeRiskClassificationResult)? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        modelCallPolicy: NLUModelCallPolicy = .default
    ) {
        self.classify = classify
        self.foundationModelAvailability = foundationModelAvailability
        self.modelCallPolicy = modelCallPolicy
    }

    public func classifyRisk(_ text: String) async throws -> HomeRiskClassificationResult {
        logger.debug("[Input] text: \(text, privacy: .public)")
        if let classify {
            let result = try await classify(text)
            logger.debug("[MockOutput] result: \(String(describing: result), privacy: .public)")
            return result
        }
        let deterministicState = AgentTextParser.deterministicState(for: text)
        let fallback = deterministicState.risk
        logger.debug("[DeterministicFallback] result: \(String(describing: fallback), privacy: .public)")
        guard foundationModelAvailability() else {
            logger.info("[Availability] Foundation model unavailable, using fallback.")
            return fallback
        }

        let hintText: String
        if modelCallPolicy.shouldProvideHint(task: .riskClassification, deterministicState: deterministicState) {
            hintText = """

            Deterministic analysis suggests: riskLevel=\(fallback.riskLevel), \
            requiresConfirmation=\(fallback.requiresConfirmation), \
            reason=\(fallback.reason), confidence=\(fallback.confidence). \
            Verify or correct. Note: you may escalate risk but should not downgrade \
            high or critical risk assessed by the deterministic system.
            """
            logger.info("[Hint] Providing deterministic risk hint to model (riskLevel: \(String(describing: fallback.riskLevel), privacy: .public), confidence: \(fallback.confidence, privacy: .public)).")
        } else {
            hintText = ""
        }

        let instructionsText = """
        Classify the risk level of this home-automation command.
        Unlocking, opening entry points, disabling cameras, starting ovens, or changing security state is high risk.
        Low risk includes lights, simple status queries, and harmless brightness changes.
        Temperature changes and appliances are medium risk.
        Critical risk includes security bypasses or unsafe automation.
        """
        logger.debug("[FoundationModelInput] System Instructions: \(instructionsText, privacy: .public)")
        logger.debug("[FoundationModelInput] Prompt: \(text, privacy: .public)")

        let session = LanguageModelSession(instructions: Instructions(instructionsText))
        do {
            let prompt = text + hintText
            let modelResult = try await FoundationModelCallRecorder.record(
                agentID: AgentID.riskClassification.rawValue,
                policyMode: modelCallPolicy.mode.rawValue,
                modelAvailability: "available",
                promptCharacterCount: instructionsText.count + prompt.count
            ) {
                try await session.respond(to: Prompt(prompt), generating: HomeRiskClassificationResult.self).content
            }
            logger.debug("[FoundationModelOutput] result: \(String(describing: modelResult), privacy: .public)")
            // Safety floor merge: deterministic high/critical can never be downgraded by model
            let merged = Self.mergeWithSafetyFloor(model: modelResult, rule: fallback)
            if merged.riskLevel != modelResult.riskLevel {
                logger.info("[SafetyFloor] Model suggested \(String(describing: modelResult.riskLevel), privacy: .public) but deterministic floor enforced \(String(describing: merged.riskLevel), privacy: .public).")
            }
            return merged
        } catch {
            logger.error("[FoundationModelError] error: \(error.localizedDescription, privacy: .public), using deterministic fallback.")
            return fallback
        }
    }

    /// Merges model and rule-based risk results using max(ruleRisk, modelRisk).
    /// The deterministic high/critical assessment is a safety floor that the model cannot lower.
    public static func mergeWithSafetyFloor(
        model: HomeRiskClassificationResult,
        rule: HomeRiskClassificationResult
    ) -> HomeRiskClassificationResult {
        let ruleOrdinal = riskOrdinal(rule.riskLevel)
        let modelOrdinal = riskOrdinal(model.riskLevel)

        if ruleOrdinal > modelOrdinal {
            // Deterministic assessed higher risk — enforce safety floor
            return HomeRiskClassificationResult(
                riskLevel: rule.riskLevel,
                requiresConfirmation: rule.requiresConfirmation || model.requiresConfirmation,
                reason: "Safety floor: \(rule.reason) (model suggested \(model.riskLevel))",
                confidence: max(rule.confidence, model.confidence)
            )
        }

        // Model matched or escalated — use model result, but merge confirmation flags
        return HomeRiskClassificationResult(
            riskLevel: model.riskLevel,
            requiresConfirmation: model.requiresConfirmation || rule.requiresConfirmation,
            reason: model.reason,
            confidence: model.confidence
        )
    }

    private static func riskOrdinal(_ level: HomeAutomationRiskLevel) -> Int {
        switch level {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .critical: return 3
        }
    }
}
