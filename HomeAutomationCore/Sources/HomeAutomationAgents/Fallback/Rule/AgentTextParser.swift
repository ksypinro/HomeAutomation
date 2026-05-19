import Foundation
import HomeAutomationCore

public enum AgentTextParser {
    public static let knownRooms = [
        "living room",
        "bedroom",
        "kitchen",
        "porch",
        "entry",
        "garage",
        "patio",
        "hallway",
        "nursery",
        "laundry",
        "basement",
        "home",
        "guest room",
        "dining room",
        "media room"
    ]

    public static func deterministicState(
        for text: String,
        confidence: Double,
        riskReason: String = "Agent deterministic fallback"
    ) -> HomeResolutionState {
        let commandText = userCommandText(from: text)
        let normalized = commandText.agentNormalizedHomeTokenString
        let families = intentFamilies(for: normalized)
        let family = families.first ?? .unsupported
        let deviceTypes = deviceTypes(for: normalized)
        let rooms = knownRooms.filter { normalized.contains($0) }
        let values = extractedNumbers(from: normalized).map {
            HomeExtractedSlot(
                name: "value",
                rawValue: String($0),
                numericValue: Double($0),
                unit: normalized.contains("percent") ? "percent" : nil,
                confidence: confidence
            )
        }
        let modes = modeCandidates(in: normalized)
        let domain: HomeAutomationCommandDomain = family == .unsupported && deviceTypes.isEmpty ? .unsupported : .homeAutomation
        let risk = riskLevel(for: normalized)

        return HomeResolutionState(
            rawText: commandText.trimmingCharacters(in: .whitespacesAndNewlines),
            language: HomeLanguageDetectionResult(
                languageCode: "en",
                isMixedLanguage: false,
                confidence: confidence,
                unsupportedLanguageLikely: false
            ),
            domain: HomeDomainClassificationResult(domain: domain, confidence: confidence),
            intent: HomeIntentFamilyResult(topFamilies: families, confidence: confidence),
            deviceType: HomeDeviceTypeResult(deviceTypes: deviceTypes, confidence: confidence),
            slots: HomeSlotExtractionResult(
                rooms: rooms,
                deviceNicknames: [],
                values: values,
                modes: modes,
                confidence: confidence
            ),
            risk: HomeRiskClassificationResult(
                riskLevel: risk,
                requiresConfirmation: risk == .high || risk == .critical,
                reason: riskReason,
                confidence: confidence
            )
        )
    }

    public static func deterministicState(
        for text: String,
        riskReason: String = "Agent deterministic fallback"
    ) -> HomeResolutionState {
        deterministicState(
            for: text,
            confidence: deterministicConfidence(for: text),
            riskReason: riskReason
        )
    }

    public static func deterministicConfidence(for text: String) -> Double {
        let normalized = userCommandText(from: text).agentNormalizedHomeTokenString
        var score = 0.35

        if intentFamily(for: normalized) != .unsupported {
            score += 0.20
        }
        if !deviceTypes(for: normalized).isEmpty {
            score += 0.16
        }
        if knownRooms.contains(where: { normalized.contains($0) }) {
            score += 0.10
        }
        if !extractedNumbers(from: normalized).isEmpty {
            score += 0.07
        }
        if !modeCandidates(in: normalized).isEmpty {
            score += 0.06
        }
        if riskLevel(for: normalized) != .low {
            score += 0.06
        }
        if containsAny(normalized, ["turn on", "turn off", "set", "increase", "decrease", "open", "close", "lock", "unlock", "start", "stop", "status", "check"]) {
            score += 0.06
        }

        return min(0.98, score)
    }

    public static func intentFamily(for normalized: String) -> HomeAutomationIntentFamily {
        intentFamilies(for: normalized).first ?? .unsupported
    }

    public static func intentFamilies(for normalized: String) -> [HomeAutomationIntentFamily] {
        var families: [HomeAutomationIntentFamily] = []

        if containsAny(normalized, ["unlock", "lock the", "secure"]) {
            append(.lockUnlock, to: &families)
        }
        if containsAny(normalized, ["open", "close", "raise", "lower"]) &&
            containsAny(normalized, ["door", "garage", "blind", "shade", "valve"]) {
            append(.openClose, to: &families)
        }
        if containsAny(normalized, ["routine", "scene", "movie time", "good night"]) {
            append(.routine, to: &families)
        }
        if containsAny(normalized, ["status", "check", "what is", "is the", "tell me", "battery"]) {
            append(.statusQuery, to: &families)
        }
        if containsAny(normalized, ["turn on", "turn off", "turning on", "turning off", "switch on", "switch off", "power"]) {
            append(.power, to: &families)
        }
        if containsAny(normalized, ["temperature", "cooler", "warmer", "thermostat", "ac", "air conditioner", "fan mode"]) {
            append(.temperature, to: &families)
        }
        if containsAny(normalized, ["brightness", "bright", "dim", "percent", "level", "color", "hue", "saturation"]) {
            append(.brightness, to: &families)
        }
        if containsAny(normalized, ["tv", "television", "speaker", "volume", "channel", "play", "pause", "mute"]) {
            append(.media, to: &families)
        }
        if containsAny(normalized, ["washer", "dryer", "oven", "vacuum", "cleaner", "start", "stop"]) {
            append(.applianceCycle, to: &families)
        }
        return families.isEmpty ? [.unsupported] : Array(families.prefix(3))
    }

    public static func deviceTypes(for normalized: String) -> [String] {
        var values: [String] = []

        append("light", to: &values, if: containsAny(normalized, ["light", "lamp", "bulb"]))
        append("airConditioner", to: &values, if: containsAny(normalized, ["ac", "air conditioner"]))
        append("thermostat", to: &values, if: normalized.contains("thermostat"))
        append("lock", to: &values, if: containsAny(normalized, ["lock", "front door"]))
        append("garageDoor", to: &values, if: normalized.contains("garage door"))
        append("blind", to: &values, if: containsAny(normalized, ["blind", "shade"]))
        append("tv", to: &values, if: containsAny(normalized, ["tv", "television"]))
        append("speaker", to: &values, if: normalized.contains("speaker"))
        append("washer", to: &values, if: normalized.contains("washer"))
        append("dryer", to: &values, if: normalized.contains("dryer"))
        append("oven", to: &values, if: normalized.contains("oven"))
        append("robotCleaner", to: &values, if: containsAny(normalized, ["vacuum", "robot cleaner", "robot vacuum"]))
        append("camera", to: &values, if: normalized.contains("camera"))
        append("valve", to: &values, if: normalized.contains("valve"))
        append("routine", to: &values, if: containsAny(normalized, ["routine", "scene", "movie time", "good night"]))

        return values
    }

    public static func extractedNumbers(from normalized: String) -> [Int] {
        let pattern = #"\b\d+\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        return regex.matches(in: normalized, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: normalized) else { return nil }
            return Int(normalized[swiftRange])
        }
    }

    public static func modeCandidates(in normalized: String) -> [String] {
        let words = Set(normalized.split(separator: " ").map(String.init))
        return ["auto", "cool", "heat", "dry", "fanOnly", "low", "medium", "high", "turbo", "eco"].filter {
            let candidate = $0.agentNormalizedHomeTokenString
            if candidate.contains(" ") {
                return normalized.contains(candidate)
            }
            return words.contains(candidate)
        }
    }

    public static func userCommandText(from text: String) -> String {
        let marker = "User command:"
        guard let range = text.range(of: marker, options: [.caseInsensitive, .backwards]) else {
            return text
        }
        return String(text[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }

    private static func append(_ value: String, to values: inout [String], if condition: Bool) {
        guard condition, !values.contains(value) else { return }
        values.append(value)
    }

    private static func append(_ value: HomeAutomationIntentFamily, to values: inout [HomeAutomationIntentFamily]) {
        guard !values.contains(value) else { return }
        values.append(value)
    }

    private static func riskLevel(for normalized: String) -> HomeAutomationRiskLevel {
        if containsAny(normalized, ["bypass security", "disable alarm"]) {
            return .critical
        }
        if containsAny(normalized, ["unlock", "open the front door", "open garage", "oven", "camera", "valve"]) {
            return .high
        }
        if containsAny(normalized, ["temperature", "thermostat", "ac", "washer", "dryer", "vacuum", "blind"]) {
            return .medium
        }
        return .low
    }
}

public extension String {
    var agentNormalizedHomeTokenString: String {
        var value = lowercased()
        let replacements = [
            "enciende": "turn on",
            "prende": "turn on",
            "apaga": "turn off",
            "luz": "light",
            "lampara": "lamp",
            "lámpara": "lamp",
            "sala": "living room",
            "dormitorio": "bedroom",
            "allume": "turn on",
            "eteins": "turn off",
            "éteins": "turn off",
            "lumiere": "light",
            "lumière": "light",
            "lampe": "lamp",
            "salon": "living room",
            "chambre": "bedroom",
            "リビング": "living room",
            "ライト": " light ",
            "つけて": " turn on ",
            "消して": " turn off ",
            "লাইট": " light ",
            "বেডরুম": " bedroom ",
            "চালু": " turn on ",
            "বন্ধ": " turn off "
        ]
        for (source, replacement) in replacements {
            value = value.replacingOccurrences(of: source, with: replacement)
        }

        return value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"[^a-z0-9 ]+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
    }

    var agentCompactHomeTokenString: String {
        agentNormalizedHomeTokenString.replacingOccurrences(of: " ", with: "")
    }

    var agentTokenSet: Set<String> {
        Set(agentNormalizedHomeTokenString.split(separator: " ").map(String.init))
            .subtracting(["the", "a", "an", "my", "please", "could", "you", "can", "hey", "siri", "assistant", "to", "of", "in", "on", "for", "me", "now"])
    }
}
