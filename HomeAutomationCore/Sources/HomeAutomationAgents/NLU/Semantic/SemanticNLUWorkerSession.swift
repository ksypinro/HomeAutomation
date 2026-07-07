import Foundation
import FoundationModels
import HomeAutomationCore
import os

public struct SemanticNLUWorkerSession: Sendable {
    private let classify: (@Sendable (String) async throws -> HomeSemanticNLUResult)?
    private let modelClassify: (@Sendable (String) async throws -> HomeSemanticNLUResult)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let modelCallPolicy: NLUModelCallPolicy
    private let modelSoftTimeoutNanoseconds: UInt64
    private let deviceTypeCatalog: [DeviceTypeCatalogEntry]
    private let logger = Logger(subsystem: "HomeAutomation", category: "NLU.SemanticNLUAgent")

    public init(
        classify: (@Sendable (String) async throws -> HomeSemanticNLUResult)? = nil,
        modelClassify: (@Sendable (String) async throws -> HomeSemanticNLUResult)? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        modelCallPolicy: NLUModelCallPolicy = .default,
        modelSoftTimeoutNanoseconds: UInt64 = NLUSoftTimeoutBudget.default.nluClassNanoseconds,
        deviceTypeCatalog: [DeviceTypeCatalogEntry]? = nil
    ) {
        self.classify = classify
        self.modelClassify = modelClassify
        self.foundationModelAvailability = foundationModelAvailability
        self.modelCallPolicy = modelCallPolicy
        self.modelSoftTimeoutNanoseconds = modelSoftTimeoutNanoseconds
        self.deviceTypeCatalog = deviceTypeCatalog ?? AvailableDeviceTypesTool.defaultCatalog()
    }

    public func classifySemanticNLU(
        _ text: String,
        modeOverride: NLUModelCallMode? = nil
    ) async throws -> HomeSemanticNLUResult {
        logger.debug("[Input] text: \(text, privacy: .public)")
        if let classify {
            let result = try await classify(text)
            logger.debug("[MockOutput] result: \(String(describing: result), privacy: .public)")
            return result
        }

        let effectivePolicy = modelCallPolicy.overridingMode(modeOverride)
        let deterministicState = AgentTextParser.deterministicState(for: text)
        let fallback = HomeSemanticNLUResult(
            intent: deterministicState.intent,
            deviceType: deterministicState.deviceType
        )
        logger.debug("[DeterministicFallback] result: \(String(describing: fallback), privacy: .public)")

        guard foundationModelAvailability() else {
            logger.info("[Availability] Foundation model unavailable, using deterministic semantic NLU fallback.")
            return fallback
        }

        guard effectivePolicy.shouldUseModel(task: .semanticNLU, deterministicState: deterministicState) else {
            logger.info("[Policy] Deterministic semantic NLU confidence meets threshold (mode: \(effectivePolicy.mode.rawValue, privacy: .public)); skipping model call.")
            return fallback
        }

        let catalogLines = deviceTypeCatalog
            .map { "- \($0.id) (\($0.displayName))" }
            .joined(separator: "\n")
        let instructionsText = """
        You are a smart-home semantic NLU classifier.

        Return one HomeSemanticNLUResult containing:
        - intent: broad smart-home intent families, ordered by likelihood.
        - deviceType: likely canonical device type identifiers.

        Valid device type identifiers:
        \(catalogLines)

        Rules:
        1. Return device type identifiers only from the valid list above. Never invent identifiers.
        2. Do not extract rooms, nicknames, numeric values, modes, or risk here.
        3. If no device type is mentioned or inferable, return an empty deviceTypes list.
        4. Keep internal values in English even when the input is multilingual.
        5. Treat Bixby placeholders such as device, location, mode, duration, temperature,
           deviceType, and numeric values as slots, not literal device names.
        6. Confidence values must be between 0.0 and 1.0.

        \(NLUInstructionContextProvider.intentFamilyContext(for: text))

        \(NLUInstructionContextProvider.deviceTypeContext(for: text))

        Examples:
        - "Turn on the lamp" -> intent power, deviceTypes ["light"]
        - "Set AC to 22 degrees" -> intent temperature, deviceTypes ["airConditioner"]
        - "Lock the front door" -> intent lockUnlock, deviceTypes ["lock"]
        - "Check the temperature" -> intent statusQuery, deviceTypes ["thermostat", "airConditioner"] when both are plausible
        - "What's the weather?" -> intent unsupported, deviceTypes []
        """

        let prompt: String
        if effectivePolicy.shouldProvideHint(task: .semanticNLU, deterministicState: deterministicState) {
            prompt = """
            \(text)

            Deterministic analysis suggests:
            - intent families: \(fallback.intent.topFamilies), confidence=\(fallback.intent.confidence)
            - device types: \(fallback.deviceType.deviceTypes), confidence=\(fallback.deviceType.confidence)
            Use this only as advisory grounding. Verify against the user command and valid device types.
            """
            logger.info("[Hint] Providing deterministic semantic NLU hint.")
        } else {
            prompt = text
        }

        logger.debug("[FoundationModelInput] System Instructions: \(instructionsText, privacy: .public)")
        logger.debug("[FoundationModelInput] Prompt: \(prompt, privacy: .public)")

        let session = LanguageModelSession(
            instructions: Instructions(instructionsText)
        )
        do {
            let modelClassify = self.modelClassify
            let result = try await withNLUModelSoftTimeout(
                agentID: .semanticNLU,
                timeoutNanoseconds: modelSoftTimeoutNanoseconds
            ) {
                if let modelClassify {
                    return try await modelClassify(prompt)
                }
                return try await FoundationModelCallRecorder.record(
                    agentID: AgentID.semanticNLU.rawValue,
                    policyMode: effectivePolicy.mode.rawValue,
                    modelAvailability: "available",
                    promptCharacterCount: instructionsText.count + prompt.count
                ) {
                    try await session.respond(
                        to: Prompt(prompt),
                        generating: HomeSemanticNLUResult.self
                    ).content
                }
            }
            logger.debug("[FoundationModelOutput] result: \(String(describing: result), privacy: .public)")
            return result
        } catch {
            logger.error("[FoundationModelError] error: \(error.localizedDescription, privacy: .public), using deterministic fallback.")
            return fallback
        }
    }
}
