import Foundation
import HomeAutomationCore
import os

public struct CapabilityResolutionInput: Sendable {
    public let rawText: String
    public let resolutionState: HomeResolutionState
    public let hydratedCandidates: [HomeCandidateRecord]
    public let aggregation: HomeCandidateAggregationResult
    public let knowledgeSnippets: [KnowledgeSnippet]

    public init(
        rawText: String,
        resolutionState: HomeResolutionState,
        hydratedCandidates: [HomeCandidateRecord],
        aggregation: HomeCandidateAggregationResult,
        knowledgeSnippets: [KnowledgeSnippet]
    ) {
        self.rawText = rawText
        self.resolutionState = resolutionState
        self.hydratedCandidates = hydratedCandidates
        self.aggregation = aggregation
        self.knowledgeSnippets = knowledgeSnippets
    }
}

/// Selects the most likely device capability and command before draft generation.
///
/// This agent makes capability matching explicit and evaluation-friendly. It does
/// not replace draft generation or safety validation; it provides structured
/// guidance and evidence for those later stages.
public struct CapabilityResolutionAgent: HomeAgent {
    public typealias Input = CapabilityResolutionInput
    public typealias Output = HomeCapabilityDecision

    public let id = AgentID.capabilityResolution
    public let capabilities: Set<AgentCapability> = [.capabilityResolution]
    public let timeoutNanoseconds: UInt64 = 30_000_000_000
    private let resolve: @Sendable (CapabilityResolutionInput) async throws -> HomeCapabilityDecision
    private let logger = Logger(subsystem: "HomeAutomation", category: "Agent.CapabilityResolution")

    public init(
        resolve: @escaping @Sendable (CapabilityResolutionInput) async throws -> HomeCapabilityDecision
    ) {
        self.resolve = resolve
    }

    public init() {
        self.resolve = Self.resolveDeterministically
    }

    public func run(
        _ input: CapabilityResolutionInput,
        context: ResolutionContext
    ) async throws -> HomeCapabilityDecision {
        logger.debug("[run] Executing CapabilityResolutionAgent")
        return try await resolve(input)
    }

    private static func resolveDeterministically(_ input: CapabilityResolutionInput) -> HomeCapabilityDecision {
        let target = selectedDevice(from: input)
        let alternatives = rankedAlternatives(input: input, target: target)
        let selected = alternatives.first
        let evidence = selected?.evidence ?? ["No supported capability matched the command with high confidence."]

        return HomeCapabilityDecision(
            selectedCapability: selected?.capability,
            selectedCommand: selected?.command,
            targetDeviceID: selected?.targetDeviceID ?? target?.id,
            alternatives: alternatives,
            evidence: evidence,
            confidence: selected?.confidence ?? 0.2
        )
    }

    private static func selectedDevice(from input: CapabilityResolutionInput) -> HomeCandidateRecord? {
        for id in input.aggregation.finalCandidateIDs {
            if let candidate = input.hydratedCandidates.first(where: { $0.id == id }) {
                return candidate
            }
        }
        return input.hydratedCandidates.first
    }

    private static func rankedAlternatives(
        input: CapabilityResolutionInput,
        target: HomeCandidateRecord?
    ) -> [HomeCapabilityAlternative] {
        guard let target else { return [] }
        let normalized = input.rawText.agentNormalizedHomeTokenString
        let families = input.resolutionState.intent.topFamilies
        var alternatives: [HomeCapabilityAlternative] = []

        for capability in target.capabilities {
            let commands = target.supportedCommands[capability, default: HomeCapabilityRegistry.supportedCommands(for: capability)]
            let proposal = commandProposal(
                capability: capability,
                commands: commands,
                normalizedText: normalized,
                families: families,
                state: input.resolutionState
            )
            guard let proposal else { continue }
            let evidence = evidenceLines(
                capability: capability,
                command: proposal.command,
                device: target,
                input: input,
                baseEvidence: proposal.evidence
            )
            alternatives.append(
                HomeCapabilityAlternative(
                    capability: capability,
                    command: proposal.command,
                    targetDeviceID: target.id,
                    confidence: proposal.confidence,
                    evidence: evidence
                )
            )
        }

        return alternatives
            .sorted {
                if $0.confidence == $1.confidence {
                    return $0.capability < $1.capability
                }
                return $0.confidence > $1.confidence
            }
            .prefix(5)
            .map { $0 }
    }

    private static func commandProposal(
        capability: String,
        commands: [String],
        normalizedText: String,
        families: [HomeAutomationIntentFamily],
        state: HomeResolutionState
    ) -> (command: String?, confidence: Double, evidence: [String])? {
        let hasPowerIntent = families.contains(.power)
        let hasTemperatureIntent = families.contains(.temperature)
        let hasBrightnessIntent = families.contains(.brightness)
        let hasLockIntent = families.contains(.lockUnlock)
        let hasOpenCloseIntent = families.contains(.openClose)
        let hasStatusIntent = families.contains(.statusQuery)
        let hasRoutineIntent = families.contains(.routine)
        let hasTurnOn = containsAny(normalizedText, ["turn on", "switch on", "power on", "start"])
        let hasTurnOff = containsAny(normalizedText, ["turn off", "switch off", "power off", "stop"])

        if capability == "switch", hasPowerIntent || hasTurnOn || hasTurnOff {
            if hasTurnOff, commands.contains("off") {
                return ("off", 0.95, ["Power intent and off phrase matched switch.off."])
            }
            if hasTurnOn, commands.contains("on") {
                return ("on", 0.95, ["Power intent and on phrase matched switch.on."])
            }
        }

        if capability == "lock", hasLockIntent || containsAny(normalizedText, ["lock", "unlock"]) {
            if normalizedText.contains("unlock"), commands.contains("unlock") {
                return ("unlock", 0.92, ["Lock/unlock intent matched lock.unlock."])
            }
            if normalizedText.contains("lock"), commands.contains("lock") {
                return ("lock", 0.9, ["Lock/unlock intent matched lock.lock."])
            }
        }

        if hasOpenCloseIntent || containsAny(normalizedText, ["open", "close"]) {
            if normalizedText.contains("open"), commands.contains("open") {
                return ("open", 0.88, ["Open/close intent matched \(capability).open."])
            }
            if normalizedText.contains("close"), commands.contains("close") {
                return ("close", 0.88, ["Open/close intent matched \(capability).close."])
            }
        }

        if capability == "switchLevel", hasBrightnessIntent {
            if commands.contains("setLevel"), !state.slots.values.isEmpty {
                return ("setLevel", 0.84, ["Brightness intent and numeric value matched switchLevel.setLevel."])
            }
            if containsAny(normalizedText, ["increase", "raise", "brighter"]), commands.contains("increaseValue") {
                return ("increaseValue", 0.78, ["Brightness increase phrase matched switchLevel.increaseValue."])
            }
            if containsAny(normalizedText, ["decrease", "lower", "dim"]), commands.contains("decreaseValue") {
                return ("decreaseValue", 0.78, ["Brightness decrease phrase matched switchLevel.decreaseValue."])
            }
        }

        if hasTemperatureIntent {
            if capability == "switch", (hasTurnOn || hasTurnOff) {
                if hasTurnOff, commands.contains("off") {
                    return ("off", 0.9, ["Temperature device power-off phrase matched switch.off."])
                }
                if hasTurnOn, commands.contains("on") {
                    return ("on", 0.9, ["Temperature device power-on phrase matched switch.on."])
                }
            }
            if capability == "thermostatCoolingSetpoint", commands.contains("setCoolingSetpoint"), !state.slots.values.isEmpty {
                return ("setCoolingSetpoint", 0.86, ["Temperature value matched thermostatCoolingSetpoint.setCoolingSetpoint."])
            }
            if capability == "thermostatHeatingSetpoint", commands.contains("setHeatingSetpoint"), !state.slots.values.isEmpty {
                return ("setHeatingSetpoint", 0.78, ["Temperature value matched thermostatHeatingSetpoint.setHeatingSetpoint."])
            }
            if capability == "airConditionerMode", commands.contains("setAirConditionerMode"), !state.slots.modes.isEmpty {
                return ("setAirConditionerMode", 0.76, ["AC mode phrase matched airConditionerMode.setAirConditionerMode."])
            }
            if capability == "airConditionerFanMode", commands.contains("setFanMode"), containsAny(normalizedText, ["fan", "speed"]) {
                return ("setFanMode", 0.74, ["Fan mode phrase matched airConditionerFanMode.setFanMode."])
            }
        }

        if hasStatusIntent || containsAny(normalizedText, ["status", "check", "what is", "showing", "reading"]) {
            if commands.contains("getStatus") {
                return ("getStatus", 0.82, ["Status query matched \(capability).getStatus."])
            }
            if HomeCapabilityRegistry.definitions[capability]?.attributeNames.isEmpty == false {
                return ("getStatus", 0.72, ["Status query matched readable attribute for \(capability)."])
            }
        }

        if hasRoutineIntent, commands.contains("run") {
            return ("run", 0.8, ["Routine intent matched run command."])
        }

        return nil
    }

    private static func evidenceLines(
        capability: String,
        command: String?,
        device: HomeCandidateRecord,
        input: CapabilityResolutionInput,
        baseEvidence: [String]
    ) -> [String] {
        var evidence = baseEvidence
        evidence.append("Target device \(device.id) supports capability \(capability).")
        if let command {
            evidence.append("Target device \(device.id) supports command \(command): \(device.supportedCommands[capability, default: []].contains(command)).")
        }
        if !input.knowledgeSnippets.isEmpty {
            let matchedSources = input.knowledgeSnippets
                .filter { snippet in
                    snippet.content.agentNormalizedHomeTokenString.contains(capability.agentNormalizedHomeTokenString)
                }
                .prefix(3)
                .map(\.sourceID)
            if !matchedSources.isEmpty {
                evidence.append("RAG sources mention capability: \(matchedSources.joined(separator: ", ")).")
            }
        }
        return evidence
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
