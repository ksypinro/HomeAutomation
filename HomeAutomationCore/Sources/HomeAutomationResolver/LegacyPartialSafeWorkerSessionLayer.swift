import Foundation
import FoundationModels
import HomeAutomationCore

public struct LegacyPartialWorkerOverrides: Sendable {
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

public struct LegacyPartialSafeWorkerSessionLayer: HomeWorkerSessionAnalyzing {
    private let foundationModelAvailability: @Sendable () -> Bool
    private let timeoutNanoseconds: UInt64
    private let workerOverrides: LegacyPartialWorkerOverrides

    public init(
        timeoutNanoseconds: UInt64 = 10_000_000_000,
        workerOverrides: LegacyPartialWorkerOverrides = LegacyPartialWorkerOverrides(),
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        }
    ) {
        self.timeoutNanoseconds = timeoutNanoseconds
        self.workerOverrides = workerOverrides
        self.foundationModelAvailability = foundationModelAvailability
    }

    public func analyze(_ text: String) async throws -> HomeResolutionState {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw FoundationLabCoreError.invalidRequest("Missing home command")
        }

        let fallback = LegacyTextParser.deterministicState(
            for: trimmedText,
            confidence: 0.42,
            riskReason: "legacy partial worker fallback"
        )

        guard foundationModelAvailability() else {
            return fallback
        }

        async let language = safe(fallback.language) {
            try await runLanguageDetection(trimmedText)
        }
        async let domain = safe(fallback.domain) {
            try await runDomainClassification(trimmedText)
        }
        async let intent = safe(fallback.intent) {
            try await runIntentClassification(trimmedText)
        }
        async let deviceType = safe(fallback.deviceType) {
            try await runDeviceTypeClassification(trimmedText)
        }
        async let slots = safe(fallback.slots) {
            try await runSlotExtraction(trimmedText)
        }
        async let risk = safe(fallback.risk) {
            try await runRiskClassification(trimmedText)
        }

        return await HomeResolutionState(
            rawText: trimmedText,
            language: language,
            domain: domain,
            intent: intent,
            deviceType: deviceType,
            slots: slots,
            risk: risk
        )
    }

    private func safe<T: Sendable>(
        _ fallback: T,
        operation: @escaping @Sendable () async throws -> T
    ) async -> T {
        do {
            return try await LegacyTimeout.run(nanoseconds: timeoutNanoseconds, operation: operation)
        } catch {
            return fallback
        }
    }

    private func runLanguageDetection(_ text: String) async throws -> HomeLanguageDetectionResult {
        if let override = workerOverrides.detectLanguage {
            return try await override(text)
        }
        return try await detectLanguage(text)
    }

    private func runDomainClassification(_ text: String) async throws -> HomeDomainClassificationResult {
        if let override = workerOverrides.classifyDomain {
            return try await override(text)
        }
        return try await classifyDomain(text)
    }

    private func runIntentClassification(_ text: String) async throws -> HomeIntentFamilyResult {
        if let override = workerOverrides.classifyIntentFamily {
            return try await override(text)
        }
        return try await classifyIntentFamily(text)
    }

    private func runDeviceTypeClassification(_ text: String) async throws -> HomeDeviceTypeResult {
        if let override = workerOverrides.classifyDeviceType {
            return try await override(text)
        }
        return try await classifyDeviceType(text)
    }

    private func runSlotExtraction(_ text: String) async throws -> HomeSlotExtractionResult {
        if let override = workerOverrides.extractSlots {
            return try await override(text)
        }
        return try await extractSlots(text)
    }

    private func runRiskClassification(_ text: String) async throws -> HomeRiskClassificationResult {
        if let override = workerOverrides.classifyRisk {
            return try await override(text)
        }
        return try await classifyRisk(text)
    }

    private func detectLanguage(_ text: String) async throws -> HomeLanguageDetectionResult {
        let session = LanguageModelSession(instructions: Instructions("""
        Detect the language of this user command.
        Return compact structured output only.
        Use BCP-47-style language codes such as en, es, fr, ja, bn, or mixed_bn_en.
        """))

        let response = try await session.respond(
            to: Prompt(text),
            generating: HomeLanguageDetectionResult.self
        )
        return response.content
    }

    private func classifyDomain(_ text: String) async throws -> HomeDomainClassificationResult {
        let session = LanguageModelSession(instructions: Instructions("""
        Decide whether the text is a smart-home or home-automation command.
        Do not resolve devices. Classify only the domain.
        """))

        let response = try await session.respond(
            to: Prompt(text),
            generating: HomeDomainClassificationResult.self
        )
        return response.content
    }

    private func classifyIntentFamily(_ text: String) async throws -> HomeIntentFamilyResult {
        let session = LanguageModelSession(instructions: Instructions("""
        Classify the command into broad smart-home intent families.
        Return the most likely families first. Do not choose a specific device.

        \(HomeBixbyCommandCatalog.instructionSummary)
        """))

        let response = try await session.respond(
            to: Prompt(text),
            generating: HomeIntentFamilyResult.self
        )
        return response.content
    }

    private func classifyDeviceType(_ text: String) async throws -> HomeDeviceTypeResult {
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

        let response = try await session.respond(
            to: Prompt(text),
            generating: HomeDeviceTypeResult.self
        )
        return response.content
    }

    private func extractSlots(_ text: String) async throws -> HomeSlotExtractionResult {
        let session = LanguageModelSession(instructions: Instructions("""
        Extract rooms, device nicknames, values, units, durations, and modes from a smart-home command.
        Keep internal values in English even when the input is multilingual.
        Do not resolve devices or commands.
        Understand Bixby Home Studio slot language: device, deviceType, location, mode, predefinedMode, temperature,
        duration, number, compartment, and channel should be extracted when present.
        """))

        let response = try await session.respond(
            to: Prompt(text),
            generating: HomeSlotExtractionResult.self
        )
        return response.content
    }

    private func classifyRisk(_ text: String) async throws -> HomeRiskClassificationResult {
        let session = LanguageModelSession(instructions: Instructions("""
        Classify the risk level of this home-automation command.
        Unlocking, opening entry points, disabling cameras, starting ovens, or changing security state is high risk.
        Low risk includes lights, simple status queries, and harmless brightness changes.
        Temperature changes and appliances are medium risk.
        Critical risk includes security bypasses or unsafe automation.
        """))

        let response = try await session.respond(
            to: Prompt(text),
            generating: HomeRiskClassificationResult.self
        )
        return response.content
    }
}
