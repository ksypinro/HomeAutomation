import Foundation
import FoundationModels
import HomeAutomationCore
import os

// MARK: - FragmentNLUOutput

public struct FragmentNLUOutput: Sendable, Hashable, Codable {
    public let intentFamilies: [HomeAutomationIntentFamily]
    public let deviceTypes: [String]
    public let rooms: [String]
    public let deviceNicknames: [String]
    public let values: [HomeExtractedSlot]
    public let confidence: Double

    public init(
        intentFamilies: [HomeAutomationIntentFamily] = [],
        deviceTypes: [String] = [],
        rooms: [String] = [],
        deviceNicknames: [String] = [],
        values: [HomeExtractedSlot] = [],
        confidence: Double
    ) {
        self.intentFamilies = intentFamilies
        self.deviceTypes = deviceTypes
        self.rooms = rooms
        self.deviceNicknames = deviceNicknames
        self.values = values
        self.confidence = confidence
    }
}

// MARK: - FragmentNLUWorkerSession

public struct FragmentNLUWorkerSession: Sendable {
    private let resolve: (@Sendable (String) async throws -> FragmentNLUOutput)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let softTimeoutNanoseconds: UInt64
    private let logger = Logger(subsystem: "HomeAutomation", category: "Loop.FragmentNLU")

    public init(
        resolve: (@Sendable (String) async throws -> FragmentNLUOutput)? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        softTimeoutNanoseconds: UInt64 = NLUSoftTimeoutBudget.default.nluClassNanoseconds
    ) {
        self.resolve = resolve
        self.foundationModelAvailability = foundationModelAvailability
        self.softTimeoutNanoseconds = softTimeoutNanoseconds
    }

    public func analyze(_ text: String) async throws -> FragmentNLUOutput {
        logger.debug("[Input] text: \(text, privacy: .public)")

        if let resolve {
            let result = try await resolve(text)
            logger.debug("[MockOutput] confidence: \(result.confidence)")
            return result
        }

        let deterministicState = AgentTextParser.deterministicState(for: text)
        let fallback = FragmentNLUOutput(
            intentFamilies: deterministicState.intent.topFamilies,
            deviceTypes: deterministicState.deviceType.deviceTypes,
            rooms: deterministicState.slots.rooms,
            deviceNicknames: deterministicState.slots.deviceNicknames,
            values: deterministicState.slots.values,
            confidence: min(deterministicState.intent.confidence, deterministicState.slots.confidence)
        )

        guard foundationModelAvailability() else {
            logger.info("[Availability] Foundation model unavailable, using deterministic fallback.")
            return fallback
        }

        let instructions = """
        Extract intent, device type, and slots from this home-automation action fragment.
        Return intent families (e.g. powerControl, setValue), device types (e.g. light, thermostat), \
        rooms, device nicknames, and value slots.
        Do NOT classify risk — that is handled separately.
        """

        let session = LanguageModelSession(instructions: Instructions(instructions))
        do {
            let modelResult = try await withNLUModelSoftTimeout(
                agentID: .fragmentNLU,
                timeoutNanoseconds: softTimeoutNanoseconds
            ) {
                let nluResult = try await FoundationModelCallRecorder.record(
                    agentID: AgentID.fragmentNLU.rawValue,
                    policyMode: "repair",
                    modelAvailability: "available",
                    promptCharacterCount: instructions.count + text.count,
                    jobID: "fragmentNLU.semantic",
                    jobKind: .semanticNLU
                ) {
                    try await session.respond(
                        to: Prompt(text),
                        generating: HomeSemanticNLUResult.self
                    ).content
                }
                let slotPrompt = "Extract slots: \(text)"
                let slotResult = try await FoundationModelCallRecorder.record(
                    agentID: AgentID.fragmentNLU.rawValue,
                    policyMode: "repair",
                    modelAvailability: "available",
                    promptCharacterCount: instructions.count + slotPrompt.count,
                    jobID: "fragmentNLU.slots",
                    jobKind: .slotExtraction
                ) {
                    try await session.respond(
                        to: Prompt(slotPrompt),
                        generating: HomeSlotExtractionResult.self
                    ).content
                }
                return FragmentNLUOutput(
                    intentFamilies: nluResult.intent.topFamilies,
                    deviceTypes: nluResult.deviceType.deviceTypes,
                    rooms: slotResult.rooms,
                    deviceNicknames: slotResult.deviceNicknames,
                    values: slotResult.values,
                    confidence: min(nluResult.intent.confidence, slotResult.confidence)
                )
            }
            logger.debug("[FoundationModelOutput] confidence: \(modelResult.confidence)")
            return modelResult
        } catch {
            logger.error("[FoundationModelError] \(error.localizedDescription, privacy: .public), using fallback.")
            return fallback
        }
    }
}

// MARK: - AgentID extension

public extension AgentID {
    static let fragmentNLU = AgentID("fragmentNLU")
}
