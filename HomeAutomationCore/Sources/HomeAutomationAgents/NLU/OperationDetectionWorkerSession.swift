import Foundation
import FoundationModels
import HomeAutomationCore
import os

/// Foundation Model-backed worker session for operation detection.
///
/// Replaces the pure rule-based `HomeOperationDetectionService.detect()` pattern
/// with a model-first approach where the rule-based result is provided as a hint.
public struct OperationDetectionWorkerSession: Sendable {
    private let detect: (@Sendable (String) async throws -> HomeOperationDetectionResult)?
    private let ruleDetect: @Sendable (String) -> HomeOperationDetectionResult
    private let foundationModelAvailability: @Sendable () -> Bool
    private let modelCallPolicy: NLUModelCallPolicy
    private let logger = Logger(subsystem: "HomeAutomation", category: "NLU.OperationDetection")

    public init(
        detect: (@Sendable (String) async throws -> HomeOperationDetectionResult)? = nil,
        ruleDetect: @escaping @Sendable (String) -> HomeOperationDetectionResult = { text in
            // Default: AgentTextParser deterministic operation classification
            let state = AgentTextParser.deterministicState(for: text)
            let normalized = text.lowercased()
            let automationTriggerKeywords = [
                "every day", "everyday", "daily", "every morning", "every evening",
                "every night", "every hour", "every minute", "each day", "weekdays",
                "weekends", "at 7", "at 8", "at 9", "when ", "whenever ", "if ",
                "schedule", "automation", "routine to", "from now on", "next time",
                "in similar situations", "remember this", "reminder"
            ]
            let hasScheduleTime = normalized.range(
                of: #"\bat\s+\d{1,2}(?::\d{2})?\s*(am|pm)?\b"#,
                options: .regularExpression
            ) != nil
            let isAutomationCreation = hasScheduleTime ||
                automationTriggerKeywords.contains { normalized.contains($0) }
            if isAutomationCreation {
                return HomeOperationDetectionResult(
                    domain: state.domain.domain,
                    operation: .automationCreation,
                    confidence: 0.82,
                    reason: "Deterministic: automation trigger or schedule signal detected."
                )
            }
            let domain = state.domain.domain
            if domain == .homeAutomation {
                return HomeOperationDetectionResult(
                    domain: domain,
                    operation: .executeDeviceCommand,
                    confidence: state.domain.confidence,
                    reason: "Deterministic: home automation device command."
                )
            }
            return HomeOperationDetectionResult(
                domain: domain,
                operation: .unsupported,
                confidence: state.domain.confidence,
                reason: "Deterministic: unsupported domain."
            )
        },
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        modelCallPolicy: NLUModelCallPolicy = .default
    ) {
        self.detect = detect
        self.ruleDetect = ruleDetect
        self.foundationModelAvailability = foundationModelAvailability
        self.modelCallPolicy = modelCallPolicy
    }

    public func detectOperation(_ text: String) async throws -> HomeOperationDetectionResult {
        logger.debug("[Input] text: \(text, privacy: .public)")

        // Mock path for testing
        if let detect {
            let result = try await detect(text)
            logger.debug("[MockOutput] result: \(String(describing: result), privacy: .public)")
            return result
        }

        // Compute rule-based result for hint and fallback
        let ruleResult = ruleDetect(text)
        logger.debug("[RuleHint] result: \(String(describing: ruleResult), privacy: .public)")

        // If FM unavailable, fall back to rule-based
        guard foundationModelAvailability() else {
            logger.info("[Availability] Foundation model unavailable, using rule-based result.")
            return ruleResult
        }

        let hintText: String
        if modelCallPolicy.mode == .modelFirstWithHint {
            hintText = """

            Rule-based analysis suggests: operation=\(ruleResult.operation.rawValue), \
            domain=\(ruleResult.domain), confidence=\(ruleResult.confidence), \
            reason="\(ruleResult.reason)". \
            Verify or correct this classification. Pay special attention to commands that \
            contain schedule triggers (times, recurrence) or conditional triggers (when/whenever/if) \
            as these should be classified as automationCreation rather than executeDeviceCommand.
            """
            logger.info("[Hint] Providing rule-based hint to model.")
        } else {
            hintText = ""
        }

        let instructionsText = """
        You are a smart‑home operation classifier.

        Your task: Given a user's command, return a single HomeOperationDetectionResult describing what the user wants to do.

        Output contract (the model must adhere to this when generating the typed result):
        - domain: `.homeAutomation` for supported operations, otherwise `.unsupported` for unrelated requests.
        - operation: exactly one of `.executeDeviceCommand`, `.automationCreation`, `.automationUpdate`, `.automationDeletion`, `.automationQuery`, `.sceneCreation`, `.routineExecution`, `.unsupported`.
        - confidence: a Double in [0.0, 1.0] reflecting certainty.
        - reason: one concise sentence explaining the key cues.

        Decision guide (apply in order):
        1) Automation deletion → if the command references an automation/rule/routine and uses delete/remove terms.
        2) Automation update → if it references an automation/rule/routine with update/change/edit/enable/disable terms.
        3) Automation query → questions about automations (show/list/what automations).
        4) Automation creation → if there is any schedule, trigger, or conditional cue together with an action.
           - Time cues: "at 7 am", "every day", "daily", "weekdays", explicit clock times.
           - Trigger cues: "when", "whenever", "if", "after", "before".
           - Conversational cues: "remember this/that", "from now on", "next time", "in similar situations".
           - Make sure user wants to do something if certain condition is met or a certain time is sceduled. 
        5) Routine/scene:
           - sceneCreation → creating/naming a new scene/routine grouping (e.g., "create a scene called movie time").
           - routineExecution → running an existing scene/routine by name (e.g., "run movie time").
        6) Execute device command → if user wants to control a device. example turning it on or increasing its temperature. But there should not be any condition or trigger.
        7) Unsupported → if not related to home automation or devices.

        Tie‑breakers:
        - If BOTH a device action and a schedule/trigger/condition are present, choose `.automationCreation`.
        - Prefer precision: if ambiguous between automation vs direct control and no clear schedule/trigger, choose `.executeDeviceCommand`.
        - If the text clearly refers to automations but neither update/delete/query words appear, prefer `.automationCreation` when a future/conditional intent is implied.
        - if your confidence is below .9 then check I have used my knowledge and found this \(hintText). prioretize it.

        Confidence calibration:
        - 0.90–1.00 when explicit keywords strongly indicate the category.
        - 0.75–0.89 when likely but with minor ambiguity.
        - 0.50–0.74 when ambiguous; explain why in `reason`.

        Examples:
        - "Delete the bedtime routine" → operation: `.automationDeletion`, domain: `.homeAutomation`, confidence: 0.90
        - "Disable the kitchen lights automation" → operation: `.automationUpdate`, domain: `.homeAutomation`, confidence: 0.86
        - "What automations are running?" → operation: `.automationQuery`, domain: `.homeAutomation`, confidence: 0.86
        - "Every day at 7am turn on the heater" → operation: `.automationCreation`, domain: `.homeAutomation`, confidence: 0.92
        - "When I arrive home, open the garage" → operation: `.automationCreation`, domain: `.homeAutomation`, confidence: 0.90
        - "Create a scene called movie time" → operation: `.sceneCreation`, domain: `.homeAutomation`, confidence: 0.88
        - "Run movie time" → operation: `.routineExecution`, domain: `.homeAutomation`, confidence: 0.90
        - "Turn on the living room lights" → operation: `.executeDeviceCommand`, domain: `.homeAutomation`, confidence: 0.85
        - "Set AC to 22 degrees" → operation: `.executeDeviceCommand`, domain: `.homeAutomation`, confidence: 0.90
        - "What's the weather?" → operation: `.unsupported`, domain: `.unsupported`, confidence: 0.90
        """
        logger.debug("[FoundationModelInput] System Instructions: \(instructionsText.prefix(200), privacy: .public)...")
        logger.debug("[FoundationModelInput] Prompt: \(text, privacy: .public)")

        let session = LanguageModelSession(instructions: Instructions(instructionsText))
        do {
            let prompt = text + hintText
            let modelResult = try await session.respond(
                to: Prompt(prompt),
                generating: HomeOperationDetectionResult.self
            ).content
            logger.debug("[FoundationModelOutput] result: \(String(describing: modelResult), privacy: .public)")

            // Safety preference: if rule says automationCreation but model says executeDeviceCommand,
            // prefer automationCreation to avoid silently ignoring triggers/schedules.
            if ruleResult.operation == .automationCreation &&
               modelResult.operation == .executeDeviceCommand &&
               ruleResult.confidence >= 0.80 {
                logger.info("[SafetyPreference] Rule detected automationCreation with high confidence; preferring rule to avoid ignoring triggers.")
                return HomeOperationDetectionResult(
                    domain: ruleResult.domain,
                    operation: .automationCreation,
                    confidence: max(ruleResult.confidence, modelResult.confidence * 0.9),
                    reason: "Safety preference: rule detected automation triggers that model missed. Rule reason: \(ruleResult.reason)"
                )
            }

            return modelResult
        } catch {
            logger.error("[FoundationModelError] error: \(error.localizedDescription, privacy: .public), using rule-based fallback.")
            return ruleResult
        }
    }
}
