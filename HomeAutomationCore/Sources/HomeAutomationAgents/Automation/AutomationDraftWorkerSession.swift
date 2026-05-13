import Foundation
import FoundationModels
import HomeAutomationCore
import os

public struct AutomationDraftWorkerSession: Sendable {
    private let draft: (@Sendable (AutomationDraftInput) async throws -> AutomationDraftOutput)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let deterministicConfidenceThreshold: Double
    private let parser: AutomationPatternParser
    private let logger = Logger(subsystem: "HomeAutomation", category: "Automation.AutomationDraftWorkerSession")

    public init(
        draft: (@Sendable (AutomationDraftInput) async throws -> AutomationDraftOutput)? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        deterministicConfidenceThreshold: Double = 0.88,
        parser: AutomationPatternParser = AutomationPatternParser()
    ) {
        self.draft = draft
        self.foundationModelAvailability = foundationModelAvailability
        self.deterministicConfidenceThreshold = deterministicConfidenceThreshold
        self.parser = parser
    }

    public func createDraft(_ input: AutomationDraftInput) async throws -> AutomationDraftOutput {
        let commandText = AgentTextParser.userCommandText(from: input.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commandText.isEmpty else {
            throw AutomationDraftError.unsupported("Missing automation command text")
        }

        logger.debug("[Input] text: \(commandText, privacy: .public)")

        if let draft {
            let result = try await draft(input)
            try validate(result)
            logger.debug("[MockOutput] result: \(String(describing: result), privacy: .public)")
            return result
        }

        let deterministic = parser.parse(commandText)
        if let deterministic,
           deterministic.confidence >= deterministicConfidenceThreshold,
           deterministic.unsupportedFragments.isEmpty {
            logger.info("[DeterministicParser] High-confidence automation draft produced.")
            return deterministic
        }

        guard foundationModelAvailability() else {
            if let deterministic {
                logger.info("[Availability] Foundation model unavailable, using deterministic parser output.")
                return deterministic
            }
            throw AutomationDraftError.unsupported("I could not extract a supported automation trigger and action from this command.")
        }

        let instructions = """
        You convert smart-home automation creation commands into a structured draft.

        Output rules:
        1. Extract actionDescriptions as standalone immediate commands, e.g. "Turn on AC".
        2. Extract schedule triggers with repeatRule and 24-hour time when present.
        3. Extract device triggers from "when" or "whenever" clauses.
        4. Preserve and/or/not condition grouping in the condition tree.
        5. Do not resolve device IDs, capabilities, commands, or SmartThings JSON.
        6. Do not invent devices or unsupported details.
        7. Put uncertain recurrence such as holidays or weekday schedules in unsupportedFragments.
        8. Treat "everyday", "every day", and "daily" as repeatRule "everyDay".
        9. Confidence must be between 0.0 and 1.0.

        Examples:
        User: Turn on AC everyday at 7 AM
        Output:
        name: Turn on AC everyDay at 07:00
        trigger: schedule, repeatRule: everyDay, time: 07:00
        actionDescriptions: ["Turn on AC"]
        unsupportedFragments: []

        User: Turn on AC every day at 7 AM if bedroom window is closed and motion is detected
        Output condition: and([bedroom window equals closed, motion equals active])
        """

        logger.debug("[FoundationModelInput] System Instructions: \(instructions, privacy: .public)")
        logger.debug("[FoundationModelInput] Prompt: \(commandText, privacy: .public)")

        let session = LanguageModelSession(instructions: Instructions(instructions))
        do {
            let result = try await session.respond(
                to: Prompt(commandText),
                generating: AutomationDraftOutput.self
            ).content
            try validate(result)
            logger.debug("[FoundationModelOutput] result: \(String(describing: result), privacy: .public)")
            return result
        } catch {
            if let deterministic {
                logger.error("[FoundationModelError] \(error.localizedDescription, privacy: .public); using deterministic parser output.")
                return deterministic
            }
            logger.error("[FoundationModelError] error: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func validate(_ output: AutomationDraftOutput) throws {
        guard !output.actionDescriptions.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).isEmpty else {
            throw AutomationDraftError.invalidOutput("missing action descriptions")
        }
        _ = try output.makeRuleDraft()
    }
}
