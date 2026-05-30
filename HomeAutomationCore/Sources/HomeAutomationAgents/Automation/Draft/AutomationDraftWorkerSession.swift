import Foundation
import FoundationModels
import HomeAutomationCore
import HomeAutomationRAG
import os

public struct AutomationDraftSessionResult: Sendable, Hashable {
    public let output: AutomationDraftOutput
    public let retrievalReports: [KnowledgeRetrievalReport]

    public init(
        output: AutomationDraftOutput,
        retrievalReports: [KnowledgeRetrievalReport] = []
    ) {
        self.output = output
        self.retrievalReports = retrievalReports
    }
}

public struct AutomationDraftWorkerSession: Sendable {
    private let draft: (@Sendable (AutomationDraftInput) async throws -> AutomationDraftOutput)?
    private let foundationModelAvailability: @Sendable () -> Bool
    private let deterministicConfidenceThreshold: Double
    private let parser: AutomationPatternParser
    private let contextRetriever: ContextRetriever?
    private let logger = Logger(subsystem: "HomeAutomation", category: "Automation.AutomationDraftWorkerSession")

    public init(
        draft: (@Sendable (AutomationDraftInput) async throws -> AutomationDraftOutput)? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        deterministicConfidenceThreshold: Double = 0.88,
        parser: AutomationPatternParser = AutomationPatternParser(),
        contextRetriever: ContextRetriever? = nil
    ) {
        self.draft = draft
        self.foundationModelAvailability = foundationModelAvailability
        self.deterministicConfidenceThreshold = deterministicConfidenceThreshold
        self.parser = parser
        self.contextRetriever = contextRetriever
    }

    public func createDraft(_ input: AutomationDraftInput) async throws -> AutomationDraftOutput {
        try await createDraftWithDiagnostics(input).output
    }

    public func createDraftWithDiagnostics(_ input: AutomationDraftInput) async throws -> AutomationDraftSessionResult {
        let commandText = AgentTextParser.userCommandText(from: input.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commandText.isEmpty else {
            throw AutomationDraftError.unsupported("Missing automation command text")
        }

        logger.debug("[Input] text: \(commandText, privacy: .public)")
        let normalizedInput = AutomationDraftInput(text: commandText, operation: input.operation)

        // Always compute deterministic parser output for hint and fallback
        let deterministic = parser.parse(commandText)
        if let deterministic {
            logger.debug("[DeterministicParser] result: \(String(describing: deterministic), privacy: .public)")
        }

        if let draft {
            let result = try await draft(input)
            let preserved = outputByPreservingParserGrounding(
                in: result,
                deterministic: deterministic
            )
            try validate(preserved, commandText: commandText)
            logger.debug("[MockOutput] result: \(String(describing: preserved), privacy: .public)")
            return AutomationDraftSessionResult(output: preserved)
        }

        // Retrieve RAG context
        let ragContext = await AgentRAGSupport.automationContext(
            normalizedInput,
            draftOutput: deterministic,
            contextRetriever: contextRetriever
        )

        // If FM unavailable, use deterministic parser as fallback
        guard foundationModelAvailability() else {
            if let deterministic {
                logger.info("[Availability] Foundation model unavailable, using deterministic parser output.")
                return AutomationDraftSessionResult(
                    output: deterministic,
                    retrievalReports: ragContext.reports
                )
            }
            throw AutomationDraftError.unsupported("I could not extract a supported automation trigger and action from this command.")
        }

        // Build parser hint for the FM prompt
        let parserHintText: String
        if let deterministic {
            parserHintText = """

            A deterministic parser produced this draft (confidence=\(deterministic.confidence)):
            - name: \(deterministic.name)
            - trigger type: \(deterministic.trigger?.type.rawValue ?? "nil")
            - trigger time: \(deterministic.trigger?.time ?? "nil")
            - trigger repeatRule: \(deterministic.trigger?.repeatRule ?? "nil")
            - trigger description: \(deterministic.trigger?.description ?? "nil")
            - actionDescriptions: \(deterministic.actionDescriptions)
            - unsupportedFragments: \(deterministic.unsupportedFragments)
            - condition: \(deterministic.condition != nil ? "present" : "nil")
            Use this as guidance. Verify, correct, and improve where needed. \
            The parser may miss nuanced triggers or conditions that you can detect.
            """
            logger.info("[ParserHint] Providing deterministic parser draft as hint (confidence: \(deterministic.confidence, privacy: .public)).")
        } else {
            parserHintText = ""
            logger.info("[ParserHint] No deterministic parser output available; model working without hint.")
        }

        let instructions = """
        You convert smart-home automation creation commands into a structured draft.

        Output rules:
        1. Extract actionDescriptions as standalone immediate commands, e.g. "Turn on AC".
        2. Extract schedule triggers with repeatRule and 24-hour time when present.
        3. Extract device triggers from "when" or "whenever" clauses.
        4. Preserve and/or/not/changes condition grouping in the condition tree.
        5. Do not resolve device IDs, capabilities, commands, or SmartThings JSON.
        6. Do not invent devices or unsupported details.
        7. Put uncertain recurrence such as holidays or weekday schedules in unsupportedFragments.
        8. Treat "everyday", "every day", and "daily" as repeatRule "everyDay".
        9. Confidence must be between 0.0 and 1.0.
        10. If the prompt includes relevant SmartThings automation knowledge, use it only as extraction guidance; the user automation command remains the source of truth.

        Examples:
        User: Turn on AC everyday at 7 AM
        Output:
        name: Turn on AC everyDay at 07:00
        trigger: schedule, repeatRule: everyDay, time: 07:00
        actionDescriptions: ["Turn on AC"]
        unsupportedFragments: []

        User: Turn on AC every day at 7 AM if bedroom window is closed and motion is detected
        Output condition: and([bedroom window equals closed, motion equals active])

        User: Turn on AC every day at 7 AM if bedroom lamp level is between 20 and 80
        Output condition: bedroom lamp level between 20 and 80

        User: When hallway motion sensor changes to active turn on bedroom lamp
        Output trigger condition: changes(hallway motion sensor equals active)
        """
        let promptText = ragContext.promptText + parserHintText

        logger.debug("[FoundationModelInput] System Instructions: \(instructions, privacy: .public)")
        logger.debug("[FoundationModelInput] Prompt: \(promptText, privacy: .public)")

        let session = LanguageModelSession(instructions: Instructions(instructions))
        do {
            let result = try await FoundationModelCallRecorder.record(
                agentID: AgentID.automationDraft.rawValue,
                policyMode: "model-first-with-parser-fallback",
                modelAvailability: "available",
                promptCharacterCount: instructions.count + promptText.count
            ) {
                try await session.respond(
                    to: Prompt(promptText),
                    generating: AutomationDraftOutput.self
                ).content
            }
            let preserved = outputByPreservingParserGrounding(
                in: result,
                deterministic: deterministic
            )
            try validate(preserved, commandText: commandText)
            logger.debug("[FoundationModelOutput] result: \(String(describing: preserved), privacy: .public)")
            return AutomationDraftSessionResult(
                output: preserved,
                retrievalReports: ragContext.reports
            )
        } catch {
            if let deterministic {
                logger.error("[FoundationModelError] \(error.localizedDescription, privacy: .public); using deterministic parser output.")
                return AutomationDraftSessionResult(
                    output: deterministic,
                    retrievalReports: ragContext.reports
                )
            }
            logger.error("[FoundationModelError] error: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func outputByPreservingParserGrounding(
        in output: AutomationDraftOutput,
        deterministic: AutomationDraftOutput?
    ) -> AutomationDraftOutput {
        guard let deterministic else { return output }

        let trigger = Self.triggerByPreservingParserCondition(
            in: output.trigger,
            deterministic: deterministic.trigger
        )
        let condition = output.condition ?? deterministic.condition
        let unsupportedFragments = Self.mergedUnsupportedFragments(
            output.unsupportedFragments,
            deterministic.unsupportedFragments
        )
        let name = Self.isGenericModelName(output.name) ? deterministic.name : output.name

        let preserved = AutomationDraftOutput(
            name: name,
            trigger: trigger,
            condition: condition,
            actionDescriptions: output.actionDescriptions,
            unsupportedFragments: unsupportedFragments,
            confidence: output.confidence
        )

        if preserved != output {
            logger.info("[ParserGrounding] Preserved grounded deterministic automation draft fields dropped by model output.")
        }
        return preserved
    }

    private static func triggerByPreservingParserCondition(
        in trigger: AutomationTriggerOutput?,
        deterministic: AutomationTriggerOutput?
    ) -> AutomationTriggerOutput? {
        guard let trigger else {
            return deterministic
        }
        guard let deterministic,
              trigger.type == deterministic.type,
              trigger.condition == nil,
              let deterministicCondition = deterministic.condition else {
            return trigger
        }

        return AutomationTriggerOutput(
            type: trigger.type,
            repeatRule: trigger.repeatRule,
            time: trigger.time,
            timezoneIdentifier: trigger.timezoneIdentifier,
            description: trigger.description,
            condition: deterministicCondition
        )
    }

    private static func mergedUnsupportedFragments(
        _ outputFragments: [String],
        _ deterministicFragments: [String]
    ) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        for fragment in outputFragments + deterministicFragments {
            let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedGroundingText(trimmed)
            guard !trimmed.isEmpty, !key.isEmpty, !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            merged.append(trimmed)
        }
        return merged
    }

    private static func isGenericModelName(_ name: String) -> Bool {
        switch normalizedGroundingText(name) {
        case "", "automation", "automation draft", "automationdraftoutput":
            return true
        default:
            return false
        }
    }

    private func validate(_ output: AutomationDraftOutput, commandText: String) throws {
        guard !output.actionDescriptions.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).isEmpty else {
            throw AutomationDraftError.invalidOutput("missing action descriptions")
        }
        _ = try output.makeRuleDraft()
        try validateGrounding(output, commandText: commandText)
    }

    private func validateGrounding(
        _ output: AutomationDraftOutput,
        commandText: String
    ) throws {
        let commandTerms = Self.significantTerms(in: commandText)
        for action in output.actionDescriptions {
            let actionTerms = Self.significantTerms(in: action)
            guard actionTerms.isEmpty || !actionTerms.isDisjoint(with: commandTerms) else {
                throw AutomationDraftError.invalidOutput(
                    "action description '\(action)' was not grounded in the user command"
                )
            }
        }

        if output.trigger?.type == .schedule,
           !Self.containsScheduleSignal(commandText) {
            throw AutomationDraftError.invalidOutput("schedule trigger was not grounded in the user command")
        }

        var deviceAttributeDescriptions: [String] = []
        Self.collectDeviceAttributeDescriptions(output.trigger?.condition, into: &deviceAttributeDescriptions)
        Self.collectDeviceAttributeDescriptions(output.condition, into: &deviceAttributeDescriptions)
        for description in deviceAttributeDescriptions {
            let descriptionTerms = Self.significantTerms(in: description)
            guard descriptionTerms.isEmpty || !descriptionTerms.isDisjoint(with: commandTerms) else {
                throw AutomationDraftError.invalidOutput(
                    "condition operand '\(description)' was not grounded in the user command"
                )
            }
        }
    }

    private static func collectDeviceAttributeDescriptions(
        _ condition: AutomationConditionOutput?,
        into descriptions: inout [String]
    ) {
        guard let condition else { return }
        switch condition.type {
        case .and, .or, .not, .changes:
            for child in condition.children {
                collectDeviceAttributeDescriptions(child, into: &descriptions)
            }
        case .comparison:
            if condition.left?.type == .deviceAttribute,
               let description = condition.left?.description?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                descriptions.append(description)
            }
        }
    }

    private static func containsScheduleSignal(_ text: String) -> Bool {
        let normalized = normalizedGroundingText(text)
        let words = Set(normalized.split(separator: " ").map(String.init))
        if !words.isDisjoint(with: ["every", "everyday", "daily", "once", "weekdays", "weekends"]) {
            return true
        }
        let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        if weekdays.contains(where: { words.contains($0) }) {
            return true
        }
        return normalized.firstAutomationMatch(of: #"\bat\s+\d{1,2}(?::\d{2})?\s*(am|pm)?\b"#) != nil
    }

    private static func significantTerms(in text: String) -> Set<String> {
        Set(
            normalizedGroundingText(text)
                .split(separator: " ")
                .map(String.init)
                .filter { !$0.isEmpty && !isGroundingStopWord($0) }
        )
    }

    private static func normalizedGroundingText(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\s:]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isGroundingStopWord(_ word: String) -> Bool {
        switch word {
        case "a", "an", "and", "are", "at", "be", "been", "being", "by", "can",
             "could", "create", "daily", "do", "every", "everyday", "for", "if",
             "in", "is", "it", "make", "my", "of", "off", "on", "once", "please",
             "rule", "schedule", "set", "switch", "the", "then", "to", "turn",
             "turned", "turns", "up", "when", "whenever", "you":
            return true
        default:
            return false
        }
    }
}
