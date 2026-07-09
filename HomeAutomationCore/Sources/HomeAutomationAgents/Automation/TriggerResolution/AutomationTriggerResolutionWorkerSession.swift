import Foundation
import FoundationModels
import HomeAutomationCore
import os

public struct AutomationTriggerResolutionWorkerSession: Sendable {
    public static let sessionInstructions = AutomationTriggerResolutionPromptBuilder.instructions
    private let foundationModelAvailability: @Sendable () -> Bool
    private let resolve: (@Sendable (AutomationTriggerResolutionInput) async throws -> AutomationTriggerResolutionFMOutput)?
    private let deterministicAcceptThreshold: Double
    private let sessionPool: FoundationModelSessionPool?
    private let logger = Logger(subsystem: "HomeAutomation", category: "Automation.TriggerResolution")

    public init(
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        resolve: (@Sendable (AutomationTriggerResolutionInput) async throws -> AutomationTriggerResolutionFMOutput)? = nil,
        deterministicAcceptThreshold: Double = 0.8,
        sessionPool: FoundationModelSessionPool? = nil
    ) {
        self.foundationModelAvailability = foundationModelAvailability
        self.resolve = resolve
        self.deterministicAcceptThreshold = deterministicAcceptThreshold
        self.sessionPool = sessionPool
    }

    public func resolve(_ input: AutomationTriggerResolutionInput) async throws -> AutomationTriggerResolutionOutput {
        let fallback = deterministicOutput(for: input)

        if let fallback, fallback.confidence >= deterministicAcceptThreshold, resolve == nil {
            logger.debug("[τ-gate] Deterministic trigger confidence \(fallback.confidence) ≥ \(self.deterministicAcceptThreshold); skipping FM.")
            return fallback
        }

        if let resolve {
            return try output(from: try await resolve(input), id: input.component.id, fallback: fallback)
        }

        guard foundationModelAvailability() else {
            if let fallback { return fallback }
            return AutomationTriggerResolutionOutput(
                id: input.component.id,
                trigger: nil,
                confidence: 0,
                unsupportedFragments: ["unsupported trigger: \(input.component.rawText)"]
            )
        }

        let prompt = AutomationTriggerResolutionPromptBuilder.prompt(input: input, fallback: fallback)
        logger.debug("[FoundationModelInput] \(prompt, privacy: .public)")
        do {
            let session: LanguageModelSession
            if let sessionPool {
                session = await sessionPool.acquire(kind: .triggerResolution)
            } else {
                session = LanguageModelSession(
                    instructions: Instructions(AutomationTriggerResolutionPromptBuilder.instructions)
                )
            }
            let fmOutput = try await FoundationModelCallRecorder.record(
                agentID: AgentID.automationTriggerResolution.rawValue,
                policyMode: "model-first-with-fallback",
                modelAvailability: "available",
                promptCharacterCount: AutomationTriggerResolutionPromptBuilder.instructions.count + prompt.count
            ) {
                try await session.respond(
                    to: Prompt(prompt),
                    generating: AutomationTriggerResolutionFMOutput.self
                ).content
            }
            if let sessionPool {
                await sessionPool.release(kind: .triggerResolution, session: session)
            }
            let result = try output(from: fmOutput, id: input.component.id, fallback: fallback)
            logger.debug("[FoundationModelOutput] \(String(describing: result), privacy: .public)")
            return result
        } catch {
            logger.error("[FoundationModelError] \(error.localizedDescription, privacy: .public); using deterministic trigger fallback.")
            if let fallback { return fallback }
            throw error
        }
    }

    private func output(
        from fmOutput: AutomationTriggerResolutionFMOutput,
        id: String,
        fallback: AutomationTriggerResolutionOutput?
    ) throws -> AutomationTriggerResolutionOutput {
        let trigger = try fmOutput.trigger?.makeHomeTrigger() ?? fallback?.trigger
        return AutomationTriggerResolutionOutput(
            id: id,
            trigger: trigger,
            confidence: fmOutput.confidence > 0 ? fmOutput.confidence : (fallback?.confidence ?? 0.5),
            unsupportedFragments: merge(fmOutput.unsupportedFragments, fallback?.unsupportedFragments ?? [])
        )
    }

    private func deterministicOutput(for input: AutomationTriggerResolutionInput) -> AutomationTriggerResolutionOutput? {
        if input.component.kindHint == .schedule,
           let trigger = scheduleTrigger(from: input.component.rawText) {
            return AutomationTriggerResolutionOutput(
                id: input.component.id,
                trigger: trigger,
                confidence: 0.84
            )
        }

        let syntheticText: String
        switch input.component.kindHint {
        case .device:
            syntheticText = "When \(input.component.rawText), turn on device"
        case .schedule, .unknown:
            syntheticText = "Turn on device \(input.component.rawText)"
        }
        guard let trigger = try? AutomationPatternParser().parse(syntheticText)?.trigger?.makeHomeTrigger() else {
            return nil
        }
        return AutomationTriggerResolutionOutput(
            id: input.component.id,
            trigger: trigger,
            confidence: 0.82
        )
    }

    private func scheduleTrigger(from rawText: String) -> HomeAutomationTrigger? {
        let normalized = AutomationPatternParser.normalized(rawText)
        guard let time = timeOfDay(from: normalized) else { return nil }
        let repeatRule: HomeAutomationRepeatRule
        if normalized.contains("weekday") {
            repeatRule = .daysOfWeek([.monday, .tuesday, .wednesday, .thursday, .friday])
        } else if normalized.contains("weekend") {
            repeatRule = .daysOfWeek([.saturday, .sunday])
        } else {
            let weekdays: [(String, HomeAutomationWeekday)] = [
                ("monday", .monday),
                ("tuesday", .tuesday),
                ("wednesday", .wednesday),
                ("thursday", .thursday),
                ("friday", .friday),
                ("saturday", .saturday),
                ("sunday", .sunday)
            ]
            let matchedDays = weekdays.compactMap { normalized.contains($0.0) ? $0.1 : nil }
            if !matchedDays.isEmpty {
                repeatRule = .daysOfWeek(matchedDays)
            } else if normalized.contains("once") || normalized.contains("tomorrow") {
                repeatRule = .once
            } else {
                repeatRule = .everyDay
            }
        }
        return .schedule(
            HomeAutomationScheduleTrigger(
                repeatRule: repeatRule,
                timeOfDay: time,
                timezoneIdentifier: nil
            )
        )
    }

    private func timeOfDay(from normalized: String) -> HomeAutomationTimeOfDay? {
        guard let match = normalized.firstAutomationMatch(of: #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#),
              var hour = Int(match[1]) else {
            return nil
        }
        let minute = Int(match[2]) ?? 0
        let period = match[3]
        if period == "pm", hour < 12 { hour += 12 }
        if period == "am", hour == 12 { hour = 0 }
        return HomeAutomationTimeOfDay(hour: hour, minute: minute)
    }

    private func merge(_ lhs: [String], _ rhs: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in lhs + rhs {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed.lowercased()) else { continue }
            seen.insert(trimmed.lowercased())
            result.append(trimmed)
        }
        return result
    }
}
