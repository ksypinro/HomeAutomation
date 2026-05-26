import Foundation

public struct HomeDeviceTypeInferenceResult: Sendable, Hashable, Codable {
    public let deviceType: String
    public let confidence: Double
    public let evidence: [String]

    public init(deviceType: String, confidence: Double, evidence: [String]) {
        self.deviceType = deviceType
        self.confidence = confidence
        self.evidence = evidence
    }
}

public enum HomeDeviceTypeInferencer {
    public static func infer(
        deviceName: String?,
        capabilities: [String],
        categoryName: String? = nil,
        categoryNames: [String] = [],
        deviceTypeName: String? = nil,
        deviceTypeID: String? = nil,
        smartThingsType: String? = nil,
        profileID: String? = nil,
        presentationID: String? = nil,
        manufacturerName: String? = nil
    ) -> HomeDeviceTypeInferenceResult {
        let catalog = HomeAutomationKnowledgeBase.shared.deviceTypes
        let capabilitySet = Set(capabilities)
        let normalizedCapabilities = Set(capabilities.map(\.normalizedHomeTokenString))
        let categoryValues = ([categoryName].compactMap { $0 } + categoryNames)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let deviceName = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        var scores: [String: ScoredDeviceType] = [:]

        func addScore(_ deviceType: String, _ score: Double, _ evidence: String) {
            guard score > 0 else { return }
            var scored = scores[deviceType] ?? ScoredDeviceType(score: 0, evidence: [])
            scored.score += score
            scored.evidence.append(evidence)
            scores[deviceType] = scored
        }

        for category in categoryValues {
            addTextMatches(
                category,
                catalog: catalog,
                baseScore: 1.08,
                evidencePrefix: "SmartThings category",
                addScore: addScore
            )
        }

        addTextMatches(
            deviceTypeName,
            catalog: catalog,
            baseScore: 0.72,
            evidencePrefix: "SmartThings deviceTypeName",
            addScore: addScore
        )

        if !looksLikeOpaqueID(deviceTypeID) {
            addTextMatches(
                deviceTypeID,
                catalog: catalog,
                baseScore: 0.62,
                evidencePrefix: "SmartThings deviceTypeId",
                addScore: addScore
            )
        }

        addTextMatches(
            smartThingsType,
            catalog: catalog,
            baseScore: 0.55,
            evidencePrefix: "SmartThings type",
            addScore: addScore
        )
        addTextMatches(
            profileID,
            catalog: catalog,
            baseScore: 0.38,
            evidencePrefix: "SmartThings profile",
            addScore: addScore
        )
        addTextMatches(
            presentationID,
            catalog: catalog,
            baseScore: 0.34,
            evidencePrefix: "SmartThings presentation",
            addScore: addScore
        )
        addTextMatches(
            manufacturerName,
            catalog: catalog,
            baseScore: 0.18,
            evidencePrefix: "SmartThings manufacturer",
            addScore: addScore
        )

        addNameMatches(
            deviceName,
            catalog: catalog,
            addScore: addScore
        )

        addStrongCapabilitySignatures(
            capabilitySet: capabilitySet,
            normalizedCapabilities: normalizedCapabilities,
            normalizedName: deviceName?.normalizedHomeTokenString ?? "",
            addScore: addScore
        )

        addCatalogCapabilityScores(
            capabilitySet: capabilitySet,
            catalog: catalog,
            addScore: addScore
        )

        guard let best = scores.max(by: { lhs, rhs in
            if lhs.value.score == rhs.value.score {
                return lhs.key > rhs.key
            }
            return lhs.value.score < rhs.value.score
        }) else {
            return HomeDeviceTypeInferenceResult(
                deviceType: "device",
                confidence: 0.25,
                evidence: ["No usable device type hints were available."]
            )
        }

        let sortedScores = scores.sorted { lhs, rhs in
            if lhs.value.score == rhs.value.score {
                return lhs.key < rhs.key
            }
            return lhs.value.score > rhs.value.score
        }
        let runnerUp = sortedScores.dropFirst().first
        let runnerUpScore = runnerUp?.value.score ?? 0
        let ambiguityPenalty = runnerUp.map { runnerUp in
            best.value.score - runnerUpScore < 0.12 && !HomeDeviceTypeRelations.areRelated(best.key, runnerUp.key) ? 0.12 : 0
        } ?? 0
        let confidence = min(0.98, max(0.35, best.value.score)) - ambiguityPenalty

        return HomeDeviceTypeInferenceResult(
            deviceType: best.key,
            confidence: max(0.3, confidence),
            evidence: stableEvidence(best.value.evidence)
        )
    }

    private static func addTextMatches(
        _ value: String?,
        catalog: [HomeCatalogDeviceType],
        baseScore: Double,
        evidencePrefix: String,
        addScore: (String, Double, String) -> Void
    ) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return
        }
        let normalized = value.normalizedHomeTokenString

        for deviceType in catalog {
            let terms = matchTerms(for: deviceType)
            if terms.exact.contains(normalized) {
                addScore(deviceType.id, baseScore, "\(evidencePrefix) matched \(value)")
            } else if terms.partial.contains(where: { textValuePartiallyMatches(normalized, term: $0) }) {
                addScore(deviceType.id, baseScore * 0.72, "\(evidencePrefix) partially matched \(value)")
            }
        }
    }

    private static func addNameMatches(
        _ name: String?,
        catalog: [HomeCatalogDeviceType],
        addScore: (String, Double, String) -> Void
    ) {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return
        }
        let normalized = name.normalizedHomeTokenString

        for deviceType in catalog {
            let terms = matchTerms(for: deviceType)
            if terms.exact.contains(normalized) {
                addScore(deviceType.id, 0.62, "Device name exactly matched \(name)")
                continue
            }
            if let matched = terms.partial.first(where: { term in
                containsTokenPhrase(normalized, phrase: term)
            }) {
                addScore(deviceType.id, 0.46, "Device name contains \(matched)")
            }
        }
    }

    private static func addStrongCapabilitySignatures(
        capabilitySet: Set<String>,
        normalizedCapabilities: Set<String>,
        normalizedName: String,
        addScore: (String, Double, String) -> Void
    ) {
        func has(_ capability: String) -> Bool {
            capabilitySet.contains(capability) || normalizedCapabilities.contains(capability.normalizedHomeTokenString)
        }

        if has("lock") {
            addScore("lock", 0.94, "Capability lock strongly implies lock")
        }
        if has("switch") {
            addScore("switch", 0.28, "Generic switch capability is available as a weak fallback")
        }
        if has("garageDoorControl") {
            addScore("garageDoor", 0.94, "Capability garageDoorControl strongly implies garageDoor")
        }
        if has("contactSensor") {
            addScore("contactSensor", 0.93, "Capability contactSensor strongly implies contactSensor")
        }
        if has("motionSensor") {
            addScore("motionSensor", 0.93, "Capability motionSensor strongly implies motionSensor")
        }
        if has("waterSensor") {
            addScore("waterSensor", 0.93, "Capability waterSensor strongly implies waterSensor")
        }
        if has("smokeDetector") {
            addScore("smokeDetector", 0.93, "Capability smokeDetector strongly implies smokeDetector")
        }
        if has("carbonMonoxideDetector") {
            addScore("carbonMonoxideDetector", 0.93, "Capability carbonMonoxideDetector strongly implies carbonMonoxideDetector")
        }
        if has("airQualitySensor") {
            addScore("airQualityDetector", 0.9, "Capability airQualitySensor strongly implies airQualityDetector")
        }
        if has("valve") {
            addScore("valve", 0.9, "Capability valve strongly implies valve")
        }
        if has("airConditionerMode") || has("airConditionerFanMode") {
            addScore("airConditioner", 0.92, "Air-conditioner capabilities strongly imply airConditioner")
        }
        if has("thermostatMode") &&
            (has("thermostatCoolingSetpoint") || has("thermostatHeatingSetpoint")) {
            addScore("thermostat", 0.92, "Thermostat mode and setpoint capabilities imply thermostat")
        }
        if has("thermostatCoolingSetpoint") &&
            has("switch") &&
            (containsTokenPhrase(normalizedName, phrase: "ac") ||
             containsTokenPhrase(normalizedName, phrase: "air conditioner") ||
             containsTokenPhrase(normalizedName, phrase: "aircon")) {
            addScore("airConditioner", 0.86, "Cooling setpoint plus AC-like name implies airConditioner")
        }
        if has("windowShade") || has("windowShadeLevel") {
            let type: String
            if containsTokenPhrase(normalizedName, phrase: "curtain") {
                type = "curtain"
            } else if containsTokenPhrase(normalizedName, phrase: "shutter") {
                type = "shutter"
            } else if containsTokenPhrase(normalizedName, phrase: "awning") {
                type = "awning"
            } else {
                type = "blind"
            }
            addScore(type, 0.82, "Window shade capabilities imply \(type)")
        }
        if has("channel") || has("mediaInputSource") {
            addScore("tv", 0.72, "Media channel/input capabilities imply tv")
        }
        if has("audioVolume") && containsTokenPhrase(normalizedName, phrase: "speaker") {
            addScore("speaker", 0.72, "Audio volume capability plus speaker name implies speaker")
        }
        if has("washerOperatingState") || has("washerMode") {
            addScore("washer", 0.9, "Washer capabilities strongly imply washer")
        }
        if has("dryerOperatingState") || has("dryerMode") {
            addScore("dryer", 0.9, "Dryer capabilities strongly imply dryer")
        }
        if has("ovenMode") || has("ovenSetpoint") {
            addScore("oven", 0.9, "Oven capabilities strongly imply oven")
        }
        if has("robotCleanerMovement") || has("robotCleanerCleaningMode") {
            addScore("robotCleaner", 0.9, "Robot cleaner capabilities strongly imply robotCleaner")
        }
        if has("routine") {
            addScore("scene", 0.85, "Routine capability implies scene")
        }
    }

    private static func addCatalogCapabilityScores(
        capabilitySet: Set<String>,
        catalog: [HomeCatalogDeviceType],
        addScore: (String, Double, String) -> Void
    ) {
        guard !capabilitySet.isEmpty else { return }
        let frequency = capabilityFrequency(in: catalog)

        for deviceType in catalog {
            var score = 0.0
            var evidence: [String] = []

            let requiredMatches = deviceType.requiredCapabilities.filter { capabilitySet.contains($0) }
            let recommendedMatches = deviceType.recommendedCapabilities.filter { capabilitySet.contains($0) }
            let optionalMatches = deviceType.optionalCapabilities.filter { capabilitySet.contains($0) }
            let allMatches = requiredMatches + recommendedMatches + optionalMatches

            for capability in requiredMatches {
                score += rarityScore(for: capability, frequency: frequency) * 1.35
            }
            for capability in recommendedMatches {
                score += rarityScore(for: capability, frequency: frequency) * 0.85
            }
            for capability in optionalMatches {
                score += rarityScore(for: capability, frequency: frequency) * 0.35
            }

            if !deviceType.requiredCapabilities.isEmpty &&
                Set(deviceType.requiredCapabilities).isSubset(of: capabilitySet) &&
                deviceType.requiredCapabilities.contains(where: { (frequency[$0] ?? Int.max) <= 4 || deviceType.requiredCapabilities.count > 1 }) {
                score += 0.24
                evidence.append("Required capability signature matched")
            }

            guard score > 0 else { continue }
            evidence.append("Capabilities matched \(allMatches.joined(separator: ","))")
            addScore(
                deviceType.id,
                min(score, 0.78),
                evidence.joined(separator: "; ")
            )
        }
    }

    private static func matchTerms(for deviceType: HomeCatalogDeviceType) -> (exact: Set<String>, partial: [String]) {
        let exactValues = [
            deviceType.id,
            deviceType.displayName
        ] + deviceType.platformMappings.smartThingsDeviceTypes

        let partialValues = exactValues +
            deviceType.aliases +
            deviceType.exampleNames

        return (
            exact: Set(exactValues.map(\.normalizedHomeTokenString)),
            partial: stableEvidence(partialValues.map(\.normalizedHomeTokenString))
                .filter { !$0.isEmpty }
        )
    }

    private static func capabilityFrequency(in catalog: [HomeCatalogDeviceType]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for deviceType in catalog {
            for capability in Set(deviceType.allCapabilityIDs) {
                counts[capability, default: 0] += 1
            }
        }
        return counts
    }

    private static func rarityScore(for capability: String, frequency: [String: Int]) -> Double {
        let count = max(frequency[capability] ?? 12, 1)
        return min(0.34, max(0.03, 0.34 / Double(count)))
    }

    private static func containsTokenPhrase(_ normalizedText: String, phrase: String) -> Bool {
        let normalizedPhrase = phrase.normalizedHomeTokenString
        guard !normalizedPhrase.isEmpty else { return false }
        let paddedText = " \(normalizedText) "
        let paddedPhrase = " \(normalizedPhrase) "
        return paddedText.contains(paddedPhrase)
    }

    private static func textValuePartiallyMatches(_ normalizedText: String, term: String) -> Bool {
        let normalizedTerm = term.normalizedHomeTokenString
        guard !normalizedTerm.isEmpty else { return false }
        let words = normalizedTerm.split(separator: " ")
        guard words.count > 1 else {
            return normalizedText == normalizedTerm
        }
        return normalizedText.contains(normalizedTerm) || normalizedTerm.contains(normalizedText)
    }

    private static func looksLikeOpaqueID(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return true
        }
        let normalized = value.normalizedHomeTokenString
        guard normalized.count >= 18 else { return false }
        let hexLikeCharacters = value.filter { $0.isHexDigit || $0 == "-" }
        return hexLikeCharacters.count == value.count
    }

    private static func stableEvidence(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

private struct ScoredDeviceType: Sendable, Hashable {
    var score: Double
    var evidence: [String]
}
