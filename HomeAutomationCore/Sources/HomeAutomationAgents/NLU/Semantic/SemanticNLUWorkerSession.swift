import Foundation
import FoundationModels
import HomeAutomationCore
import os

public struct SemanticNLUWorkerSession: Sendable {
    private let classify: (@Sendable (String) async throws -> HomeSemanticNLUResult)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let modelCallPolicy: NLUModelCallPolicy
    private let deviceTypeCatalog: [DeviceTypeCatalogEntry]
    private let logger = Logger(subsystem: "HomeAutomation", category: "NLU.SemanticNLUAgent")

    public init(
        classify: (@Sendable (String) async throws -> HomeSemanticNLUResult)? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        modelCallPolicy: NLUModelCallPolicy = .default,
        deviceTypeCatalog: [DeviceTypeCatalogEntry]? = nil
    ) {
        self.classify = classify
        self.foundationModelAvailability = foundationModelAvailability
        self.modelCallPolicy = modelCallPolicy
        self.deviceTypeCatalog = deviceTypeCatalog ?? AvailableDeviceTypesTool.defaultCatalog()
    }

    public func classifySemanticNLU(_ text: String) async throws -> HomeSemanticNLUResult {
        logger.debug("[Input] text: \(text, privacy: .public)")
        if let classify {
            let result = try await classify(text)
            logger.debug("[MockOutput] result: \(String(describing: result), privacy: .public)")
            return result
        }

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

        let tool = AvailableDeviceTypesTool(catalog: deviceTypeCatalog)
        let instructionsText = """
        You are a smart-home semantic NLU classifier.

        Return one HomeSemanticNLUResult containing:
        - intent: broad smart-home intent families, ordered by likelihood.
        - deviceType: likely canonical device type identifiers.

        Rules:
        1. FIRST call the getAvailableDeviceTypes tool before producing deviceType.
        2. Return device type identifiers only from the tool results. Never invent identifiers.
        3. Do not extract rooms, nicknames, numeric values, modes, or risk here.
        4. If no device type is mentioned or inferable, return an empty deviceTypes list.
        5. Keep internal values in English even when the input is multilingual.
        6. Treat Bixby placeholders such as device, location, mode, duration, temperature,
           deviceType, and numeric values as slots, not literal device names.
        7. Confidence values must be between 0.0 and 1.0.

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
        if modelCallPolicy.shouldProvideHint(task: .semanticNLU, deterministicState: deterministicState) {
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

        let tracedInstructions = HomeAutomationToolTraceInstructions.append(to: instructionsText)
        let session = LanguageModelSession(
            tools: [tool],
            instructions: Instructions(tracedInstructions)
        )
        do {
            let result = try await FoundationModelCallRecorder.record(
                agentID: AgentID.semanticNLU.rawValue,
                policyMode: modelCallPolicy.mode.rawValue,
                modelAvailability: "available",
                promptCharacterCount: tracedInstructions.count + prompt.count,
                selectedToolNames: ["getAvailableDeviceTypes"]
            ) {
                try await session.respond(
                    to: Prompt(prompt),
                    generating: HomeSemanticNLUResult.self
                ).content
            }
            logger.debug("[FoundationModelOutput] result: \(String(describing: result), privacy: .public)")
            return result
        } catch {
            logger.error("[FoundationModelError] error: \(error.localizedDescription, privacy: .public), using deterministic fallback.")
            return fallback
        }
    }
}
