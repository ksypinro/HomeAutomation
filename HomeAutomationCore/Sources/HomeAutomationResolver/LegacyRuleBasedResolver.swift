import Foundation
import HomeAutomationCore

public struct LegacyRuleBasedResolver: HomeCommandResolving {
    private let registry: MockHomeDeviceRegistry
    private let validator: LegacyCommandValidator
    private let executor: LegacyPlanExecutor
    private let bixbyFallbackMapper: LegacyBixbyFallbackMapper

    public init(
        registry: MockHomeDeviceRegistry = MockHomeDeviceRegistry(),
        validator: LegacyCommandValidator = LegacyCommandValidator(),
        bixbyFallbackMapper: LegacyBixbyFallbackMapper = LegacyBixbyFallbackMapper()
    ) {
        self.registry = registry
        self.validator = validator
        self.executor = LegacyPlanExecutor(registry: registry)
        self.bixbyFallbackMapper = bixbyFallbackMapper
    }

    public func resolve(
        _ text: String,
        executeLowRiskCommands: Bool = true
    ) async throws -> HomeAutomationResolverResult {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw FoundationLabCoreError.invalidRequest("Missing home command")
        }

        return try await resolveInternal(
            trimmedText,
            executeLowRiskCommands: executeLowRiskCommands,
            requireHighConfidence: false
        ) ?? unsupportedResult(for: trimmedText)
    }

    func resolveIfHighConfidence(
        _ text: String,
        executeLowRiskCommands: Bool
    ) async throws -> HomeAutomationResolverResult? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        return try await resolveInternal(
            trimmedText,
            executeLowRiskCommands: executeLowRiskCommands,
            requireHighConfidence: true
        )
    }

    private func resolveInternal(
        _ text: String,
        executeLowRiskCommands: Bool,
        requireHighConfidence: Bool
    ) async throws -> HomeAutomationResolverResult? {
        let normalized = text.legacyNormalizedHomeTokenString
        let state = LegacyTextParser.deterministicState(
            for: text,
            confidence: requireHighConfidence ? 0.82 : 0.65,
            riskReason: "legacy rule-based classification"
        )

        guard state.domain.domain == .homeAutomation else {
            return nil
        }

        let allDevices = await registry.allDevices()

        guard let ruleIntent = RuleIntent(normalized: normalized) else {
            return try await resolveBixby(
                text,
                state: state,
                allDevices: allDevices,
                executeLowRiskCommands: executeLowRiskCommands,
                requireHighConfidence: requireHighConfidence
            )
        }

        let scored = allDevices.compactMap { device -> ScoredDevice? in
            guard let draftIntent = ruleIntent.makeDraftIntent(for: device, normalized: normalized) else {
                return nil
            }

            let score = score(device, for: ruleIntent, normalized: normalized)
            guard score > 0 else { return nil }
            return ScoredDevice(device: device, draftIntent: draftIntent, score: score)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.device.displayName < rhs.device.displayName
            }
            return lhs.score > rhs.score
        }

        guard let selected = scored.first else {
            if let bixbyResult = try await resolveBixby(
                text,
                state: state,
                allDevices: allDevices,
                executeLowRiskCommands: executeLowRiskCommands,
                requireHighConfidence: requireHighConfidence
            ) {
                return bixbyResult
            }

            return requireHighConfidence ? nil : clarificationResult(
                for: text,
                state: state,
                retrievedCandidates: Array(allDevices.prefix(8)),
                question: "Which device do you want to control?"
            )
        }

        let secondScore = scored.dropFirst().first?.score ?? 0
        let isAmbiguous = selected.score < 8 || (secondScore > 0 && selected.score - secondScore < 2)
        if isAmbiguous {
            return requireHighConfidence ? nil : clarificationResult(
                for: text,
                state: state,
                retrievedCandidates: scored.prefix(8).map(\.device),
                question: "Which \(selected.device.deviceType) do you mean?"
            )
        }

        if requireHighConfidence, selected.score < 12 {
            return nil
        }

        let candidateIDs = [selected.device.id]
        let aggregation = HomeCandidateAggregationResult(
            finalCandidateIDs: candidateIDs,
            needsClarification: false,
            confidence: min(0.98, Double(selected.score) / 24.0)
        )
        let finalInput = HomeFinalResolutionInput(
            rawText: text,
            resolutionState: state,
            hydratedCandidates: [selected.device],
            aggregation: aggregation
        )
        let draft = HomeCommandDraft(
            intent: selected.draftIntent.intent,
            targetDeviceID: selected.device.id,
            capability: selected.draftIntent.capability,
            command: selected.draftIntent.command,
            parameters: selected.draftIntent.parameters,
            needsClarification: false,
            requiresConfirmation: false,
            confidence: min(0.98, Double(selected.score) / 24.0)
        )

        var resolution = validator.validate(draft, input: finalInput)
        if executeLowRiskCommands,
           case .readyToExecute(let plan) = resolution,
           !plan.requiresConfirmation,
           plan.steps.allSatisfy({ $0.type != "query" }) {
            let updatedDevice = try await executor.executeLowRiskPlan(plan)
            resolution = .executed(plan, updatedDevice: updatedDevice)
        }

        return HomeAutomationResolverResult(
            state: state,
            retrievedCandidates: scored.prefix(12).map(\.device),
            aggregation: aggregation,
            hydratedCandidates: [selected.device],
            draft: draft,
            resolution: resolution
        )
    }

    private func unsupportedResult(for text: String) -> HomeAutomationResolverResult {
        let state = LegacyTextParser.deterministicState(
            for: text,
            confidence: 0.4,
            riskReason: "legacy rule-based fallback could not map the command"
        )
        return HomeAutomationResolverResult(
            state: state,
            retrievedCandidates: [],
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: [],
                needsClarification: false,
                confidence: 0
            ),
            hydratedCandidates: [],
            draft: nil,
            resolution: .unsupported("legacy rule-based fallback could not map this command.")
        )
    }

    private func clarificationResult(
        for text: String,
        state: HomeResolutionState,
        retrievedCandidates: [HomeCandidateRecord],
        question: String
    ) -> HomeAutomationResolverResult {
        HomeAutomationResolverResult(
            state: state,
            retrievedCandidates: retrievedCandidates,
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: [],
                needsClarification: true,
                clarificationQuestion: question,
                confidence: 0.25
            ),
            hydratedCandidates: [],
            draft: nil,
            resolution: .needsClarification(question)
        )
    }

    private func score(
        _ device: HomeCandidateRecord,
        for intent: RuleIntent,
        normalized: String
    ) -> Int {
        let queryTokens = normalized.legacyTokenSet
        let name = device.displayName.legacyNormalizedHomeTokenString
        let nameTokens = name.legacyTokenSet
        let type = device.deviceType.legacyNormalizedHomeTokenString
        let room = device.room?.legacyNormalizedHomeTokenString
        let aliases = device.metadata["aliases"]?
            .split(separator: ",")
            .map { String($0).legacyNormalizedHomeTokenString } ?? []

        var total = 0
        if normalized.contains(name) { total += 20 }
        if aliases.contains(where: { !$0.isEmpty && normalized.contains($0) }) { total += 14 }
        if normalized.contains(type) || intent.deviceTypeHints.contains(type) { total += 7 }
        if let room, normalized.contains(room) { total += 6 }

        let overlap = queryTokens.intersection(nameTokens).count
        total += min(overlap * 2, 8)

        if intent.capabilityPreferences.contains(where: { device.capabilities.contains($0.capability) }) {
            total += 6
        }

        if device.type == .routine, intent.family == .routine {
            total += 8
        }

        return total
    }

    private func resolveBixby(
        _ text: String,
        state: HomeResolutionState,
        allDevices: [HomeCandidateRecord],
        executeLowRiskCommands: Bool,
        requireHighConfidence: Bool
    ) async throws -> HomeAutomationResolverResult? {
        let matches = bixbyFallbackMapper.matches(text: text, devices: allDevices)
        guard let selected = matches.first else { return nil }

        let secondScore = matches.dropFirst().first?.score ?? 0
        let isAmbiguous = secondScore > 0 && selected.score - secondScore < 2
        if isAmbiguous {
            return requireHighConfidence ? nil : clarificationResult(
                for: text,
                state: state,
                retrievedCandidates: matches.prefix(8).map(\.device),
                question: "Which device do you mean?"
            )
        }

        if requireHighConfidence, selected.score < 28 {
            return nil
        }

        let aggregation = HomeCandidateAggregationResult(
            finalCandidateIDs: [selected.device.id],
            needsClarification: false,
            confidence: min(0.98, Double(selected.score) / 36.0)
        )
        let finalInput = HomeFinalResolutionInput(
            rawText: text,
            resolutionState: state,
            hydratedCandidates: [selected.device],
            aggregation: aggregation
        )

        var resolution = validator.validate(selected.draft, input: finalInput)
        if executeLowRiskCommands,
           case .readyToExecute(let plan) = resolution,
           !plan.requiresConfirmation,
           plan.steps.allSatisfy({ $0.type != "query" }) {
            let updatedDevice = try await executor.executeLowRiskPlan(plan)
            resolution = .executed(plan, updatedDevice: updatedDevice)
        }

        return HomeAutomationResolverResult(
            state: state,
            retrievedCandidates: Array(Set(matches.prefix(12).map(\.device))).sorted { $0.displayName < $1.displayName },
            aggregation: aggregation,
            hydratedCandidates: [selected.device],
            draft: selected.draft,
            resolution: resolution
        )
    }
}

private struct ScoredDevice {
    let device: HomeCandidateRecord
    let draftIntent: DraftIntent
    let score: Int
}

private struct DraftIntent {
    let intent: HomeAutomationIntent
    let capability: String
    let command: String
    let parameters: [HomeResolvedParameter]
}

private struct CapabilityCommand {
    let capability: String
    let command: String
}

private struct RuleIntent {
    let family: HomeAutomationIntentFamily
    let intent: HomeAutomationIntent
    let capabilityPreferences: [CapabilityCommand]
    let parameters: [HomeResolvedParameter]
    let deviceTypeHints: Set<String>
    let relativeTemperatureDelta: Int?
    let relativeTemperatureDirection: Int

    init?(normalized: String) {
        let numbers = LegacyTextParser.extractedNumbers(from: normalized)
        let firstNumber = numbers.first

        if LegacyTextParser.containsAny(normalized, ["movie time", "good night", "routine", "scene"]) {
            self.init(
                family: .routine,
                intent: .runRoutine,
                capabilityPreferences: [CapabilityCommand(capability: "routine", command: "run")],
                parameters: [],
                deviceTypeHints: ["routine"],
                relativeTemperatureDelta: nil,
                relativeTemperatureDirection: 0
            )
            return
        }

        if normalized.contains("unlock") || normalized.contains("open the lock") {
            self.init(
                family: .lockUnlock,
                intent: .unlock,
                capabilityPreferences: [CapabilityCommand(capability: "lock", command: "unlock")],
                parameters: [],
                deviceTypeHints: ["lock"],
                relativeTemperatureDelta: nil,
                relativeTemperatureDirection: 0
            )
            return
        }

        if normalized.contains("lock") || normalized.contains("secure") {
            self.init(
                family: .lockUnlock,
                intent: .lock,
                capabilityPreferences: [CapabilityCommand(capability: "lock", command: "lock")],
                parameters: [],
                deviceTypeHints: ["lock"],
                relativeTemperatureDelta: nil,
                relativeTemperatureDirection: 0
            )
            return
        }

        if LegacyTextParser.containsAny(normalized, ["open", "raise"]) &&
            LegacyTextParser.containsAny(normalized, ["door", "garage", "blind", "shade", "valve"]) {
            self.init(
                family: .openClose,
                intent: .open,
                capabilityPreferences: [
                    CapabilityCommand(capability: "garageDoorControl", command: "open"),
                    CapabilityCommand(capability: "doorControl", command: "open"),
                    CapabilityCommand(capability: "windowShade", command: "open"),
                    CapabilityCommand(capability: "valve", command: "open")
                ],
                parameters: [],
                deviceTypeHints: ["garage door", "door", "blind", "valve"],
                relativeTemperatureDelta: nil,
                relativeTemperatureDirection: 0
            )
            return
        }

        if LegacyTextParser.containsAny(normalized, ["close", "lower"]) &&
            LegacyTextParser.containsAny(normalized, ["door", "garage", "blind", "shade", "valve"]) {
            self.init(
                family: .openClose,
                intent: .close,
                capabilityPreferences: [
                    CapabilityCommand(capability: "garageDoorControl", command: "close"),
                    CapabilityCommand(capability: "doorControl", command: "close"),
                    CapabilityCommand(capability: "windowShade", command: "close"),
                    CapabilityCommand(capability: "valve", command: "close")
                ],
                parameters: [],
                deviceTypeHints: ["garage door", "door", "blind", "valve"],
                relativeTemperatureDelta: nil,
                relativeTemperatureDirection: 0
            )
            return
        }

        if LegacyTextParser.containsAny(normalized, ["status", "check", "what is", "is the", "tell me", "battery"]) {
            self.init(
                family: .statusQuery,
                intent: .getStatus,
                capabilityPreferences: statusCapabilityPreferences(for: normalized),
                parameters: [],
                deviceTypeHints: Set(LegacyTextParser.deviceTypes(for: normalized).map(\.legacyNormalizedHomeTokenString)),
                relativeTemperatureDelta: nil,
                relativeTemperatureDirection: 0
            )
            return
        }

        if normalized.contains("fan mode") {
            let mode = LegacyTextParser.modeCandidates(in: normalized).first ?? "auto"
            self.init(
                family: .temperature,
                intent: .setValue,
                capabilityPreferences: [
                    CapabilityCommand(capability: "airConditionerFanMode", command: "setFanMode"),
                    CapabilityCommand(capability: "thermostatFanMode", command: "setThermostatFanMode")
                ],
                parameters: [
                    HomeResolvedParameter(name: "value", value: mode, confidence: 0.85)
                ],
                deviceTypeHints: ["air conditioner", "thermostat"],
                relativeTemperatureDelta: nil,
                relativeTemperatureDirection: 0
            )
            return
        }

        if LegacyTextParser.containsAny(normalized, ["cooler", "warmer"]) {
            let direction = normalized.contains("cooler") ? -1 : 1
            self.init(
                family: .temperature,
                intent: direction < 0 ? .decreaseValue : .increaseValue,
                capabilityPreferences: [
                    CapabilityCommand(capability: "thermostatCoolingSetpoint", command: "setCoolingSetpoint"),
                    CapabilityCommand(capability: "thermostatHeatingSetpoint", command: "setHeatingSetpoint")
                ],
                parameters: [],
                deviceTypeHints: ["air conditioner", "thermostat"],
                relativeTemperatureDelta: firstNumber ?? 1,
                relativeTemperatureDirection: direction
            )
            return
        }

        if LegacyTextParser.containsAny(normalized, ["temperature", "setpoint", "degrees"]) && firstNumber != nil {
            self.init(
                family: .temperature,
                intent: .setValue,
                capabilityPreferences: [
                    CapabilityCommand(capability: "thermostatCoolingSetpoint", command: "setCoolingSetpoint"),
                    CapabilityCommand(capability: "thermostatHeatingSetpoint", command: "setHeatingSetpoint")
                ],
                parameters: [
                    HomeResolvedParameter(name: "value", numericValue: Double(firstNumber ?? 0), unit: "degrees", confidence: 0.85)
                ],
                deviceTypeHints: ["air conditioner", "thermostat"],
                relativeTemperatureDelta: nil,
                relativeTemperatureDirection: 0
            )
            return
        }

        if LegacyTextParser.containsAny(normalized, ["brightness", "bright", "dim", "percent", "level"]) && firstNumber != nil {
            let isIncrease = LegacyTextParser.containsAny(normalized, ["increase", "raise", "brighter"])
            let isDecrease = LegacyTextParser.containsAny(normalized, ["decrease", "lower", "dim"])
            let command = isIncrease ? "increaseValue" : isDecrease ? "decreaseValue" : "setLevel"
            self.init(
                family: .brightness,
                intent: isIncrease ? .increaseValue : isDecrease ? .decreaseValue : .setValue,
                capabilityPreferences: [CapabilityCommand(capability: "switchLevel", command: command)],
                parameters: [
                    HomeResolvedParameter(name: "value", numericValue: Double(firstNumber ?? 0), unit: "percent", confidence: 0.9)
                ],
                deviceTypeHints: ["light"],
                relativeTemperatureDelta: nil,
                relativeTemperatureDirection: 0
            )
            return
        }

        if LegacyTextParser.containsAny(normalized, ["turn on", "switch on", "power on"]) {
            self.init(
                family: .power,
                intent: .turnOn,
                capabilityPreferences: [CapabilityCommand(capability: "switch", command: "on")],
                parameters: [],
                deviceTypeHints: Set(LegacyTextParser.deviceTypes(for: normalized).map(\.legacyNormalizedHomeTokenString)),
                relativeTemperatureDelta: nil,
                relativeTemperatureDirection: 0
            )
            return
        }

        if LegacyTextParser.containsAny(normalized, ["turn off", "switch off", "power off"]) {
            self.init(
                family: .power,
                intent: .turnOff,
                capabilityPreferences: [CapabilityCommand(capability: "switch", command: "off")],
                parameters: [],
                deviceTypeHints: Set(LegacyTextParser.deviceTypes(for: normalized).map(\.legacyNormalizedHomeTokenString)),
                relativeTemperatureDelta: nil,
                relativeTemperatureDirection: 0
            )
            return
        }

        return nil
    }

    private init(
        family: HomeAutomationIntentFamily,
        intent: HomeAutomationIntent,
        capabilityPreferences: [CapabilityCommand],
        parameters: [HomeResolvedParameter],
        deviceTypeHints: Set<String>,
        relativeTemperatureDelta: Int?,
        relativeTemperatureDirection: Int
    ) {
        self.family = family
        self.intent = intent
        self.capabilityPreferences = capabilityPreferences
        self.parameters = parameters
        self.deviceTypeHints = deviceTypeHints
        self.relativeTemperatureDelta = relativeTemperatureDelta
        self.relativeTemperatureDirection = relativeTemperatureDirection
    }

    func makeDraftIntent(for device: HomeCandidateRecord, normalized: String) -> DraftIntent? {
        guard let preference = capabilityPreferences.first(where: { device.capabilities.contains($0.capability) }) else {
            return nil
        }

        let parameters: [HomeResolvedParameter]
        if let delta = relativeTemperatureDelta {
            parameters = [
                HomeResolvedParameter(
                    name: "delta",
                    numericValue: Double(delta),
                    unit: "degrees",
                    confidence: 0.85
                )
            ]
        } else {
            parameters = self.parameters
        }

        return DraftIntent(
            intent: intent,
            capability: preference.capability,
            command: preference.command,
            parameters: parameters
        )
    }

}

private func statusCapabilityPreferences(for normalized: String) -> [CapabilityCommand] {
    if normalized.contains("battery") {
        return [CapabilityCommand(capability: "battery", command: "getStatus")]
    }
    if LegacyTextParser.containsAny(normalized, ["temperature", "hot", "cold"]) {
        return [CapabilityCommand(capability: "temperatureMeasurement", command: "getStatus")]
    }
    if normalized.contains("humidity") {
        return [CapabilityCommand(capability: "relativeHumidityMeasurement", command: "getStatus")]
    }
    if LegacyTextParser.containsAny(normalized, ["open", "closed", "door"]) {
        return [
            CapabilityCommand(capability: "contactSensor", command: "getStatus"),
            CapabilityCommand(capability: "garageDoorControl", command: "getStatus"),
            CapabilityCommand(capability: "lock", command: "getStatus")
        ]
    }
    return [
        CapabilityCommand(capability: "temperatureMeasurement", command: "getStatus"),
        CapabilityCommand(capability: "contactSensor", command: "getStatus"),
        CapabilityCommand(capability: "motionSensor", command: "getStatus"),
        CapabilityCommand(capability: "switch", command: "getStatus"),
        CapabilityCommand(capability: "battery", command: "getStatus")
    ]
}
