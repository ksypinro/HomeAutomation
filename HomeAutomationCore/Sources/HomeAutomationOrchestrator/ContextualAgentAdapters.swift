import Foundation
import FoundationModels
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationRAG
import OSLog

private struct AgentContextInputError: LocalizedError, Sendable {
    let agentID: AgentID
    let message: String

    var errorDescription: String? {
        "\(agentID.rawValue): \(message)"
    }
}

/// A generic wrapper that adapts an agent's specific input/output types into the unified `ResolutionContext`.
///
/// This allows the orchestrator to treat all agents uniformly (`AnyHomeAgent`), while still
/// allowing individual agents to define strict input dependencies and typed outputs.
public struct ContextualHomeAgent<Agent: HomeAgent>: AnyHomeAgent {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "ContextualHomeAgent")
    public let agent: Agent
    private let makeInput: @Sendable (ResolutionContext) throws -> Agent.Input
    private let makePatch: @Sendable (Agent.Output, ResolutionContext) -> ResolutionContextPatch

    public var id: AgentID { agent.id }
    public var capabilities: Set<AgentCapability> { agent.capabilities }
    public var timeoutNanoseconds: UInt64 { agent.timeoutNanoseconds }

    public init(
        agent: Agent,
        makeInput: @escaping @Sendable (ResolutionContext) throws -> Agent.Input,
        makePatch: @escaping @Sendable (Agent.Output, ResolutionContext) -> ResolutionContextPatch
    ) {
        self.agent = agent
        self.makeInput = makeInput
        self.makePatch = makePatch
    }

    /// Executes the underlying agent by converting the context into its required input,
    /// and then mapping its output back to a `ResolutionContextPatch`.
    public func run(context: ResolutionContext) async -> AgentRunResult {
        do {
            logger.debug("Generating input for agent: \(self.id.rawValue, privacy: .public)")
            let input = try makeInput(context)
            
            logger.debug("Running agent: \(self.id.rawValue, privacy: .public)")
            let output = try await agent.run(input, context: context)
            
            let patch = makePatch(output, context)
            logger.debug("Agent \(self.id.rawValue, privacy: .public) produced patch successfully.")
            return .success(patch)
        } catch {
            logger.error("Agent \(self.id.rawValue, privacy: .public) failed with error: \(error.localizedDescription, privacy: .public)")
            return .terminalFailure(
                AgentFailure(
                    agentID: id,
                    reason: error.localizedDescription,
                    isRetryable: false
                )
            )
        }
    }
}

/// A factory for assembling the default set of home automation agents.
/// 
/// This factory configures each agent with its necessary workers, dependencies,
/// and contextual mappers, yielding a ready-to-use `AgentRegistry`.
public enum DefaultAgentRegistryFactory {
    public static func make(
        registry: MockHomeDeviceRegistry = MockHomeDeviceRegistry(),
        contextRetriever: ContextRetriever? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        }
    ) -> AgentRegistry {
        let candidateResolver = HomeCandidateResolverSupport(
            foundationModelAvailability: foundationModelAvailability
        )
        let toolProvider = AgentToolProvider(registry: registry)
        let instructionFactory = AgentInstructionSetFactory(
            toolProvider: toolProvider,
            contextRetriever: contextRetriever
        )
        let draftResolver = AgentDraftResolver()
        let commandValidator = AgentCommandValidator()
        let ruleResolver = AgentRuleBasedResolver(
            registry: registry,
            validator: commandValidator,
            contextRetriever: contextRetriever
        )
        let bixbyMapper = AgentBixbyFallbackMapper()
        let executor = AgentPlanExecutor(registry: registry)

        let agents: [any AnyHomeAgent] = [
            ContextualHomeAgent(
                agent: LanguageAgent(
                    worker: LanguageAgentWorkerSession(foundationModelAvailability: foundationModelAvailability),
                    contextRetriever: contextRetriever
                ),
                makeInput: { $0.request.text },
                makePatch: { output, _ in patch(.language, [ResolutionContextPatchKey.language: output]) }
            ),
            ContextualHomeAgent(
                agent: DomainAgent(
                    worker: DomainAgentWorkerSession(foundationModelAvailability: foundationModelAvailability),
                    contextRetriever: contextRetriever
                ),
                makeInput: { $0.request.text },
                makePatch: { output, _ in patch(.domain, [ResolutionContextPatchKey.domain: output]) }
            ),
            ContextualHomeAgent(
                agent: IntentFamilyAgent(
                    worker: IntentFamilyAgentWorkerSession(foundationModelAvailability: foundationModelAvailability),
                    contextRetriever: contextRetriever
                ),
                makeInput: { $0.request.text },
                makePatch: { output, _ in patch(.intentFamily, [ResolutionContextPatchKey.intent: output]) }
            ),
            ContextualHomeAgent(
                agent: DeviceTypeAgent(
                    worker: DeviceTypeAgentWorkerSession(foundationModelAvailability: foundationModelAvailability),
                    contextRetriever: contextRetriever
                ),
                makeInput: { $0.request.text },
                makePatch: { output, _ in patch(.deviceType, [ResolutionContextPatchKey.deviceType: output]) }
            ),
            ContextualHomeAgent(
                agent: SlotExtractionAgent(
                    worker: SlotExtractionAgentWorkerSession(foundationModelAvailability: foundationModelAvailability),
                    contextRetriever: contextRetriever
                ),
                makeInput: { $0.request.text },
                makePatch: { output, _ in patch(.slotExtraction, [ResolutionContextPatchKey.slots: output]) }
            ),
            ContextualHomeAgent(
                agent: RiskClassificationAgent(
                    worker: RiskClassificationAgentWorkerSession(foundationModelAvailability: foundationModelAvailability),
                    contextRetriever: contextRetriever
                ),
                makeInput: { $0.request.text },
                makePatch: { output, _ in patch(.riskClassification, [ResolutionContextPatchKey.risk: output]) }
            ),
            ContextualHomeAgent(
                agent: CapabilityKnowledgeAgent(contextRetriever: contextRetriever),
                makeInput: capabilityHints,
                makePatch: { output, _ in knowledgePatch(.capabilityKnowledge, output) }
            ),
            ContextualHomeAgent(
                agent: BixbyKnowledgeAgent(contextRetriever: contextRetriever),
                makeInput: { context in
                    BixbyKnowledgeInput(
                        text: context.request.text,
                        deviceNames: deviceNames(from: context)
                    )
                },
                makePatch: { output, _ in knowledgePatch(.bixbyKnowledge, output) }
            ),
            ContextualHomeAgent(
                agent: CommandExampleAgent(contextRetriever: contextRetriever),
                makeInput: { CommandExampleInput(text: $0.request.text, limit: 5) },
                makePatch: { output, _ in knowledgePatch(.commandExample, output) }
            ),
            ContextualHomeAgent(
                agent: RetrievalJudgeAgent(
                    contextRetriever: contextRetriever,
                    foundationModelAvailability: foundationModelAvailability
                ),
                makeInput: { RetrievalJudgeInput(text: $0.request.text) },
                makePatch: { output, _ in knowledgePatch(.retrievalJudge, output) }
            ),
            ContextualHomeAgent(
                agent: CandidateRetrievalAgent(registry: registry, contextRetriever: contextRetriever),
                makeInput: { context in
                    CandidateRetrievalInput(
                        text: context.request.text,
                        state: context.resolutionState ?? fallbackState(for: context.request.text),
                        memoryHints: context.memoryHints
                    )
                },
                makePatch: { output, _ in patch(.candidateRetrieval, [ResolutionContextPatchKey.retrievedCandidates: output]) }
            ),
            ContextualHomeAgent(
                agent: CandidateRankingAgent(resolver: candidateResolver),
                makeInput: { context in
                    CandidateRankingInput(
                        text: context.request.text,
                        state: try state(from: context, agentID: .candidateRanking),
                        candidates: context.retrievedCandidates.map(\.compactView),
                        memoryHints: context.memoryHints
                    )
                },
                makePatch: { output, _ in
                    var updates: [String: any Sendable] = [
                        ResolutionContextPatchKey.aggregation: output,
                        ResolutionContextPatchKey.selectedCandidateIDs: output.finalCandidateIDs
                    ]
                    if output.needsClarification {
                        updates[ResolutionContextPatchKey.resolution] = HomeCommandResolution.needsClarification(
                            output.clarificationQuestion ?? "Which device do you want to control?"
                        )
                    }
                    return patch(.candidateRanking, updates)
                }
            ),
            ContextualHomeAgent(
                agent: CandidateShardAgent(resolver: candidateResolver),
                makeInput: { context in
                    CandidateShardInput(
                        text: context.request.text,
                        state: try state(from: context, agentID: .candidateShard),
                        shard: context.retrievedCandidates.map(\.compactView),
                        memoryHints: context.memoryHints
                    )
                },
                makePatch: { output, _ in patch(.candidateShard, [ResolutionContextPatchKey.selectedCandidateIDs: output.selectedCandidateIDs]) }
            ),
            ContextualHomeAgent(
                agent: CandidateHydrationAgent(registry: registry),
                makeInput: { context in
                    CandidateHydrationInput(candidateIDs: context.aggregation?.finalCandidateIDs ?? context.selectedCandidateIDs)
                },
                makePatch: { output, _ in patch(.candidateHydration, [ResolutionContextPatchKey.hydratedCandidates: output]) }
            ),
            ContextualHomeAgent(
                agent: InstructionComposerAgent(factory: instructionFactory),
                makeInput: finalInput,
                makePatch: { output, _ in patch(.instructionComposer, [ResolutionContextPatchKey.instructionPackage: output]) }
            ),
            ContextualHomeAgent(
                agent: DraftGenerationAgent(resolver: draftResolver),
                makeInput: { context in
                    guard let package = context.instructionPackage else {
                        throw AgentContextInputError(agentID: .draftGeneration, message: "Missing instruction package")
                    }
                    return package
                },
                makePatch: { output, _ in patch(.draftGeneration, [ResolutionContextPatchKey.draft: output]) }
            ),
            ContextualHomeAgent(
                agent: DraftRepairAgent(resolver: draftResolver),
                makeInput: { context in
                    guard let package = context.instructionPackage else {
                        throw AgentContextInputError(agentID: .draftRepair, message: "Missing instruction package")
                    }
                    return package
                },
                makePatch: { output, _ in patch(.draftRepair, [ResolutionContextPatchKey.draft: output.draft]) }
            ),
            ContextualHomeAgent(
                agent: SafetyValidationAgent(validator: commandValidator),
                makeInput: { context in
                    guard let draft = context.draft else {
                        throw AgentContextInputError(agentID: .safetyValidation, message: "Missing draft")
                    }
                    return SafetyValidationInput(draft: draft, finalInput: try finalInput(context))
                },
                makePatch: { output, _ in
                    var updates: [String: any Sendable] = [ResolutionContextPatchKey.resolution: output]
                    if case .readyToExecute(let plan) = output {
                        updates[ResolutionContextPatchKey.executionPlan] = plan
                    }
                    return patch(.safetyValidation, updates)
                }
            ),
            ContextualHomeAgent(
                agent: ParameterValidationAgent(),
                makeInput: { context in
                    guard let draft = context.draft,
                          let device = selectedDevice(from: context),
                          let capability = draft.capability,
                          let command = draft.command else {
                        throw AgentContextInputError(agentID: .parameterValidation, message: "Missing draft, target, capability, or command")
                    }
                    return ParameterValidationInput(
                        parameters: draft.parameters,
                        capability: capability,
                        command: command,
                        device: device
                    )
                },
                makePatch: { output, _ in
                    output
                        ? patch(.parameterValidation, [:])
                        : patch(.parameterValidation, [ResolutionContextPatchKey.resolution: HomeCommandResolution.needsClarification("Some command values are invalid or missing.")])
                }
            ),
            ContextualHomeAgent(
                agent: ConfirmationPolicyAgent(),
                makeInput: { context in
                    guard let draft = context.draft,
                          let device = selectedDevice(from: context) else {
                        throw AgentContextInputError(agentID: .confirmationPolicy, message: "Missing draft or selected device")
                    }
                    return ConfirmationPolicyInput(
                        intent: draft.intent,
                        capability: draft.capability,
                        deviceType: device.deviceType,
                        candidateRisk: device.riskLevel,
                        command: draft.command,
                        memoryContributedTarget: memoryContributedTarget(deviceID: device.id, context: context)
                    )
                },
                makePatch: { output, context in
                    if output, let draft = context.draft {
                        return patch(.confirmationPolicy, [ResolutionContextPatchKey.resolution: HomeCommandResolution.requiresConfirmation(draft)])
                    }
                    return patch(.confirmationPolicy, [:])
                }
            ),
            ContextualHomeAgent(
                agent: ExecutionPlanningAgent(),
                makeInput: { context in
                    guard let draft = context.draft,
                          let device = selectedDevice(from: context) else {
                        throw AgentContextInputError(agentID: .executionPlanning, message: "Missing draft or selected device")
                    }
                    return ExecutionPlanningInput(draft: draft, device: device)
                },
                makePatch: { output, _ in
                    patch(
                        .executionPlanning,
                        [
                            ResolutionContextPatchKey.executionPlan: output,
                            ResolutionContextPatchKey.resolution: HomeCommandResolution.readyToExecute(output)
                        ]
                    )
                }
            ),
            ContextualHomeAgent(
                agent: MockExecutionAgent(execute: executor.executeLowRiskPlan),
                makeInput: { context in
                    guard let plan = context.executionPlan else {
                        throw AgentContextInputError(agentID: .mockExecution, message: "Missing execution plan")
                    }
                    return plan
                },
                makePatch: { output, context in
                    let plan = context.executionPlan ?? HomeAutomationExecutionPlan(steps: [], requiresConfirmation: false)
                    return patch(.mockExecution, [ResolutionContextPatchKey.resolution: HomeCommandResolution.executed(plan, updatedDevice: output)])
                }
            ),
            ContextualHomeAgent(
                agent: RuleFallbackAgent(resolver: ruleResolver),
                makeInput: {
                    RuleFallbackInput(
                        text: $0.request.text,
                        executeLowRiskCommands: $0.request.executeLowRiskCommands,
                        memoryHints: $0.memoryHints
                    )
                },
                makePatch: { output, _ in patch(.ruleFallback, [ResolutionContextPatchKey.resolverResult: output]) }
            ),
            ContextualHomeAgent(
                agent: BixbyFallbackAgent(mapper: bixbyMapper),
                makeInput: { context in
                    BixbyFallbackInput(text: context.request.text, devices: context.retrievedCandidates)
                },
                makePatch: { output, context in
                    guard let first = output.first else {
                        return patch(.bixbyFallback, [:])
                    }
                    let aggregation = HomeCandidateAggregationResult(
                        finalCandidateIDs: [first.device.id],
                        needsClarification: false,
                        confidence: min(0.98, Double(first.score) / 36.0)
                    )
                    return patch(
                        .bixbyFallback,
                        [
                            ResolutionContextPatchKey.aggregation: aggregation,
                            ResolutionContextPatchKey.hydratedCandidates: [first.device],
                            ResolutionContextPatchKey.draft: first.draft
                        ]
                    )
                }
            ),
            ContextualHomeAgent(
                agent: UnsupportedCommandAgent(),
                makeInput: { $0.request.text },
                makePatch: { output, _ in patch(.unsupportedCommand, [ResolutionContextPatchKey.resolution: output]) }
            ),
            ContextualHomeAgent(
                agent: ClarificationAgent(),
                makeInput: { context in context.aggregation?.clarificationQuestion ?? "Which device do you want to control?" },
                makePatch: { output, _ in patch(.clarification, [ResolutionContextPatchKey.resolution: output]) }
            ),
            ContextualHomeAgent(
                agent: ResultSummaryAgent(),
                makeInput: { context in context.resolution ?? .unsupported("No resolution produced") },
                makePatch: { _, _ in patch(.resultSummary, [:]) }
            )
        ]

        return AgentRegistry(agents: agents)
    }

    private static func patch(_ agentID: AgentID, _ values: [String: any Sendable]) -> ResolutionContextPatch {
        ResolutionContextPatch(
            agentID: agentID,
            updates: values.mapValues { AnySendableValue($0) }
        )
    }

    private static func knowledgePatch(
        _ agentID: AgentID,
        _ output: KnowledgeRetrievalAgentOutput
    ) -> ResolutionContextPatch {
        patch(
            agentID,
            [
                ResolutionContextPatchKey.knowledgeSnippets: output.snippets,
                ResolutionContextPatchKey.retrievalReports: output.reports
            ]
        )
    }

    private static func state(from context: ResolutionContext, agentID: AgentID) throws -> HomeResolutionState {
        guard let state = context.resolutionState else {
            throw AgentContextInputError(agentID: agentID, message: "Missing resolution state")
        }
        return state
    }

    private static func finalInput(_ context: ResolutionContext) throws -> HomeFinalResolutionInput {
        HomeFinalResolutionInput(
            rawText: context.request.text,
            resolutionState: try state(from: context, agentID: .instructionComposer),
            hydratedCandidates: context.hydratedCandidates,
            aggregation: context.aggregation ?? HomeCandidateAggregationResult(
                finalCandidateIDs: context.selectedCandidateIDs,
                needsClarification: false,
                confidence: 0
            )
        )
    }

    private static func fallbackState(for text: String) -> HomeResolutionState {
        AgentTextParser.deterministicState(for: text, confidence: 0.42, riskReason: "Orchestrator fallback state")
    }

    private static func selectedDevice(from context: ResolutionContext) -> HomeCandidateRecord? {
        guard let id = context.draft?.targetDeviceID ?? context.aggregation?.finalCandidateIDs.first ?? context.selectedCandidateIDs.first else {
            return nil
        }
        return context.hydratedCandidates.first { $0.id == id } ??
            context.retrievedCandidates.first { $0.id == id }
    }

    private static func memoryContributedTarget(deviceID: String, context: ResolutionContext) -> Bool {
        context.memoryHints.contains { $0.deviceID == deviceID }
    }

    private static func deviceNames(from context: ResolutionContext) -> [String] {
        let names = (context.hydratedCandidates + context.retrievedCandidates).map(\.displayName)
        if !names.isEmpty {
            return names
        }

        let slots = context.slots ?? context.resolutionState?.slots
        let deviceTypes = context.deviceType?.deviceTypes ?? context.resolutionState?.deviceType.deviceTypes ?? []
        let rooms = slots?.rooms ?? []
        let inferred = rooms.flatMap { room in
            deviceTypes.map { "\(room) \(Self.displayName(forDeviceType: $0))" }
        } + deviceTypes.map(Self.displayName(forDeviceType:))
        return inferred.isEmpty ? ["device"] : stableUnique(inferred)
    }

    private static func displayName(forDeviceType deviceType: String) -> String {
        deviceType
            .agentNormalizedHomeTokenString
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let key = value.agentNormalizedHomeTokenString
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(value)
        }
        return result
    }

    private static func capabilityHints(from context: ResolutionContext) -> [String] {
        var values = Set(context.hydratedCandidates.flatMap(\.capabilities) + context.retrievedCandidates.flatMap(\.capabilities))
        let families = context.intent?.topFamilies ?? context.resolutionState?.intent.topFamilies ?? []
        for family in families {
            switch family {
            case .createAutomation:
                break
            case .power:
                values.insert("switch")
            case .temperature:
                values.insert("thermostatCoolingSetpoint")
                values.insert("thermostatHeatingSetpoint")
                values.insert("thermostatMode")
            case .brightness:
                values.insert("switchLevel")
            case .lockUnlock:
                values.insert("lock")
            case .openClose:
                values.insert("garageDoorControl")
                values.insert("doorControl")
                values.insert("windowShade")
            case .routine:
                values.insert("routine")
            case .statusQuery:
                values.insert("temperatureMeasurement")
                values.insert("contactSensor")
                values.insert("battery")
            case .media:
                values.insert("mediaPlayback")
                values.insert("audioVolume")
            case .applianceCycle:
                values.insert("washerOperatingState")
                values.insert("dryerOperatingState")
            case .maintenanceQuery, .unsupported:
                break
            }
        }
        return values.sorted()
    }
}
