import Foundation
import HomeAutomationCore
import HomeAutomationRAG

/// Deterministic rule-based resolver using keyword matching, scoring, and Bixby catalog lookup.
///
/// `AgentRuleBasedResolver` is used by `RuleFallbackAgent` when Foundation Models are
/// unavailable. It provides full command resolution through:
/// 1. Keyword-based intent detection via `AgentRuleIntent`
/// 2. Device scoring via token overlap and capability matching
/// 3. Bixby catalog fallback via `AgentBixbyFallbackMapper`
/// 4. Deterministic safety validation via `AgentCommandValidator`
/// 5. Low-risk execution via `AgentPlanExecutor`
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
            case .automationPattern, .automationRuleExample, .automationConditionOperator, .smartThingsRuleSchema:
                continue
            }
        }

        return AgentSemanticHints(
            preferredDeviceIDs: deviceIDs,
            preferredCapabilityIDs: capabilityIDs,
            preferredCommands: commands
        )
    }
}
