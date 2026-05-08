import Foundation
import FoundationModels
import HomeAutomationCore
import HomeAutomationRAG

public struct AgentDraftAttemptReport: Sendable, Codable, Equatable {
    public let name: String
    public let useAdapter: Bool
    public let simplifiedPrompt: Bool
    public let outcome: String
    public let confidence: Double?
    public let selected: Bool
    public let errorDescription: String?

    public var summary: String {
        var parts = ["\(name) \(outcome)"]
        if let confidence {
            parts.append("confidence=\(confidence)")
        }
        if selected {
            parts.append("selected")
        }
        if let errorDescription {
            parts.append("error=\(errorDescription)")
        }
        return parts.joined(separator: " ")
    }

    public init(
        name: String,
        useAdapter: Bool,
        simplifiedPrompt: Bool,
        outcome: String,
        confidence: Double?,
        selected: Bool,
        errorDescription: String?
    ) {
        self.name = name
        self.useAdapter = useAdapter
        self.simplifiedPrompt = simplifiedPrompt
        self.outcome = outcome
        self.confidence = confidence
        self.selected = selected
        self.errorDescription = errorDescription
    }

    func selecting() -> AgentDraftAttemptReport {
        AgentDraftAttemptReport(
            name: name,
            useAdapter: useAdapter,
            simplifiedPrompt: simplifiedPrompt,
            outcome: outcome,
            confidence: confidence,
            selected: true,
            errorDescription: errorDescription
        )
    }
}

public struct AgentDraftResolutionReport: Sendable, Codable, Equatable {
    public let attempts: [AgentDraftAttemptReport]
    public let selectedAttemptName: String?

    public var attemptCount: Int { attempts.count }
    public var attemptSummaries: [String] { attempts.map(\.summary) }
    public var bestDraftAttempt: String? { selectedAttemptName }

    public init(attempts: [AgentDraftAttemptReport], selectedAttemptName: String?) {
        self.attempts = attempts
        self.selectedAttemptName = selectedAttemptName
    }
}

public struct AgentDraftResolutionOutput: Sendable {
    public let draft: HomeCommandDraft
    public let report: AgentDraftResolutionReport

    public init(draft: HomeCommandDraft, report: AgentDraftResolutionReport) {
        self.draft = draft
        self.report = report
    }
}

public actor AgentDraftResolverMetrics {
    private var report: AgentDraftResolutionReport?

    public init() {}

    public func store(_ report: AgentDraftResolutionReport) {
        self.report = report
    }

    public func lastReport() -> AgentDraftResolutionReport? {
        report
    }
}

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

public struct AgentDraftResolver: HomeCommandDraftResolving {
    private let resolver: any HomeCommandDraftResolving
    private let confidenceThreshold: Double
    private let metrics: AgentDraftResolverMetrics?

    public init(
        adapterProvider: HomeAdapterModelProvider = HomeAdapterModelProvider(),
        confidenceThreshold: Double = 0.70,
        metrics: AgentDraftResolverMetrics? = nil,
        resolver: (any HomeCommandDraftResolving)? = nil
    ) {
        self.resolver = resolver ?? FoundationHomeCommandDraftResolver(adapterProvider: adapterProvider)
        self.confidenceThreshold = confidenceThreshold
        self.metrics = metrics
    }

    public func resolveDraft(from package: HomeModelInstructionPackage) async throws -> HomeCommandDraft {
        let output = try await resolveDraftWithReport(from: package)
        await metrics?.store(output.report)
        return output.draft
    }

    public func resolveDraftWithReport(from package: HomeModelInstructionPackage) async throws -> AgentDraftResolutionOutput {
        var lastError: Error?
        var bestDraft: HomeCommandDraft?
        var bestAttemptIndex: Int?
        var attempts: [AgentDraftAttemptReport] = []

        for candidate in retryPackages(for: package) {
            do {
                let draft = try await resolver.resolveDraft(from: candidate.package)
                if draft.confidence >= confidenceThreshold {
                    attempts.append(
                        AgentDraftAttemptReport(
                            name: candidate.name,
                            useAdapter: candidate.useAdapter,
                            simplifiedPrompt: candidate.simplifiedPrompt,
                            outcome: "success",
                            confidence: draft.confidence,
                            selected: true,
                            errorDescription: nil
                        )
                    )
                    return AgentDraftResolutionOutput(
                        draft: draft,
                        report: AgentDraftResolutionReport(attempts: attempts, selectedAttemptName: candidate.name)
                    )
                }
                if bestDraft.map({ draft.confidence > $0.confidence }) ?? true {
                    bestDraft = draft
                    bestAttemptIndex = attempts.count
                }
                attempts.append(
                    AgentDraftAttemptReport(
                        name: candidate.name,
                        useAdapter: candidate.useAdapter,
                        simplifiedPrompt: candidate.simplifiedPrompt,
                        outcome: "low-confidence",
                        confidence: draft.confidence,
                        selected: false,
                        errorDescription: nil
                    )
                )
            } catch {
                lastError = error
                attempts.append(
                    AgentDraftAttemptReport(
                        name: candidate.name,
                        useAdapter: candidate.useAdapter,
                        simplifiedPrompt: candidate.simplifiedPrompt,
                        outcome: "error",
                        confidence: nil,
                        selected: false,
                        errorDescription: error.localizedDescription
                    )
                )
            }
        }

        if let bestDraft, let bestAttemptIndex {
            attempts[bestAttemptIndex] = attempts[bestAttemptIndex].selecting()
            return AgentDraftResolutionOutput(
                draft: bestDraft,
                report: AgentDraftResolutionReport(
                    attempts: attempts,
                    selectedAttemptName: attempts[bestAttemptIndex].name
                )
            )
        }

        let report = AgentDraftResolutionReport(attempts: attempts, selectedAttemptName: nil)
        await metrics?.store(report)
        throw lastError ?? FoundationLabCoreError.invalidRequest("Agent draft resolver failed")
    }

    private func retryPackages(for package: HomeModelInstructionPackage) -> [AgentDraftPackageAttempt] {
        [
            makeAttempt(from: package, name: "base/full", useAdapter: false, simplifyPrompt: false),
            makeAttempt(from: package, name: "adapter/full", useAdapter: true, simplifyPrompt: false),
            makeAttempt(from: package, name: "base/simplified", useAdapter: false, simplifyPrompt: true),
            makeAttempt(from: package, name: "adapter/simplified", useAdapter: true, simplifyPrompt: true)
        ]
    }

    private func makeAttempt(
        from package: HomeModelInstructionPackage,
        name: String,
        useAdapter: Bool,
        simplifyPrompt: Bool
    ) -> AgentDraftPackageAttempt {
        AgentDraftPackageAttempt(
            name: name,
            useAdapter: useAdapter,
            simplifiedPrompt: simplifyPrompt,
            package: HomeModelInstructionPackage(
                instructions: package.instructions,
                prompt: simplifyPrompt ? simplifiedPrompt(from: package.prompt) : package.prompt,
                tools: package.tools,
                useAdapter: useAdapter,
                generationMode: package.generationMode
            )
        )
    }

    private func simplifiedPrompt(from prompt: String) -> String {
        """
        Resolve the smart-home command using only the hydrated candidate IDs, capabilities, and commands in this prompt.
        Return a single HomeCommandDraft. If the target or command is ambiguous, set needsClarification true.

        \(prompt)
        """
    }
}

private struct AgentDraftPackageAttempt {
    let name: String
    let useAdapter: Bool
    let simplifiedPrompt: Bool
    let package: HomeModelInstructionPackage
}

public struct InstructionComposerAgent: HomeAgent {
    public typealias Input = HomeFinalResolutionInput
    public typealias Output = HomeModelInstructionPackage

    public let id = AgentID.instructionComposer
    public let capabilities: Set<AgentCapability> = [.instructionComposition]
    public let timeoutNanoseconds: UInt64 = 5_000_000_000
    private let compose: @Sendable (HomeFinalResolutionInput) async throws -> HomeModelInstructionPackage

    public init(compose: @escaping @Sendable (HomeFinalResolutionInput) async throws -> HomeModelInstructionPackage) {
        self.compose = compose
    }

    public init(factory: AgentInstructionSetFactory) {
        self.compose = { input in await factory.makePackageWithRAG(from: input) }
    }

    public init(registry: MockHomeDeviceRegistry = MockHomeDeviceRegistry()) {
        self.init(factory: AgentInstructionSetFactory(toolProvider: AgentToolProvider(registry: registry)))
    }

    public func run(_ input: HomeFinalResolutionInput, context: ResolutionContext) async throws -> HomeModelInstructionPackage {
        try await compose(input)
    }
}

public struct DraftGenerationAgent: HomeAgent {
    public typealias Input = HomeModelInstructionPackage
    public typealias Output = HomeCommandDraft

    public let id = AgentID.draftGeneration
    public let capabilities: Set<AgentCapability> = [.draftGeneration]
    public let timeoutNanoseconds: UInt64 = 20_000_000_000
    private let generate: @Sendable (HomeModelInstructionPackage) async throws -> HomeCommandDraft

    public init(generate: @escaping @Sendable (HomeModelInstructionPackage) async throws -> HomeCommandDraft) {
        self.generate = generate
    }

    public init(resolver: AgentDraftResolver = AgentDraftResolver()) {
        self.generate = resolver.resolveDraft
    }

    public func run(_ input: HomeModelInstructionPackage, context: ResolutionContext) async throws -> HomeCommandDraft {
        try await generate(input)
    }
}

public struct DraftRepairAgent: HomeAgent {
    public typealias Input = HomeModelInstructionPackage
    public typealias Output = AgentDraftResolutionOutput

    public let id = AgentID.draftRepair
    public let capabilities: Set<AgentCapability> = [.draftRepair]
    public let timeoutNanoseconds: UInt64 = 25_000_000_000
    private let repair: @Sendable (HomeModelInstructionPackage) async throws -> AgentDraftResolutionOutput

    public init(repair: @escaping @Sendable (HomeModelInstructionPackage) async throws -> AgentDraftResolutionOutput) {
        self.repair = repair
    }

    public init(resolver: AgentDraftResolver = AgentDraftResolver()) {
        self.repair = resolver.resolveDraftWithReport
    }

    public func run(_ input: HomeModelInstructionPackage, context: ResolutionContext) async throws -> AgentDraftResolutionOutput {
        try await repair(input)
    }
}
