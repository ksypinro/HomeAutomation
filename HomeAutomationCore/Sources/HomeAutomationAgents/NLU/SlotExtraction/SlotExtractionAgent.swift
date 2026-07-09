import Foundation
import HomeAutomationCore
import HomeAutomationRAG

/// Extracts structured slots from the user's natural-language command.
///
/// The `SlotExtractionAgent` identifies rooms, device nicknames, numeric values, units,
/// durations, and modes from the command text. Extracted slots are critical for:
/// - **Candidate retrieval**: Room and nickname slots narrow the device search space
/// - **Draft generation**: Value and unit slots are used to populate command parameters
/// - **Bixby mapping**: Slot values are matched against Bixby command placeholders
///
/// The agent understands Bixby Home Studio slot language including `device`, `deviceType`,
/// `location`, `mode`, `predefinedMode`, `temperature`, `duration`, `number`, `compartment`,
/// and `channel`.
///
/// Internal values are kept in English even when the input is multilingual.
///
/// Runs in parallel with the other five NLU agents during the first orchestrator phase.
public struct SlotExtractionAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = HomeSlotExtractionResult

    public let id = AgentID.slotExtraction
    public let capabilities: Set<AgentCapability> = [.slotExtraction]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let worker: SlotExtractionAgentWorkerSession
    private let contextRetriever: ContextRetriever?

    public init(
        contextRetriever: ContextRetriever? = nil,
        extract: @escaping @Sendable (String) async throws -> HomeSlotExtractionResult
    ) {
        self.init(
            worker: SlotExtractionAgentWorkerSession(extract: extract),
            contextRetriever: contextRetriever
        )
    }

    public init(
        worker: SlotExtractionAgentWorkerSession = SlotExtractionAgentWorkerSession(),
        contextRetriever: ContextRetriever? = nil
    ) {
        self.worker = worker
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: String, context: ResolutionContext) async throws -> HomeSlotExtractionResult {
        let enrichedInput = await AgentRAGSupport.nluInput(
            input,
            task: "slot extraction",
            contextRetriever: contextRetriever,
            deterministicConfidence: AgentTextParser.deterministicState(for: input).slots.confidence
        )
        let modeOverride = context.artifact(for: ContextArtifactKeys.nluPolicyOverride())
        return try await worker.extractSlots(input, modelPrompt: enrichedInput, modeOverride: modeOverride)
    }
}
