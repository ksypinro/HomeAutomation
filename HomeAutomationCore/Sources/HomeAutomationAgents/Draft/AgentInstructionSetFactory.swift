import Foundation
import FoundationModels
import HomeAutomationCore
import HomeAutomationRAG

/// Builds `HomeModelInstructionPackage` from final input, tools, RAG context,
/// and canonical registries.
public struct AgentInstructionSetFactory: Sendable {
    private let toolProvider: AgentToolProvider
    private let contextRetriever: ContextRetriever?

    public init(
        toolProvider: AgentToolProvider,
        contextRetriever: ContextRetriever? = nil
    ) {
        self.toolProvider = toolProvider
        self.contextRetriever = contextRetriever
    }

    public func makePackage(from input: HomeFinalResolutionInput) -> HomeModelInstructionPackage {
        makePackage(from: input, selectedKnowledgeContext: nil)
    }

    public func makePackageWithRAG(from input: HomeFinalResolutionInput) async -> HomeModelInstructionPackage {
        let selectedKnowledgeContext = await selectedKnowledgeContext(for: input)
        return makePackage(from: input, selectedKnowledgeContext: selectedKnowledgeContext)
    }

    private func makePackage(
        from input: HomeFinalResolutionInput,
        selectedKnowledgeContext: String?
    ) -> HomeModelInstructionPackage {
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

        return package(
            input,
            focus: focus,
            extraRules: extraRules,
            selectedKnowledgeContext: selectedKnowledgeContext
        )
    }

    public static func languageRules(for input: HomeFinalResolutionInput) -> String {
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

    private func package(
        _ input: HomeFinalResolutionInput,
        focus: String,
        extraRules: String,
        selectedKnowledgeContext: String?
    ) -> HomeModelInstructionPackage {
        let knowledgeBlock = selectedKnowledgeContext ?? """
        \(HomeAutomationKnowledgeBase.instructionSummary)

        \(HomeBixbyCommandCatalog.instructionSummary)
        """
        let selectedKnowledgePrompt = selectedKnowledgeContext.map {
            """

            Selected RAG context:
            \($0)
            """
        } ?? ""

        let instructions = Instructions("""
        \(focus)

        Choose only from the hydrated candidate records.
        Do not invent devices, capabilities, commands, modes, or IDs.
        Use the provided tools when state, mode values, capability support, or hydration details are needed.
        If more than one device is plausible, set needsClarification to true.
        Keep internal schema values in English even when the user command is multilingual.
        \(Self.languageRules(for: input))
        Return one structured HomeCommandDraft.
        For status or measurement questions, set intent getStatus and command getStatus.
        For relative numeric changes, either compute an absolute setter value from current state or use increaseValue/decreaseValue with a numeric delta.

        \(extraRules)

        \(knowledgeBlock)
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
        \(selectedKnowledgePrompt)
        """

        return HomeModelInstructionPackage(
            instructions: instructions,
            prompt: prompt,
            tools: toolProvider.tools(for: input),
            useAdapter: false,
            generationMode: .greedy
        )
    }

    private func selectedKnowledgeContext(for input: HomeFinalResolutionInput) async -> String? {
        guard let contextRetriever else { return nil }

        let capabilityChunks = await contextRetriever.retrieve(
            query: input.rawText,
            topK: 5,
            filter: MetadataFilter(source: .capability)
        )
        let exampleChunks = await contextRetriever.retrieve(
            query: input.rawText,
            topK: 3,
            filter: MetadataFilter(source: .nlDataset)
        )
        let bixbyChunks = await contextRetriever.retrieve(
            query: input.rawText,
            topK: 3,
            filter: MetadataFilter(source: .bixbyCommand)
        )

        let capabilities = hydrateCapabilities(from: capabilityChunks)
        let examples = hydrateExamples(from: exampleChunks)
        let bixbyCommands = hydrateBixbyCommands(from: bixbyChunks)

        var sections: [String] = []
        if !capabilities.isEmpty {
            sections.append("Relevant canonical capabilities:\n\(capabilities)")
        }
        if !examples.isEmpty {
            sections.append("Similar canonical command examples:\n\(examples)")
        }
        if !bixbyCommands.isEmpty {
            sections.append("Relevant canonical Bixby commands:\n\(bixbyCommands)")
        }

        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    private func hydrateCapabilities(from chunks: [ScoredChunk]) -> String {
        AgentRAGSupport.stableUnique(chunks.compactMap { scored -> (HomeCapabilityDefinition, Float)? in
            guard let id = scored.chunk.metadata["capabilityId"],
                  let definition = HomeCapabilityRegistry.definitions[id] else {
                return nil
            }
            return (definition, scored.score)
        }) { $0.0.id }
        .map { definition, score in
            [
                "\(definition.id) score=\(String(format: "%.3f", score))",
                "commands=\(definition.commands.joined(separator: ","))",
                "attributes=\(definition.attributeNames.joined(separator: ","))",
                "enumValues=\(definition.enumValues.joined(separator: ","))",
                "range=\(definition.numericRange.map { "\($0.lowerBound)...\($0.upperBound)" } ?? "none")",
                "risk=\(definition.riskLevel)"
            ].joined(separator: "; ")
        }
        .joined(separator: "\n")
    }

    private func hydrateExamples(from chunks: [ScoredChunk]) -> String {
        let examples = HomeAutomationKnowledgeBase.generatedDatasetCommands()
        let examplesByID = Dictionary(uniqueKeysWithValues: examples.map { ($0.id, $0) })
        return AgentRAGSupport.stableUnique(chunks.compactMap { scored -> (HomeGeneratedCommandExample, Float)? in
            guard let id = scored.chunk.metadata["exampleId"],
                  let example = examplesByID[id] else {
                return nil
            }
            return (example, scored.score)
        }) { $0.0.id }
        .map { example, score in
            "\(example.text) score=\(String(format: "%.3f", score)); capability=\(example.capability); command=\(example.command); risk=\(example.riskLevel)"
        }
        .joined(separator: "\n")
    }

    private func hydrateBixbyCommands(from chunks: [ScoredChunk]) -> String {
        AgentRAGSupport.stableUnique(chunks.compactMap { scored -> (HomeBixbyVoiceCommand, Float)? in
            guard let command = Self.hydrateBixbyCommand(from: scored.chunk) else {
                return nil
            }
            return (command, scored.score)
        }) { $0.0.id }
        .map { command, score in
            "\(command.capabilityAction) score=\(String(format: "%.3f", score)); method=\(command.method); hint=\(command.hint)"
        }
        .joined(separator: "\n")
    }

    private static func hydrateBixbyCommand(from chunk: DocumentChunk) -> HomeBixbyVoiceCommand? {
        guard let capability = chunk.metadata["capability"],
              let action = chunk.metadata["action"],
              let method = chunk.metadata["method"] else {
            return nil
        }

        return HomeBixbyCommandCatalog.commands.first {
            $0.capability == capability &&
                $0.action == action &&
                $0.method == method
        }
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
