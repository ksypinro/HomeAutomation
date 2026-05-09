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
        let tools = toolProvider.tools(for: input)
        let budgeter = FoundationModelContextBudgeter()
        let variants = Self.instructionVariants(
            selectedKnowledgeContext: selectedKnowledgeContext,
            hydratedCandidates: input.hydratedCandidates
        )

        var fallback: HomeModelInstructionPackage?
        for variant in variants {
            let instructionText = Self.instructionText(
                focus: focus,
                input: input,
                extraRules: extraRules,
                knowledgeBlock: variant.knowledgeBlock
            )
            let prompt = Self.promptText(
                input: input,
                candidateDescription: variant.candidateDescription,
                selectedKnowledgePrompt: variant.selectedKnowledgePrompt
            )
            let report = budgeter.report(
                instructionText: instructionText,
                prompt: prompt,
                tools: tools,
                candidateCount: input.hydratedCandidates.count,
                ragCapabilitySectionCount: variant.ragCapabilitySectionCount,
                ragExampleSectionCount: variant.ragExampleSectionCount,
                ragBixbySectionCount: variant.ragBixbySectionCount,
                selectedCompactionLevel: variant.compactionLevel,
                estimatedToolOutputCharacterCount: toolProvider.estimatedOutputCharacters(
                    for: tools,
                    candidateCount: input.hydratedCandidates.count
                )
            )
            let package = HomeModelInstructionPackage(
                instructions: Instructions(instructionText),
                instructionText: instructionText,
                prompt: prompt,
                tools: tools,
                useAdapter: false,
                generationMode: .greedy,
                contextBudgetReport: report
            )
            fallback = package
            if budgeter.isWithinBudget(report) {
                return package
            }
        }

        return fallback ?? HomeModelInstructionPackage(
            instructions: Instructions(focus),
            instructionText: focus,
            prompt: input.rawText,
            tools: tools,
            useAdapter: false,
            generationMode: .greedy,
            contextBudgetReport: budgeter.report(
                instructionText: focus,
                prompt: input.rawText,
                tools: tools,
                candidateCount: input.hydratedCandidates.count,
                ragCapabilitySectionCount: 0,
                ragExampleSectionCount: 0,
                ragBixbySectionCount: 0,
                selectedCompactionLevel: "minimal"
            )
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

    private static func compactDescribe(_ candidates: [HomeCandidateRecord], limit: Int = 25) -> String {
        let described = candidates.prefix(limit).map { candidate in
            [
                "id=\(candidate.id)",
                "name=\(candidate.displayName)",
                "type=\(candidate.deviceType)",
                "room=\(candidate.room ?? "none")",
                "caps=\(candidate.capabilities.prefix(4).joined(separator: ","))",
                "risk=\(candidate.riskLevel)"
            ].joined(separator: " ")
        }
        .joined(separator: "\n")
        guard candidates.count > limit else { return described }
        return described + "\nomitted=\(candidates.count - limit)"
    }

    private static func instructionText(
        focus: String,
        input: HomeFinalResolutionInput,
        extraRules: String,
        knowledgeBlock: String
    ) -> String {
        """
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
        """
    }

    private static func promptText(
        input: HomeFinalResolutionInput,
        candidateDescription: String,
        selectedKnowledgePrompt: String
    ) -> String {
        """
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
        \(candidateDescription)
        \(selectedKnowledgePrompt)
        """
    }

    private static func instructionVariants(
        selectedKnowledgeContext: String?,
        hydratedCandidates: [HomeCandidateRecord]
    ) -> [InstructionVariant] {
        let fullKnowledge = selectedKnowledgeContext ?? """
        \(HomeAutomationKnowledgeBase.instructionSummary)

        \(HomeBixbyCommandCatalog.instructionSummary)
        """
        let fullCandidates = describe(hydratedCandidates)
        let compactCandidates = compactDescribe(hydratedCandidates)
        let minimalCandidates = compactDescribe(hydratedCandidates, limit: 8)

        return [
            makeVariant("full", knowledge: fullKnowledge, selectedKnowledgeContext: selectedKnowledgeContext, candidateDescription: fullCandidates),
            makeVariant("dropExamples", knowledge: compactKnowledge(selectedKnowledgeContext, includeCapabilities: true, includeExamples: false, includeBixby: true) ?? fullKnowledge, selectedKnowledgeContext: compactKnowledge(selectedKnowledgeContext, includeCapabilities: true, includeExamples: false, includeBixby: true), candidateDescription: fullCandidates),
            makeVariant("dropBixby", knowledge: compactKnowledge(selectedKnowledgeContext, includeCapabilities: true, includeExamples: false, includeBixby: false) ?? HomeAutomationKnowledgeBase.instructionSummary, selectedKnowledgeContext: compactKnowledge(selectedKnowledgeContext, includeCapabilities: true, includeExamples: false, includeBixby: false), candidateDescription: fullCandidates),
            makeVariant("dropCapabilities", knowledge: compactKnowledge(selectedKnowledgeContext, includeCapabilities: false, includeExamples: false, includeBixby: false) ?? HomeAutomationKnowledgeBase.instructionSummary, selectedKnowledgeContext: compactKnowledge(selectedKnowledgeContext, includeCapabilities: false, includeExamples: false, includeBixby: false), candidateDescription: fullCandidates),
            makeVariant("compactCandidates", knowledge: compactKnowledge(selectedKnowledgeContext, includeCapabilities: true, includeExamples: false, includeBixby: false) ?? HomeAutomationKnowledgeBase.instructionSummary, selectedKnowledgeContext: compactKnowledge(selectedKnowledgeContext, includeCapabilities: true, includeExamples: false, includeBixby: false), candidateDescription: compactCandidates),
            makeVariant("minimal", knowledge: "Use only the provided candidate IDs, tools, and canonical schema values.", selectedKnowledgeContext: nil, candidateDescription: minimalCandidates)
        ]
    }

    private static func makeVariant(
        _ level: String,
        knowledge: String,
        selectedKnowledgeContext: String?,
        candidateDescription: String
    ) -> InstructionVariant {
        let selectedKnowledgePrompt = selectedKnowledgeContext.map {
            """

            Selected RAG context:
            \($0)
            """
        } ?? ""
        return InstructionVariant(
            compactionLevel: level,
            knowledgeBlock: knowledge,
            selectedKnowledgePrompt: selectedKnowledgePrompt,
            candidateDescription: candidateDescription,
            ragCapabilitySectionCount: selectedKnowledgeContext?.contains("Relevant canonical capabilities:") == true ? 1 : 0,
            ragExampleSectionCount: selectedKnowledgeContext?.contains("Similar canonical command examples:") == true ? 1 : 0,
            ragBixbySectionCount: selectedKnowledgeContext?.contains("Relevant canonical Bixby commands:") == true ? 1 : 0
        )
    }

    private static func compactKnowledge(
        _ context: String?,
        includeCapabilities: Bool,
        includeExamples: Bool,
        includeBixby: Bool
    ) -> String? {
        guard let context else { return nil }
        let sections = context.components(separatedBy: "\n\n").filter { section in
            if section.contains("Relevant canonical capabilities:") { return includeCapabilities }
            if section.contains("Similar canonical command examples:") { return includeExamples }
            if section.contains("Relevant canonical Bixby commands:") { return includeBixby }
            return true
        }
        guard !sections.isEmpty else { return nil }
        return sections.joined(separator: "\n\n")
    }

}

private struct InstructionVariant {
    let compactionLevel: String
    let knowledgeBlock: String
    let selectedKnowledgePrompt: String
    let candidateDescription: String
    let ragCapabilitySectionCount: Int
    let ragExampleSectionCount: Int
    let ragBixbySectionCount: Int
}
