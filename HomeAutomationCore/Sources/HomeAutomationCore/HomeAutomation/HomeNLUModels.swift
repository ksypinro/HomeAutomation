import Foundation
import FoundationModels

@Generable
public struct HomeLanguageDetectionResult: Sendable, Hashable, Codable {
    @Guide(description: "BCP-47-style language code such as en, es, fr, ja, bn, or mixed_bn_en.")
    public let languageCode: String
    public let isMixedLanguage: Bool
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    public let confidence: Double
    public let unsupportedLanguageLikely: Bool

    public init(
        languageCode: String,
        isMixedLanguage: Bool,
        confidence: Double,
        unsupportedLanguageLikely: Bool
    ) {
        self.languageCode = languageCode
        self.isMixedLanguage = isMixedLanguage
        self.confidence = confidence
        self.unsupportedLanguageLikely = unsupportedLanguageLikely
    }
}

@Generable
public struct HomeDomainClassificationResult: Sendable, Hashable, Codable {
    public let domain: HomeAutomationCommandDomain
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    public let confidence: Double

    public init(domain: HomeAutomationCommandDomain, confidence: Double) {
        self.domain = domain
        self.confidence = confidence
    }
}

@Generable
public struct HomeIntentFamilyResult: Sendable, Hashable, Codable {
    @Guide(description: "Most likely smart-home intent families, ordered by likelihood.", .maximumCount(3))
    public let topFamilies: [HomeAutomationIntentFamily]
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    public let confidence: Double

    public init(topFamilies: [HomeAutomationIntentFamily], confidence: Double) {
        self.topFamilies = topFamilies
        self.confidence = confidence
    }
}

@Generable
public struct HomeDeviceTypeResult: Sendable, Hashable, Codable {
    @Guide(description: "Likely device types in internal English schema names.", .maximumCount(5))
    public let deviceTypes: [String]
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    public let confidence: Double

    public init(deviceTypes: [String], confidence: Double) {
        self.deviceTypes = deviceTypes
        self.confidence = confidence
    }
}

@Generable
public struct HomeSemanticNLUResult: Sendable, Hashable, Codable {
    public let intent: HomeIntentFamilyResult
    public let deviceType: HomeDeviceTypeResult

    public init(
        intent: HomeIntentFamilyResult,
        deviceType: HomeDeviceTypeResult
    ) {
        self.intent = intent
        self.deviceType = deviceType
    }
}

@Generable
public struct HomeExtractedSlot: Sendable, Hashable, Codable {
    @Guide(description: "Canonical slot name such as value, duration, temperature, mode, room, or device.")
    public let name: String
    @Guide(description: "Exact text or normalized phrase from the user command.")
    public let rawValue: String
    public let numericValue: Double?
    @Guide(description: "Short unit such as percent, degree, minute, hour, celsius, or fahrenheit.")
    public let unit: String?
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    public let confidence: Double

    public init(
        name: String,
        rawValue: String,
        numericValue: Double? = nil,
        unit: String? = nil,
        confidence: Double
    ) {
        self.name = name
        self.rawValue = rawValue
        self.numericValue = numericValue
        self.unit = unit
        self.confidence = confidence
    }
}

@Generable
public struct HomeSlotExtractionResult: Sendable, Hashable, Codable {
    @Guide(description: "Room or location names mentioned by the user.", .maximumCount(5))
    public let rooms: [String]
    @Guide(description: "Device nicknames or labels mentioned by the user.", .maximumCount(5))
    public let deviceNicknames: [String]
    @Guide(description: "Numeric, duration, temperature, color, or other value slots.", .maximumCount(6))
    public let values: [HomeExtractedSlot]
    @Guide(description: "Mode names mentioned by the user.", .maximumCount(5))
    public let modes: [String]
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    public let confidence: Double

    public init(
        rooms: [String],
        deviceNicknames: [String],
        values: [HomeExtractedSlot],
        modes: [String],
        confidence: Double
    ) {
        self.rooms = rooms
        self.deviceNicknames = deviceNicknames
        self.values = values
        self.modes = modes
        self.confidence = confidence
    }
}

@Generable
public struct HomeRiskClassificationResult: Sendable, Hashable, Codable {
    public let riskLevel: HomeAutomationRiskLevel
    public let requiresConfirmation: Bool
    @Guide(description: "One concise sentence explaining the risk classification.")
    public let reason: String
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    public let confidence: Double

    public init(
        riskLevel: HomeAutomationRiskLevel,
        requiresConfirmation: Bool,
        reason: String,
        confidence: Double
    ) {
        self.riskLevel = riskLevel
        self.requiresConfirmation = requiresConfirmation
        self.reason = reason
        self.confidence = confidence
    }
}

public struct HomeResolutionState: Sendable, Hashable, Codable {
    public let rawText: String
    public let language: HomeLanguageDetectionResult
    public let domain: HomeDomainClassificationResult
    public let intent: HomeIntentFamilyResult
    public let deviceType: HomeDeviceTypeResult
    public let slots: HomeSlotExtractionResult
    public let risk: HomeRiskClassificationResult

    public init(
        rawText: String,
        language: HomeLanguageDetectionResult,
        domain: HomeDomainClassificationResult,
        intent: HomeIntentFamilyResult,
        deviceType: HomeDeviceTypeResult,
        slots: HomeSlotExtractionResult,
        risk: HomeRiskClassificationResult
    ) {
        self.rawText = rawText
        self.language = language
        self.domain = domain
        self.intent = intent
        self.deviceType = deviceType
        self.slots = slots
        self.risk = risk
    }
}
