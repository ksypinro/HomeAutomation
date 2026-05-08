import Foundation
import FoundationModels
import HomeAutomationCore

public struct LegacyInstructionSetFactory: Sendable {
    private let toolProvider: LegacyToolProvider

    public init(toolProvider: LegacyToolProvider) {
        self.toolProvider = toolProvider
    }

    public func makePackage(from input: HomeFinalResolutionInput) -> HomeModelInstructionPackage {
        let topFamily = input.resolutionState.intent.topFamilies.first
        let focus: String
        let extraRules: String

        switch topFamily {
        case .power:
            focus = "Resolve a smart-home power command."
            extraRules = "Use capability switch and command on or off when appropriate."
        case .temperature:
            focus = "Resolve a smart-home temperature, thermostat, or air-conditioner command."
            extraRules = """
            Use getCurrentDeviceState for relative temperature changes.
            Prefer exact setter commands after computing the intended target value.
            For fan mode, validate supported modes before choosing setFanMode.
            """
        case .brightness:
            focus = "Resolve a smart-home brightness, color, or level command."
            extraRules = """
            Use switchLevel.setLevel for absolute brightness percentages.
            Use read state tools when a relative change needs the current value.
            """
        case .lockUnlock, .openClose:
            focus = "Resolve a safety-sensitive smart-home command."
            extraRules = """
            Lock, unlock, open, and close commands must be conservative.
            Set requiresConfirmation true for unlock, open, exterior entry, or high-risk targets.
            If the target is ambiguous, ask a clarification question.
            """
        case .routine:
            focus = "Resolve a smart-home routine or scene command."
            extraRules = "Use capability routine and command run when the user asks to run a routine."
        case .statusQuery:
            focus = "Resolve a smart-home status query."
            extraRules = "Use getCurrentDeviceState when current state is needed. Set intent getStatus and command getStatus."
        default:
            focus = "Resolve the smart-home command."
            extraRules = "If the command cannot be mapped to the candidates, return unsupported or ask for clarification."
        }

        return package(input, focus: focus, extraRules: extraRules)
    }

    private func package(
        _ input: HomeFinalResolutionInput,
        focus: String,
        extraRules: String
    ) -> HomeModelInstructionPackage {
        let languageRules = Self.languageRules(for: input)
        let instructions = Instructions("""
        \(focus)

        Choose only from the hydrated candidate records.
        Do not invent devices, capabilities, commands, modes, or IDs.
        Use the provided tools when state, mode values, capability support, or hydration details are needed.
        If more than one device is plausible, set needsClarification to true.
        Keep internal schema values in English even when the user command is multilingual.
        \(languageRules)
        Return one structured HomeCommandDraft.
        For status or measurement questions, set intent getStatus and command getStatus.
        For relative numeric changes, either compute an absolute setter value from current state or use increaseValue/decreaseValue with a numeric delta.

        \(extraRules)

        \(HomeAutomationKnowledgeBase.instructionSummary)

        \(HomeBixbyCommandCatalog.instructionSummary)
        """)

        let prompt = """
        User command: \(input.rawText)

        Worker session outputs:
        - Language: \(input.resolutionState.language.languageCode)
        - Intent families: \(input.resolutionState.intent.topFamilies)
        - Device types: \(input.resolutionState.deviceType.deviceTypes)
        - Rooms: \(input.resolutionState.slots.rooms)
        - Device nicknames: \(input.resolutionState.slots.deviceNicknames)
        - Values: \(input.resolutionState.slots.values)
        - Modes: \(input.resolutionState.slots.modes)
        - Risk: \(input.resolutionState.risk.riskLevel), confirmation hint: \(input.resolutionState.risk.requiresConfirmation)

        Candidate aggregation:
        - Final candidate IDs: \(input.aggregation.finalCandidateIDs)
        - Needs clarification: \(input.aggregation.needsClarification)
        - Clarification question: \(input.aggregation.clarificationQuestion ?? "none")

        Hydrated candidate records:
        \(Self.describe(input.hydratedCandidates))
        """

        return HomeModelInstructionPackage(
            instructions: instructions,
            prompt: prompt,
            tools: toolProvider.tools(for: input),
            useAdapter: false,
            generationMode: .greedy
        )
    }

    static func languageRules(for input: HomeFinalResolutionInput) -> String {
        let language = input.resolutionState.language
        var rules: [String] = []

        if language.languageCode != "en" {
            rules.append(
                "The user's command is in \(language.languageCode). Infer home concepts in that language, but return capability names, commands, device types, modes, parameter names, and IDs exactly in the provided English/internal schema."
            )
        }

        if language.isMixedLanguage {
            rules.append(
                "The command may mix languages. Resolve meaning across both languages, but keep every internal schema value in English."
            )
        }

        if language.unsupportedLanguageLikely {
            rules.append(
                "If the language makes the target or action uncertain, ask for clarification instead of guessing."
            )
        }

        return rules.joined(separator: "\n")
    }

    private static func describe(_ candidates: [HomeCandidateRecord]) -> String {
        candidates.map { candidate in
            """
            ID: \(candidate.id)
            Name: \(candidate.displayName)
            Type: \(candidate.deviceType)
            Room: \(candidate.room ?? "none")
            Capabilities: \(candidate.capabilities.joined(separator: ", "))
            Commands: \(candidate.supportedCommands)
            Modes: \(candidate.supportedModes)
            State: \(candidate.currentState)
            Risk: \(candidate.riskLevel)
            """
        }
        .joined(separator: "\n---\n")
    }
}
