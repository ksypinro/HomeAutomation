import Foundation
import HomeAutomationCore
import HomeAutomationRAG

public struct RuleFallbackInput: Sendable, Hashable {
    public let text: String
    public let executeLowRiskCommands: Bool
    public let memoryHints: [MemoryHint]

    public init(
        text: String,
        executeLowRiskCommands: Bool = true,
        memoryHints: [MemoryHint] = []
    ) {
        self.text = text
        self.executeLowRiskCommands = executeLowRiskCommands
        self.memoryHints = memoryHints
    }
}

public struct AgentRuleBasedResolver: HomeCommandResolving {
    private let registry: MockHomeDeviceRegistry
    private let validator: AgentCommandValidator
    private let executor: AgentPlanExecutor
    private let bixbyFallbackMapper: AgentBixbyFallbackMapper
    private let contextRetriever: ContextRetriever?

    public init(
        registry: MockHomeDeviceRegistry = MockHomeDeviceRegistry(),
        validator: AgentCommandValidator = AgentCommandValidator(),
        bixbyFallbackMapper: AgentBixbyFallbackMapper = AgentBixbyFallbackMapper(),
        contextRetriever: ContextRetriever? = nil
    ) {
        self.registry = registry
        self.validator = validator
        self.executor = AgentPlanExecutor(registry: registry)
        self.bixbyFallbackMapper = bixbyFallbackMapper
        self.contextRetriever = contextRetriever
    }

    public func resolve(_ text: String, executeLowRiskCommands: Bool) async throws -> HomeAutomationResolverResult {
        try await resolve(text, executeLowRiskCommands: executeLowRiskCommands, memoryHints: [])
    }

    public func resolve(
        _ text: String,
        executeLowRiskCommands: Bool = true,
        memoryHints: [MemoryHint] = []
    ) async throws -> HomeAutomationResolverResult {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw FoundationLabCoreError.invalidRequest("Missing home command")
        }

        let state = AgentTextParser.deterministicState(
            for: trimmedText,
            confidence: 0.65,
            riskReason: "Agent rule-based classification"
        )
        guard state.domain.domain == .homeAutomation else {
            return unsupportedResult(for: trimmedText)
        }

        let devices = await registry.allDevices()
        let normalized = trimmedText.agentNormalizedHomeTokenString
        let semanticHints = await semanticHints(for: trimmedText, memoryHints: memoryHints)

        if let ruleIntent = AgentRuleIntent(normalized: normalized),
           let result = try await resolveRuleIntent(
            ruleIntent,
            text: trimmedText,
            normalized: normalized,
            state: state,
            devices: devices,
            semanticHints: semanticHints,
            executeLowRiskCommands: executeLowRiskCommands
           ) {
            return result
        }

        if let result = try await resolveBixby(
            trimmedText,
            state: state,
            devices: devices,
            executeLowRiskCommands: executeLowRiskCommands
        ) {
            return result
        }

        return clarificationResult(
            for: trimmedText,
            state: state,
            retrievedCandidates: Array(devices.prefix(8)),
            question: "Which device do you want to control?"
        )
    }

    private func resolveRuleIntent(
        _ intent: AgentRuleIntent,
        text: String,
        normalized: String,
        state: HomeResolutionState,
        devices: [HomeCandidateRecord],
        semanticHints: AgentSemanticHints,
        executeLowRiskCommands: Bool
    ) async throws -> HomeAutomationResolverResult? {
        let scored = devices.compactMap { device -> AgentScoredDevice? in
            guard let draftIntent = intent.makeDraftIntent(for: device) else { return nil }
            let score = score(device, for: intent, normalized: normalized, semanticHints: semanticHints)
            guard score > 0 else { return nil }
            return AgentScoredDevice(device: device, draftIntent: draftIntent, score: score)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.device.displayName < rhs.device.displayName
            }
            return lhs.score > rhs.score
        }

        guard let selected = scored.first else { return nil }
        let secondScore = scored.dropFirst().first?.score ?? 0
        let isAmbiguous = selected.score < 8 || (secondScore > 0 && selected.score - secondScore < 2)
        if isAmbiguous {
            return clarificationResult(
                for: text,
                state: state,
                retrievedCandidates: scored.prefix(8).map(\.device),
                question: "Which \(selected.device.deviceType) do you mean?"
            )
        }

        let aggregation = HomeCandidateAggregationResult(
            finalCandidateIDs: [selected.device.id],
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

    private func resolveBixby(
        _ text: String,
        state: HomeResolutionState,
        devices: [HomeCandidateRecord],
        executeLowRiskCommands: Bool
    ) async throws -> HomeAutomationResolverResult? {
        let matches = bixbyFallbackMapper.matches(text: text, devices: devices)
        guard let selected = matches.first else { return nil }

        let secondScore = matches.dropFirst().first?.score ?? 0
        if secondScore > 0 && selected.score - secondScore < 2 {
            return clarificationResult(
                for: text,
                state: state,
                retrievedCandidates: matches.prefix(8).map(\.device),
                question: "Which device do you mean?"
            )
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

    private func unsupportedResult(for text: String) -> HomeAutomationResolverResult {
        let state = AgentTextParser.deterministicState(
            for: text,
            confidence: 0.4,
            riskReason: "Agent rule-based fallback could not map the command"
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
            resolution: .unsupported("Agent rule-based fallback could not map this command.")
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
        for intent: AgentRuleIntent,
        normalized: String,
        semanticHints: AgentSemanticHints
    ) -> Int {
        let queryTokens = normalized.agentTokenSet
        let name = device.displayName.agentNormalizedHomeTokenString
        let nameTokens = name.agentTokenSet
        let type = device.deviceType.agentNormalizedHomeTokenString
        let room = device.room?.agentNormalizedHomeTokenString
        let aliases = device.metadata["aliases"]?
            .split(separator: ",")
            .map { String($0).agentNormalizedHomeTokenString } ?? []

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

        if semanticHints.preferredDeviceIDs.contains(device.id) {
            total += 8
        }
        if !semanticHints.preferredCapabilityIDs.isDisjoint(with: Set(device.capabilities)) {
            total += 4
        }

        if device.type == .routine, intent.family == .routine {
            total += 8
        }

        return total
    }

    private func semanticHints(for text: String, memoryHints: [MemoryHint]) async -> AgentSemanticHints {
        var deviceIDs = Set(memoryHints.compactMap(\.deviceID))
        var capabilityIDs = Set(memoryHints.compactMap(\.capability))
        var commands = Set<String>()

        guard let contextRetriever else {
            return AgentSemanticHints(
                preferredDeviceIDs: deviceIDs,
                preferredCapabilityIDs: capabilityIDs,
                preferredCommands: commands
            )
        }

        let chunks = await contextRetriever.retrieve(query: text, topK: 5)


        for scored in chunks where scored.score > 0 {
            switch scored.chunk.source {
            case .device:
                if let id = scored.chunk.metadata["deviceId"] {
                    deviceIDs.insert(id)
                }
                if let capabilities = scored.chunk.metadata["capabilities"] {
                    capabilityIDs.formUnion(capabilities.split(separator: ",").map(String.init))
                }
            case .capability:
                if let id = scored.chunk.metadata["capabilityId"] {
                    capabilityIDs.insert(id)
                }
            case .nlDataset:
                if let capability = scored.chunk.metadata["capability"] {
                    capabilityIDs.insert(capability)
                }
                if let command = scored.chunk.metadata["command"] {
                    commands.insert(command)
                }
            case .bixbyCommand:
                if let capability = scored.chunk.metadata["capability"] {
                    capabilityIDs.insert(capability)
                }
                if let action = scored.chunk.metadata["action"] {
                    commands.insert(action)
                }
            }
        }

        return AgentSemanticHints(
            preferredDeviceIDs: deviceIDs,
            preferredCapabilityIDs: capabilityIDs,
            preferredCommands: commands
        )
    }
}

public struct RuleFallbackAgent: HomeAgent {
    public typealias Input = RuleFallbackInput
    public typealias Output = HomeAutomationResolverResult

    public let id = AgentID.ruleFallback
    public let capabilities: Set<AgentCapability> = [.ruleFallback]
    public let timeoutNanoseconds: UInt64 = 5_000_000_000
    private let resolve: @Sendable (RuleFallbackInput) async throws -> HomeAutomationResolverResult

    public init(resolve: @escaping @Sendable (RuleFallbackInput) async throws -> HomeAutomationResolverResult) {
        self.resolve = resolve
    }

    public init(resolver: AgentRuleBasedResolver = AgentRuleBasedResolver()) {
        self.resolve = { input in
            try await resolver.resolve(
                input.text,
                executeLowRiskCommands: input.executeLowRiskCommands,
                memoryHints: input.memoryHints
            )
        }
    }

    public func run(_ input: RuleFallbackInput, context: ResolutionContext) async throws -> HomeAutomationResolverResult {
        try await resolve(input)
    }
}

public struct UnsupportedCommandAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = HomeCommandResolution

    public let id = AgentID.unsupportedCommand
    public let capabilities: Set<AgentCapability> = [.unsupported]
    public let timeoutNanoseconds: UInt64 = 1_000_000_000
    private let reasonBuilder: @Sendable (String) -> String

    public init(reasonBuilder: @escaping @Sendable (String) -> String = { _ in "This command is not supported." }) {
        self.reasonBuilder = reasonBuilder
    }

    public func run(_ input: String, context: ResolutionContext) async throws -> HomeCommandResolution {
        .unsupported(reasonBuilder(input))
    }
}

private struct AgentScoredDevice {
    let device: HomeCandidateRecord
    let draftIntent: AgentDraftIntent
    let score: Int
}

private struct AgentDraftIntent {
    let intent: HomeAutomationIntent
    let capability: String
    let command: String
    let parameters: [HomeResolvedParameter]
}

private struct AgentCapabilityCommand {
    let capability: String
    let command: String
}

private struct AgentSemanticHints {
    let preferredDeviceIDs: Set<String>
    let preferredCapabilityIDs: Set<String>
    let preferredCommands: Set<String>

    init(
        preferredDeviceIDs: Set<String> = [],
        preferredCapabilityIDs: Set<String> = [],
        preferredCommands: Set<String> = []
    ) {
        self.preferredDeviceIDs = preferredDeviceIDs
        self.preferredCapabilityIDs = preferredCapabilityIDs
        self.preferredCommands = preferredCommands
    }
}

private struct AgentRuleIntent {
    let family: HomeAutomationIntentFamily
    let intent: HomeAutomationIntent
    let capabilityPreferences: [AgentCapabilityCommand]
    let parameters: [HomeResolvedParameter]
    let deviceTypeHints: Set<String>

    init?(normalized: String) {
        let numbers = AgentTextParser.extractedNumbers(from: normalized)
        let firstNumber = numbers.first

        if AgentTextParser.containsAny(normalized, ["movie time", "good night", "routine", "scene"]) {
            self.init(family: .routine, intent: .runRoutine, capabilityPreferences: [.init(capability: "routine", command: "run")], parameters: [], deviceTypeHints: ["routine"])
            return
        }
        if normalized.contains("unlock") || normalized.contains("open the lock") {
            self.init(family: .lockUnlock, intent: .unlock, capabilityPreferences: [.init(capability: "lock", command: "unlock")], parameters: [], deviceTypeHints: ["lock"])
            return
        }
        if normalized.contains("lock") || normalized.contains("secure") {
            self.init(family: .lockUnlock, intent: .lock, capabilityPreferences: [.init(capability: "lock", command: "lock")], parameters: [], deviceTypeHints: ["lock"])
            return
        }
        if AgentTextParser.containsAny(normalized, ["open", "raise"]) &&
            AgentTextParser.containsAny(normalized, ["door", "garage", "blind", "shade", "valve"]) {
            self.init(
                family: .openClose,
                intent: .open,
                capabilityPreferences: [
                    .init(capability: "garageDoorControl", command: "open"),
                    .init(capability: "doorControl", command: "open"),
                    .init(capability: "windowShade", command: "open"),
                    .init(capability: "valve", command: "open")
                ],
                parameters: [],
                deviceTypeHints: ["garage door", "door", "blind", "valve"]
            )
            return
        }
        if AgentTextParser.containsAny(normalized, ["close", "lower"]) &&
            AgentTextParser.containsAny(normalized, ["door", "garage", "blind", "shade", "valve"]) {
            self.init(
                family: .openClose,
                intent: .close,
                capabilityPreferences: [
                    .init(capability: "garageDoorControl", command: "close"),
                    .init(capability: "doorControl", command: "close"),
                    .init(capability: "windowShade", command: "close"),
                    .init(capability: "valve", command: "close")
                ],
                parameters: [],
                deviceTypeHints: ["garage door", "door", "blind", "valve"]
            )
            return
        }
        if AgentTextParser.containsAny(normalized, ["status", "check", "what is", "is the", "tell me", "battery"]) {
            self.init(
                family: .statusQuery,
                intent: .getStatus,
                capabilityPreferences: statusCapabilityPreferences(for: normalized),
                parameters: [],
                deviceTypeHints: Set(AgentTextParser.deviceTypes(for: normalized).map(\.agentNormalizedHomeTokenString))
            )
            return
        }
        if AgentTextParser.containsAny(normalized, ["cooler", "warmer"]) {
            let direction = normalized.contains("cooler") ? -1 : 1
            self.init(
                family: .temperature,
                intent: direction < 0 ? .decreaseValue : .increaseValue,
                capabilityPreferences: [
                    .init(capability: "thermostatCoolingSetpoint", command: "setCoolingSetpoint"),
                    .init(capability: "thermostatHeatingSetpoint", command: "setHeatingSetpoint")
                ],
                parameters: [
                    HomeResolvedParameter(name: "delta", numericValue: Double(firstNumber ?? 1), unit: "degrees", confidence: 0.85)
                ],
                deviceTypeHints: ["air conditioner", "thermostat"]
            )
            return
        }
        if AgentTextParser.containsAny(normalized, ["temperature", "setpoint", "degrees"]) && firstNumber != nil {
            self.init(
                family: .temperature,
                intent: .setValue,
                capabilityPreferences: [
                    .init(capability: "thermostatCoolingSetpoint", command: "setCoolingSetpoint"),
                    .init(capability: "thermostatHeatingSetpoint", command: "setHeatingSetpoint")
                ],
                parameters: [
                    HomeResolvedParameter(name: "value", numericValue: Double(firstNumber ?? 0), unit: "degrees", confidence: 0.85)
                ],
                deviceTypeHints: ["air conditioner", "thermostat"]
            )
            return
        }
        if AgentTextParser.containsAny(normalized, ["brightness", "bright", "dim", "percent", "level"]) && firstNumber != nil {
            let isIncrease = AgentTextParser.containsAny(normalized, ["increase", "raise", "brighter"])
            let isDecrease = AgentTextParser.containsAny(normalized, ["decrease", "lower", "dim"])
            let command = isIncrease ? "increaseValue" : isDecrease ? "decreaseValue" : "setLevel"
            self.init(
                family: .brightness,
                intent: isIncrease ? .increaseValue : isDecrease ? .decreaseValue : .setValue,
                capabilityPreferences: [.init(capability: "switchLevel", command: command)],
                parameters: [
                    HomeResolvedParameter(name: "value", numericValue: Double(firstNumber ?? 0), unit: "percent", confidence: 0.9)
                ],
                deviceTypeHints: ["light"]
            )
            return
        }
        if AgentTextParser.containsAny(normalized, ["turn on", "switch on", "power on"]) {
            self.init(
                family: .power,
                intent: .turnOn,
                capabilityPreferences: [.init(capability: "switch", command: "on")],
                parameters: [],
                deviceTypeHints: Set(AgentTextParser.deviceTypes(for: normalized).map(\.agentNormalizedHomeTokenString))
            )
            return
        }
        if AgentTextParser.containsAny(normalized, ["turn off", "switch off", "power off"]) {
            self.init(
                family: .power,
                intent: .turnOff,
                capabilityPreferences: [.init(capability: "switch", command: "off")],
                parameters: [],
                deviceTypeHints: Set(AgentTextParser.deviceTypes(for: normalized).map(\.agentNormalizedHomeTokenString))
            )
            return
        }

        return nil
    }

    private init(
        family: HomeAutomationIntentFamily,
        intent: HomeAutomationIntent,
        capabilityPreferences: [AgentCapabilityCommand],
        parameters: [HomeResolvedParameter],
        deviceTypeHints: Set<String>
    ) {
        self.family = family
        self.intent = intent
        self.capabilityPreferences = capabilityPreferences
        self.parameters = parameters
        self.deviceTypeHints = deviceTypeHints
    }

    func makeDraftIntent(for device: HomeCandidateRecord) -> AgentDraftIntent? {
        guard let preference = capabilityPreferences.first(where: { device.capabilities.contains($0.capability) }) else {
            return nil
        }
        return AgentDraftIntent(
            intent: intent,
            capability: preference.capability,
            command: preference.command,
            parameters: parameters
        )
    }
}

private func statusCapabilityPreferences(for normalized: String) -> [AgentCapabilityCommand] {
    if normalized.contains("battery") {
        return [AgentCapabilityCommand(capability: "battery", command: "getStatus")]
    }
    if AgentTextParser.containsAny(normalized, ["temperature", "hot", "cold"]) {
        return [AgentCapabilityCommand(capability: "temperatureMeasurement", command: "getStatus")]
    }
    if normalized.contains("humidity") {
        return [AgentCapabilityCommand(capability: "relativeHumidityMeasurement", command: "getStatus")]
    }
    if AgentTextParser.containsAny(normalized, ["open", "closed", "door"]) {
        return [
            AgentCapabilityCommand(capability: "contactSensor", command: "getStatus"),
            AgentCapabilityCommand(capability: "garageDoorControl", command: "getStatus"),
            AgentCapabilityCommand(capability: "lock", command: "getStatus")
        ]
    }
    return [
        AgentCapabilityCommand(capability: "temperatureMeasurement", command: "getStatus"),
        AgentCapabilityCommand(capability: "contactSensor", command: "getStatus"),
        AgentCapabilityCommand(capability: "motionSensor", command: "getStatus"),
        AgentCapabilityCommand(capability: "switch", command: "getStatus"),
        AgentCapabilityCommand(capability: "battery", command: "getStatus")
    ]
}
