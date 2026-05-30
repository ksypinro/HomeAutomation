import Foundation
import FoundationModels
import HomeAutomationCore
import os

/// Foundation Model-backed worker session for operation detection.
///
/// Uses a model-first approach where deterministic operation detection is exposed
/// as an optional tool instead of being injected into the prompt as a fixed hint.
public struct OperationDetectionWorkerSession: Sendable {
    private let detect: (@Sendable (String) async throws -> HomeOperationDetectionResult)?
    private let detectRouting: (@Sendable (String) async throws -> HomeOperationRoutingResult)?
    private let ruleDetect: @Sendable (String) -> HomeOperationDetectionResult
    private let foundationModelAvailability: @Sendable () -> Bool
    private let modelCallPolicy: NLUModelCallPolicy
    private let logger = Logger(subsystem: "HomeAutomation", category: "NLU.OperationDetection")

    public init(
        detect: (@Sendable (String) async throws -> HomeOperationDetectionResult)? = nil,
        detectRouting: (@Sendable (String) async throws -> HomeOperationRoutingResult)? = nil,
        ruleDetect: @escaping @Sendable (String) -> HomeOperationDetectionResult = { text in
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
        self.detectRouting = detectRouting
        self.ruleDetect = ruleDetect
        self.foundationModelAvailability = foundationModelAvailability
        self.modelCallPolicy = modelCallPolicy
    }

    public func detectOperation(_ text: String) async throws -> HomeOperationRoutingResult {
        logger.debug("[Input] text: \(text, privacy: .public)")

        if let detectRouting {
            let result = try await detectRouting(text)
            logger.debug("[MockOutput] result: \(String(describing: result), privacy: .public)")
            return normalizedRoutingResult(result, text: text, semanticResult: ruleDetect(text))
        }

        if let detect {
            let result = try await detect(text)
            logger.debug("[MockOutput] result: \(String(describing: result), privacy: .public)")
            return routingFallback(text: text, operation: result)
        }

        guard foundationModelAvailability() else {
            let semanticResult = ruleDetect(text)
            logger.info("[Availability] Foundation model unavailable, using semantic analyzer result.")
            logger.debug("[SemanticAnalyzerFallback] result: \(String(describing: semanticResult), privacy: .public)")
            return routingFallback(text: text, operation: semanticResult)
        }

        let semanticAnalyzerTool = OperationSemanticAnalyzerTool(commandText: text, analyze: ruleDetect)

        let instructionsText = """
        You are a smart-home operation, language, and domain routing classifier.

        Your task: Given a user's command, return a single HomeOperationRoutingResult.
        The result contains:
        - operation: a HomeOperationDetectionResult describing what the user wants to do.
        - language: a HomeLanguageDetectionResult describing the command language.
        - domain: a HomeDomainClassificationResult describing the same domain as operation.domain.

        You have access to the analyzeOperationSemantics tool. This tool runs a deterministic semantic analyzer
        and returns a suggested operation. Tool use is optional:
        - Classify independently from the user command first.
        - Call the tool when the command is ambiguous, conversational, compound, or you want a second semantic reading.
        - Treat the tool as advisory. You may agree with it or override it when the user text supports a better answer.

        Output contract:
        - operation.domain: `.homeAutomation` for supported operations, otherwise `.unsupported` for unrelated requests.
        - operation.operation: exactly one of `.executeDeviceCommand`, `.automationCreation`, `.automationUpdate`, `.automationDeletion`, `.automationQuery`, `.sceneCreation`, `.routineExecution`, `.unsupported`.
        - operation.confidence: a Double in [0.0, 1.0] reflecting certainty.
        - operation.reason: one concise sentence explaining the key cues.
        - language.languageCode: BCP-47-style code such as en, es, fr, ja, bn, or mixed_bn_en.
        - language.isMixedLanguage: true when the command mixes languages.
        - language.unsupportedLanguageLikely: true only when language support is likely poor.
        - domain.domain must match operation.domain.
        - domain.confidence should reflect domain confidence, not operation-specific confidence.

        Decision guide:
        1. Automation deletion: automation/rule/routine plus delete/remove terms.
        2. Automation update: automation/rule/routine plus update/change/edit/enable/disable terms.
        3. Automation query: questions about automations.
        4. Automation creation: schedule, trigger, or conditional cue together with an action.
        5. Scene creation or routine execution when the user creates or runs a named scene/routine.
        6. Execute device command when the user controls a device without a condition or trigger.
        7. Unsupported when unrelated to home automation.

        Tie-breakers:
        - If both a device action and schedule/trigger/condition are present, choose `.automationCreation`.
        - Conversational phrases like "remember this", "from now on", and "in similar situations" can indicate automation creation.

        Examples:
        - "Delete the bedtime routine" -> `.automationDeletion`
        - "Disable the kitchen lights automation" -> `.automationUpdate`
        - "What automations are running?" -> `.automationQuery`
        - "Every day at 7am turn on the heater" -> `.automationCreation`
        - "When I arrive home, open the garage" -> `.automationCreation`
        - "Create a scene called movie time" -> `.sceneCreation`
        - "Run movie time" -> `.routineExecution`
        - "Turn on the living room lights" -> `.executeDeviceCommand`
        - "What's the weather?" -> `.unsupported`
        """
        logger.debug("[FoundationModelInput] System Instructions: \(instructionsText.prefix(200), privacy: .public)...")
        logger.debug("[FoundationModelInput] Prompt: \(text, privacy: .public)")

        let session = LanguageModelSession(
            tools: [semanticAnalyzerTool],
            instructions: Instructions(instructionsText)
        )
        do {
            let prompt = "User command:\n\(text)"
            let modelResult = try await FoundationModelCallRecorder.record(
                agentID: AgentID.operationDetection.rawValue,
                policyMode: modelCallPolicy.mode.rawValue,
                modelAvailability: "available",
                promptCharacterCount: instructionsText.count + prompt.count,
                selectedToolNames: ["analyzeHomeOperation"]
            ) {
                try await session.respond(
                    to: Prompt(prompt),
                    generating: HomeOperationRoutingResult.self
                ).content
            }
            logger.debug("[FoundationModelOutput] result: \(String(describing: modelResult), privacy: .public)")

            let semanticResult = ruleDetect(text)
            logger.debug("[SemanticAnalyzerSafetyCheck] result: \(String(describing: semanticResult), privacy: .public)")
            return normalizedRoutingResult(modelResult, text: text, semanticResult: semanticResult)
        } catch {
            let semanticResult = ruleDetect(text)
            logger.error("[FoundationModelError] error: \(error.localizedDescription, privacy: .public), using semantic analyzer fallback.")
            return routingFallback(text: text, operation: semanticResult)
        }
    }

    private func routingFallback(
        text: String,
        operation: HomeOperationDetectionResult
    ) -> HomeOperationRoutingResult {
        let state = AgentTextParser.deterministicState(for: text)
        let domain = HomeDomainClassificationResult(
            domain: operation.domain,
            confidence: max(state.domain.confidence, operation.confidence)
        )
        return HomeOperationRoutingResult(
            operation: operation,
            language: state.language,
            domain: domain
        )
    }

    private func normalizedRoutingResult(
        _ result: HomeOperationRoutingResult,
        text: String,
        semanticResult: HomeOperationDetectionResult
    ) -> HomeOperationRoutingResult {
        var operation = result.operation
        if semanticResult.operation == .automationCreation &&
            operation.operation == .executeDeviceCommand &&
            semanticResult.confidence >= 0.80 {
            logger.info("[SafetyPreference] Semantic analyzer detected automationCreation with high confidence; preferring it to avoid ignoring triggers.")
            operation = HomeOperationDetectionResult(
                domain: semanticResult.domain,
                operation: .automationCreation,
                confidence: max(semanticResult.confidence, operation.confidence * 0.9),
                reason: "Safety preference: semantic analyzer detected automation triggers that model missed. Analyzer reason: \(semanticResult.reason)"
            )
        }

        let fallback = AgentTextParser.deterministicState(for: text)
        let language = result.language.languageCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallback.language
            : result.language
        let domain = HomeDomainClassificationResult(
            domain: operation.domain,
            confidence: result.domain.domain == operation.domain
                ? result.domain.confidence
                : max(result.domain.confidence * 0.8, operation.confidence)
        )
        return HomeOperationRoutingResult(
            operation: operation,
            language: language,
            domain: domain
        )
    }
}
