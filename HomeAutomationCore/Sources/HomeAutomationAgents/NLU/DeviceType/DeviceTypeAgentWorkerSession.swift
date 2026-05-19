import Foundation
import FoundationModels
import HomeAutomationCore
import os

public struct DeviceTypeAgentWorkerSession: Sendable {
    private let classify: (@Sendable (String) async throws -> HomeDeviceTypeResult)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let deviceTypeCatalog: [DeviceTypeCatalogEntry]
    private let logger = Logger(subsystem: "HomeAutomation", category: "NLU.DeviceTypeAgent")

    public init(
        classify: (@Sendable (String) async throws -> HomeDeviceTypeResult)? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        deviceTypeCatalog: [DeviceTypeCatalogEntry]? = nil
    ) {
        self.classify = classify
        self.foundationModelAvailability = foundationModelAvailability
        self.deviceTypeCatalog = deviceTypeCatalog ?? AvailableDeviceTypesTool.defaultCatalog()
    }

    public func classifyDeviceType(_ text: String) async throws -> HomeDeviceTypeResult {
        logger.debug("[Input] text: \(text, privacy: .public)")

        if let classify {
            let result = try await classify(text)
            logger.debug("[MockOutput] result: \(String(describing: result), privacy: .public)")
            return result
        }

        guard foundationModelAvailability() else {
            let fallback = HomeDeviceTypeResult(deviceTypes: [], confidence: 0.0)
            logger.info("[Availability] Foundation model unavailable, returning empty fallback.")
            return fallback
        }

        let tool = AvailableDeviceTypesTool(catalog: deviceTypeCatalog)

        let systemInstructions = """
        You are a smart-home device type classifier.

        Your task: Given a user's voice command, determine which smart-home device type(s) \
        the user is referring to.

        Rules:
        1. FIRST call the getAvailableDeviceTypes tool to see all valid device type identifiers.
        2. Return ONLY identifiers from the tool results. Never invent or guess identifiers.
        3. If the command mentions a specific device (e.g. "lamp", "AC", "thermostat"), \
           return the matching device type identifier.
        4. If the command uses a generic term (e.g. "turn on the light"), map it to the \
           correct canonical type (e.g. "light").
        5. If multiple device types could match (e.g. "check the temperature" could be a \
           thermostat or air conditioner), return all plausible types ordered by likelihood.
        6. If no device type is mentioned or inferable, return an empty list.
        7. Set confidence between 0.0 and 1.0 based on how certain you are about the classification.
        8. Aliases and descriptions from the tool help you match informal language to formal identifiers.

        Examples:
        - "Turn on the lamp" -> deviceTypes: ["light"], confidence: 0.95
        - "Set AC to 22 degrees" -> deviceTypes: ["airConditioner"], confidence: 0.95
        - "Lock the front door" -> deviceTypes: ["lock"], confidence: 0.95
        - "Check the temperature" -> deviceTypes: ["thermostat", "airConditioner"], confidence: 0.75
        - "What's the weather?" -> deviceTypes: [], confidence: 0.90
        - "Start the vacuum" -> deviceTypes: ["robotCleaner"], confidence: 0.90
        - "Open the blinds" -> deviceTypes: ["blind"], confidence: 0.95
        - "Run movie time" -> deviceTypes: ["routine"], confidence: 0.90
        """

        logger.debug("[FoundationModelInput] System Instructions (length): \(systemInstructions.count)")
        logger.debug("[FoundationModelInput] Prompt: \(text, privacy: .public)")

        let session = LanguageModelSession(
            tools: [tool],
            instructions: Instructions(systemInstructions)
        )

        let deterministicHint: String
        let deterministicState = AgentTextParser.deterministicState(for: text)
        let deterministicTypes = deterministicState.deviceType.deviceTypes
        if !deterministicTypes.isEmpty {
            deterministicHint = "\n\nDeterministic keyword analysis suggests device types: \(deterministicTypes). Use this only as auxiliary context; call the tool first and confirm against valid identifiers."
            logger.info("[Hint] Providing deterministic device type hint: \(deterministicTypes, privacy: .public).")
        } else {
            deterministicHint = ""
        }

        let prompt = text + deterministicHint

        do {
            let result = try await session.respond(
                to: Prompt(prompt),
                generating: HomeDeviceTypeResult.self
            ).content
            logger.debug("[FoundationModelOutput] result: \(String(describing: result), privacy: .public)")
            return result
        } catch {
            logger.error("[FoundationModelError] error: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
