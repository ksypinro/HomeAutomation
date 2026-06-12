import Foundation
import FoundationModels
import HomeAutomationCore
import os

@Generable
public struct CapabilityResolutionFMCapabilityHypothesis: Sendable, Hashable, Codable {
    @Guide(description: "Canonical capability name returned by getAllCapabilities.")
    public let capability: String

    @Guide(description: "Candidate device IDs that likely support the requested command through this capability.", .maximumCount(5))
    public let likelyDeviceIDs: [String]

    @Guide(description: "Model-assigned likelihood score from 0.0 to 1.0.", .range(0.0...1.0))
    public let score: Double

    @Guide(description: "Short evidence explaining why this capability is likely.", .maximumCount(4))
    public let evidence: [String]

    public init(
        capability: String,
        likelyDeviceIDs: [String],
        score: Double,
        evidence: [String]
    ) {
        self.capability = capability
        self.likelyDeviceIDs = likelyDeviceIDs
        self.score = score
        self.evidence = evidence
    }
}

@Generable
public struct CapabilityResolutionFMTriplet: Sendable, Hashable, Codable {
    @Guide(description: "Device ID from the candidate device list.")
    public let deviceID: String?

    @Guide(description: "Canonical capability name from one of the top capability hypotheses.")
    public let capability: String?

    @Guide(description: "Canonical command name supported by the selected device capability, or getStatus for status queries.")
    public let command: String?

    @Guide(description: "Model-assigned triplet score from 0.0 to 1.0.", .range(0.0...1.0))
    public let score: Double

    @Guide(description: "Short evidence explaining why this device/capability/command triplet matches.", .maximumCount(5))
    public let evidence: [String]

    public init(
        deviceID: String?,
        capability: String?,
        command: String?,
        score: Double,
        evidence: [String]
    ) {
        self.deviceID = deviceID
        self.capability = capability
        self.command = command
        self.score = score
        self.evidence = evidence
    }
}

@Generable
public struct CapabilityResolutionFMOutput: Sendable, Hashable, Codable {
    @Guide(description: "The model-ranked top capability hypotheses. Keep at most 5.", .maximumCount(5))
    public let topCapabilities: [CapabilityResolutionFMCapabilityHypothesis]

    @Guide(description: "The final selected device/capability/command triplet.")
    public let selectedTriplet: CapabilityResolutionFMTriplet?

    @Guide(description: "Ranked backup triplets when there is ambiguity. Keep at most 5.", .maximumCount(5))
    public let alternativeTriplets: [CapabilityResolutionFMTriplet]

    public init(
        topCapabilities: [CapabilityResolutionFMCapabilityHypothesis],
        selectedTriplet: CapabilityResolutionFMTriplet?,
        alternativeTriplets: [CapabilityResolutionFMTriplet]
    ) {
        self.topCapabilities = topCapabilities
        self.selectedTriplet = selectedTriplet
        self.alternativeTriplets = alternativeTriplets
    }
}

/// Model-backed capability and command resolver.
///
/// The worker uses Foundation Models with tools to inspect candidate devices,
/// rank the five most likely capabilities, and then select a final
/// device/capability/command triplet. Model output is treated as a proposal:
/// it must validate against hydrated candidates before it becomes a
/// `HomeCapabilityDecision`; otherwise deterministic resolution is used.
public final class CapabilityResolutionWorker: Sendable {
    private let foundationModelAvailability: @Sendable () -> Bool
    private let resolve: (@Sendable (CapabilityResolutionInput) async throws -> CapabilityResolutionFMOutput)?
    private let outputSizeStore: AgentToolOutputSizeStore
    private let logger = Logger(subsystem: "HomeAutomation", category: "Agent.CapabilityResolutionWorker")

    public init(
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        resolve: (@Sendable (CapabilityResolutionInput) async throws -> CapabilityResolutionFMOutput)? = nil,
        outputSizeStore: AgentToolOutputSizeStore = .shared
    ) {
        self.foundationModelAvailability = foundationModelAvailability
        self.resolve = resolve
        self.outputSizeStore = outputSizeStore
    }

    public func resolve(_ input: CapabilityResolutionInput) async throws -> HomeCapabilityDecision {
        let fallback = CapabilityResolutionAgent.resolveDeterministically(input)

        if let resolve {
            return Self.validatedDecision(
                from: try await resolve(input),
                input: input,
                fallback: fallback
            )
        }

        guard foundationModelAvailability() else {
            logger.info("[Availability] Foundation model unavailable, using deterministic capability fallback.")
            return fallback
        }

        let candidateDetailsTool = CapabilityCandidateDeviceDetailsTool(
            candidates: input.hydratedCandidates,
            outputSizeStore: outputSizeStore
        )
        let capabilitiesTool = CapabilityAllCapabilitiesTool(
            candidates: input.hydratedCandidates,
            outputSizeStore: outputSizeStore
        )
        let tools: [any Tool] = [candidateDetailsTool, capabilitiesTool]

        let instructions = HomeAutomationToolTraceInstructions.append(to: Self.instructions)
        let prompt = Self.prompt(input: input, fallback: fallback)
        logger.debug("[FoundationModelInput] System Instructions: \(instructions, privacy: .public)")
        logger.debug("[FoundationModelInput] Prompt: \(prompt, privacy: .public)")

        let session = LanguageModelSession(
            tools: tools,
            instructions: Instructions(instructions)
        )

        do {
            let output = try await FoundationModelCallRecorder.record(
                agentID: AgentID.capabilityResolution.rawValue,
                policyMode: "model-first-with-deterministic-fallback",
                modelAvailability: "available",
                promptCharacterCount: instructions.count + prompt.count,
                selectedToolNames: tools.map(\.name),
                estimatedToolOutputCharacterCount: Self.estimatedToolOutputCharacters(
                    candidates: input.hydratedCandidates,
                    outputSizeStore: outputSizeStore
                )
            ) {
                try await session.respond(
                    to: Prompt(prompt),
                    generating: CapabilityResolutionFMOutput.self
                ).content
            }
            let decision = Self.validatedDecision(from: output, input: input, fallback: fallback)
            logger.debug("[FoundationModelOutput] result: \(String(describing: decision), privacy: .public)")
            return decision
        } catch {
            logger.error("[FoundationModelError] error: \(error.localizedDescription, privacy: .public), using deterministic capability fallback.")
            return fallback
        }
    }

    private static let instructions = """
    You are a smart-home capability and command resolver.

    Your task: choose the target device, canonical capability, and canonical command for one direct device command.

    Required runtime tool workflow:
    1. FIRST call getCapabilityCandidateDeviceDetails to inspect candidate IDs, rooms, names, device types, capabilities, and state.
    2. THEN call getAllCapabilities with the plausible candidate device IDs. If uncertain, pass all candidate IDs.
    3. Rank the top 5 most probable capabilities as device-aware hypotheses. A hypothesis must include the likely device IDs for that capability.
    4. Only after ranking top capabilities, generate candidate device/capability/command triplets internally from those top capabilities and the tool-returned commands.
    5. Score triplets jointly using the user text, device identity, capability meaning, command meaning, slots, room, and device type. Return the best triplet and up to 5 alternatives.

    Hard rules:
    - Use only candidate device IDs from the prompt or tool output.
    - Use only capabilities returned by getAllCapabilities for the chosen device.
    - Use only commands returned for that device/capability row. For status queries, getStatus is allowed when the row has readable attributes.
    - Do not require the app to enumerate every device/capability/command combination for you. Build and score the plausible triplets yourself after ranking top capabilities.
    - Never invent capability names such as "volume" when the canonical capability is "audioVolume".
    - Return internal canonical strings, not natural-language labels.
    - If the command is ambiguous, return the best low-confidence decision plus alternatives.
    - Keep evidence short and grounded in the command text and tool outputs.

    Media examples:
    - "move to next channel in living room TV" -> capability channel, command channelUp.
    - "go to channel 101 on living room TV" -> capability channel, command setChannel.
    - "turn up living room TV volume" -> capability audioVolume, command volumeUp.
    - "mute living room TV" -> capability audioVolume, command mute.
    - "play living room TV" -> capability mediaPlayback, command play.
    - "set living room TV input to HDMI 1" -> capability mediaInputSource, command setInputSource.
    """

    private static func prompt(input: CapabilityResolutionInput, fallback: HomeCapabilityDecision) -> String {
        let candidateIDs = input.hydratedCandidates.map(\.id).joined(separator: ", ")
        let candidateSummary = input.hydratedCandidates.prefix(12).map { candidate in
            "- id=\(candidate.id), name=\(candidate.displayName), type=\(candidate.deviceType), room=\(candidate.room ?? "none"), capabilities=\(candidate.capabilities.joined(separator: ","))"
        }
        .joined(separator: "\n")
        let knowledge = input.knowledgeSnippets.prefix(5).map { "- \($0.sourceID): \($0.content)" }.joined(separator: "\n")
        return """
        User command:
        \(input.rawText)

        Resolution state:
        intentFamilies: \(input.resolutionState.intent.topFamilies.map { String(describing: $0) }.joined(separator: ","))
        deviceTypes: \(input.resolutionState.deviceType.deviceTypes.joined(separator: ","))
        rooms: \(input.resolutionState.slots.rooms.joined(separator: ","))
        values: \(input.resolutionState.slots.values.map { "\($0.name)=\($0.rawValue)" }.joined(separator: ","))
        modes: \(input.resolutionState.slots.modes.joined(separator: ","))
        risk: \(String(describing: input.resolutionState.risk.riskLevel))

        Candidate IDs selected by ranking:
        \(input.aggregation.finalCandidateIDs.joined(separator: ", "))

        Hydrated candidate summary:
        \(candidateSummary.isEmpty ? "- none" : candidateSummary)

        All candidate IDs available to tools:
        \(candidateIDs.isEmpty ? "none" : candidateIDs)

        Knowledge snippets:
        \(knowledge.isEmpty ? "- none" : knowledge)

        Deterministic fallback hint:
        targetDeviceID: \(fallback.targetDeviceID ?? "none")
        selectedCapability: \(fallback.selectedCapability ?? "none")
        selectedCommand: \(fallback.selectedCommand ?? "none")
        confidence: \(fallback.confidence)
        evidence: \(fallback.evidence.joined(separator: " | "))

        Verify the fallback with tools. Correct it when the tool evidence supports a better canonical capability or command.
        """
    }

    private static func estimatedToolOutputCharacters(
        candidates: [HomeCandidateRecord],
        outputSizeStore: AgentToolOutputSizeStore
    ) -> Int {
        outputSizeStore.estimate(
            toolName: "getCapabilityCandidateDeviceDetails",
            fallback: max(600, min(candidates.count, 12) * 280)
        ) + outputSizeStore.estimate(
            toolName: "getAllCapabilities",
            fallback: max(900, min(candidates.count, 12) * 420)
        )
    }

    private static func validatedDecision(
        from output: CapabilityResolutionFMOutput,
        input: CapabilityResolutionInput,
        fallback: HomeCapabilityDecision
    ) -> HomeCapabilityDecision {
        guard let selectedTriplet = output.selectedTriplet,
              let targetDeviceID = selectedTriplet.deviceID?.trimmedNonEmpty,
              let selectedCapability = selectedTriplet.capability?.trimmedNonEmpty,
              let selectedCommand = selectedTriplet.command?.trimmedNonEmpty,
              let device = input.hydratedCandidates.first(where: { $0.id == targetDeviceID }),
              topCapabilitiesContain(output.topCapabilities, capability: selectedCapability, deviceID: targetDeviceID),
              isSupported(device: device, capability: selectedCapability, command: selectedCommand) else {
            return fallbackWithRejectionEvidence(
                fallback,
                reason: "FoundationModel capability proposal failed validation."
            )
        }

        let alternatives = stableAlternatives(
            from: output,
            input: input,
            selected: (targetDeviceID, selectedCapability, selectedCommand)
        )
        let evidence = selectedTriplet.evidence.isEmpty
            ? ["FoundationModel selected \(selectedCapability).\(selectedCommand) for \(targetDeviceID) after ranking top capabilities."]
            : selectedTriplet.evidence
        let selectedAlternative = HomeCapabilityAlternative(
            capability: selectedCapability,
            command: selectedCommand,
            targetDeviceID: targetDeviceID,
            confidence: boundedConfidence(selectedTriplet.score),
            evidence: evidence
        )
        return HomeCapabilityDecision(
            selectedCapability: selectedCapability,
            selectedCommand: selectedCommand,
            targetDeviceID: targetDeviceID,
            alternatives: stableUniqueAlternatives([selectedAlternative] + alternatives),
            evidence: evidence,
            confidence: boundedConfidence(selectedTriplet.score)
        )
    }

    private static func stableAlternatives(
        from output: CapabilityResolutionFMOutput,
        input: CapabilityResolutionInput,
        selected: (targetDeviceID: String, capability: String, command: String)
    ) -> [HomeCapabilityAlternative] {
        output.alternativeTriplets.compactMap { alternative in
            guard let targetDeviceID = alternative.deviceID?.trimmedNonEmpty,
                  let capability = alternative.capability?.trimmedNonEmpty,
                  let command = alternative.command?.trimmedNonEmpty,
                  (targetDeviceID, capability, command) != selected,
                  let device = input.hydratedCandidates.first(where: { $0.id == targetDeviceID }),
                  isSupported(device: device, capability: capability, command: command) else {
                return nil
            }
            return HomeCapabilityAlternative(
                capability: capability,
                command: command,
                targetDeviceID: targetDeviceID,
                confidence: boundedConfidence(alternative.score),
                evidence: alternative.evidence
            )
        }
    }

    private static func isSupported(
        device: HomeCandidateRecord,
        capability: String,
        command: String
    ) -> Bool {
        guard device.capabilities.contains(capability) else { return false }
        let supportedCommands = device.supportedCommands[
            capability,
            default: HomeCapabilityRegistry.supportedCommands(for: capability)
        ]
        if supportedCommands.contains(command) { return true }
        if command == "getStatus",
           let definition = HomeCapabilityRegistry.definitions[capability],
           !definition.attributeNames.isEmpty {
            return true
        }
        return false
    }

    private static func topCapabilitiesContain(
        _ topCapabilities: [CapabilityResolutionFMCapabilityHypothesis],
        capability: String,
        deviceID: String
    ) -> Bool {
        topCapabilities.contains { hypothesis in
            hypothesis.capability == capability
                && (hypothesis.likelyDeviceIDs.isEmpty || hypothesis.likelyDeviceIDs.contains(deviceID))
        }
    }

    private static func fallbackWithRejectionEvidence(
        _ fallback: HomeCapabilityDecision,
        reason: String
    ) -> HomeCapabilityDecision {
        HomeCapabilityDecision(
            selectedCapability: fallback.selectedCapability,
            selectedCommand: fallback.selectedCommand,
            targetDeviceID: fallback.targetDeviceID,
            alternatives: fallback.alternatives,
            evidence: fallback.evidence + [reason],
            confidence: fallback.confidence
        )
    }

    private static func boundedConfidence(_ confidence: Double) -> Double {
        min(max(confidence, 0), 1)
    }

    private static func stableUniqueAlternatives(_ alternatives: [HomeCapabilityAlternative]) -> [HomeCapabilityAlternative] {
        var seen = Set<String>()
        var result: [HomeCapabilityAlternative] = []
        for alternative in alternatives {
            let key = [
                alternative.targetDeviceID ?? "",
                alternative.capability,
                alternative.command ?? ""
            ].joined(separator: "|")
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(alternative)
        }
        return result.sorted {
            if $0.confidence == $1.confidence {
                return $0.capability < $1.capability
            }
            return $0.confidence > $1.confidence
        }
        .prefix(5)
        .map { $0 }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
