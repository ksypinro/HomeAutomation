import Foundation
import FoundationModels
import HomeAutomationCore

public struct HomeAgentWorkerOverrides: Sendable {
    public let detectLanguage: (@Sendable (String) async throws -> HomeLanguageDetectionResult)?
    public let classifyDomain: (@Sendable (String) async throws -> HomeDomainClassificationResult)?
    public let classifyIntentFamily: (@Sendable (String) async throws -> HomeIntentFamilyResult)?
    public let classifyDeviceType: (@Sendable (String) async throws -> HomeDeviceTypeResult)?
    public let extractSlots: (@Sendable (String) async throws -> HomeSlotExtractionResult)?
    public let classifyRisk: (@Sendable (String) async throws -> HomeRiskClassificationResult)?

    public init(
        detectLanguage: (@Sendable (String) async throws -> HomeLanguageDetectionResult)? = nil,
        classifyDomain: (@Sendable (String) async throws -> HomeDomainClassificationResult)? = nil,
        classifyIntentFamily: (@Sendable (String) async throws -> HomeIntentFamilyResult)? = nil,
        classifyDeviceType: (@Sendable (String) async throws -> HomeDeviceTypeResult)? = nil,
        extractSlots: (@Sendable (String) async throws -> HomeSlotExtractionResult)? = nil,
        classifyRisk: (@Sendable (String) async throws -> HomeRiskClassificationResult)? = nil
    ) {
        self.detectLanguage = detectLanguage
        self.classifyDomain = classifyDomain
        self.classifyIntentFamily = classifyIntentFamily
        self.classifyDeviceType = classifyDeviceType
        self.extractSlots = extractSlots
        self.classifyRisk = classifyRisk
    }
}

public struct HomeAgentWorkerSessionSupport: Sendable {
    private let foundationModelAvailability: @Sendable () -> Bool
    private let overrides: HomeAgentWorkerOverrides

    public init(
        overrides: HomeAgentWorkerOverrides = HomeAgentWorkerOverrides(),
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        }
    ) {
        self.overrides = overrides
        self.foundationModelAvailability = foundationModelAvailability
    }

    public func detectLanguage(_ text: String) async throws -> HomeLanguageDetectionResult {
        if let override = overrides.detectLanguage {
            return try await override(text)
        }
        let fallback = AgentTextParser.deterministicState(for: text, confidence: 0.42).language
        guard foundationModelAvailability() else { return fallback }

        let session = LanguageModelSession(instructions: Instructions("""
        Detect the language of this user command.
        Return compact structured output only.
        Use BCP-47-style language codes such as en, es, fr, ja, bn, or mixed_bn_en.
        """))
        return try await session.respond(to: Prompt(text), generating: HomeLanguageDetectionResult.self).content
    }

    public func classifyDomain(_ text: String) async throws -> HomeDomainClassificationResult {
        if let override = overrides.classifyDomain {
            return try await override(text)
        }
        let fallback = AgentTextParser.deterministicState(for: text, confidence: 0.42).domain
        guard foundationModelAvailability() else { return fallback }

        let session = LanguageModelSession(instructions: Instructions("""
        Decide whether the text is a smart-home or home-automation command.
        Do not resolve devices. Classify only the domain.
        """))
        return try await session.respond(to: Prompt(text), generating: HomeDomainClassificationResult.self).content
    }

    public func classifyIntentFamily(_ text: String) async throws -> HomeIntentFamilyResult {
        if let override = overrides.classifyIntentFamily {
            return try await override(text)
        }
        let fallback = AgentTextParser.deterministicState(for: text, confidence: 0.42).intent
        guard foundationModelAvailability() else { return fallback }

        let session = LanguageModelSession(instructions: Instructions("""
        Classify the command into broad smart-home intent families.
        Return the most likely families first. Do not choose a specific device.

        \(HomeBixbyCommandCatalog.instructionSummary)
        """))
        return try await session.respond(to: Prompt(text), generating: HomeIntentFamilyResult.self).content
    }

    public func classifyDeviceType(_ text: String) async throws -> HomeDeviceTypeResult {
        if let override = overrides.classifyDeviceType {
            return try await override(text)
        }
        let fallback = AgentTextParser.deterministicState(for: text, confidence: 0.42).deviceType
        guard foundationModelAvailability() else { return fallback }

        let session = LanguageModelSession(instructions: Instructions("""
        Extract likely smart-home device types mentioned by the user.
        Use stable internal English identifiers such as light, airConditioner, thermostat, fan, lock, garageDoor, blind,
        contactSensor, motionSensor, airPurifier, airQualityDetector, tv, speaker, washer, dryer, oven, robotCleaner,
        camera, valve, waterSensor, smokeDetector, routine.
        Also use the expanded cross-client catalog identifiers below when relevant.
        \(HomeAutomationKnowledgeBase.instructionSummary)
        Bixby command placeholders such as Device, deviceType, and location are slots, not device names.
        Return an empty list if no type is mentioned.
        """))
        return try await session.respond(to: Prompt(text), generating: HomeDeviceTypeResult.self).content
    }

    public func extractSlots(_ text: String) async throws -> HomeSlotExtractionResult {
        if let override = overrides.extractSlots {
            return try await override(text)
        }
        let fallback = AgentTextParser.deterministicState(for: text, confidence: 0.42).slots
        guard foundationModelAvailability() else { return fallback }

        let session = LanguageModelSession(instructions: Instructions("""
        Extract rooms, device nicknames, values, units, durations, and modes from a smart-home command.
        Keep internal values in English even when the input is multilingual.
        Do not resolve devices or commands.
        Understand Bixby Home Studio slot language: device, deviceType, location, mode, predefinedMode, temperature,
        duration, number, compartment, and channel should be extracted when present.
        """))
        return try await session.respond(to: Prompt(text), generating: HomeSlotExtractionResult.self).content
    }

    public func classifyRisk(_ text: String) async throws -> HomeRiskClassificationResult {
        if let override = overrides.classifyRisk {
            return try await override(text)
        }
        let fallback = AgentTextParser.deterministicState(for: text, confidence: 0.42).risk
        guard foundationModelAvailability() else { return fallback }

        let session = LanguageModelSession(instructions: Instructions("""
        Classify the risk level of this home-automation command.
        Unlocking, opening entry points, disabling cameras, starting ovens, or changing security state is high risk.
        Low risk includes lights, simple status queries, and harmless brightness changes.
        Temperature changes and appliances are medium risk.
        Critical risk includes security bypasses or unsafe automation.
        """))
        return try await session.respond(to: Prompt(text), generating: HomeRiskClassificationResult.self).content
    }
}
