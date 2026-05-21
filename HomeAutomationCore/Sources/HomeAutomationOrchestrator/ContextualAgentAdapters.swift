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

private final class AgentRegistryBox: @unchecked Sendable {
    var registry: AgentRegistry?
}

private protocol AgentModule: Sendable {
    var name: String { get }
    func makeAgents() -> [any AnyHomeAgent]
}

private struct StaticAgentModule: AgentModule {
    let name: String
    let agents: [any AnyHomeAgent]

    func makeAgents() -> [any AnyHomeAgent] {
        agents
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
    public var manifest: AgentManifest { agent.manifest }
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
        let startedAt = Date()
        do {
            logger.debug("Generating input for agent: \(self.id.rawValue, privacy: .public)")
            let input = try makeInput(context)
            await HomeAutomationTelemetry.shared.logAgentInput(
                String(describing: input),
                inputType: String(reflecting: Agent.Input.self)
            )
            
            logger.debug("Running agent: \(self.id.rawValue, privacy: .public)")
            let output = try await agent.run(input, context: context)
            let evaluationPayload = Self.evaluationPayload(for: output)
            await HomeAutomationTelemetry.shared.logAgentOutput(
                String(describing: output),
                outputType: String(reflecting: Agent.Output.self),
                durationMs: Date().timeIntervalSince(startedAt) * 1_000
            )
            if !evaluationPayload.isEmpty {
                await HomeAutomationTelemetry.shared.log(
                    "agent.evaluationOutput",
                    status: "completed",
                    durationMs: Date().timeIntervalSince(startedAt) * 1_000,
                    payload: evaluationPayload
                )
            }
            
            let patch = makePatch(output, context)
            await HomeAutomationTelemetry.shared.log(
                "agent.patch",
                payload: Self.patchEvaluationPayload(for: patch).merging(
                    ["patch": String(describing: patch)],
                    uniquingKeysWith: { current, _ in current }
                )
            )
            logger.debug("Agent \(self.id.rawValue, privacy: .public) produced patch successfully.")
            return .success(patch)
        } catch {
            await HomeAutomationTelemetry.shared.log(
                "agent.failed",
                status: "failed",
                durationMs: Date().timeIntervalSince(startedAt) * 1_000,
                payload: [
                    "error": error.localizedDescription
                ]
            )
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

    private static func evaluationPayload(for output: Agent.Output) -> [String: String] {
        if let decision = output as? HomeCapabilityDecision {
            var payload: [String: String] = [
                "selectedCapability": decision.selectedCapability ?? "",
                "selectedCommand": decision.selectedCommand ?? "",
                "targetDeviceID": decision.targetDeviceID ?? "",
                "confidence": String(decision.confidence),
                "alternativeCount": String(decision.alternatives.count)
            ]
            payload["evidence"] = decision.evidence.joined(separator: " | ")
            return payload
        }
        if let routing = output as? HomeOperationRoutingResult {
            return [
                "producedFields": "operation,language,domain",
                "mergedAgentIDs": "operationDetection,language,domain",
                "operation": routing.operation.operation.rawValue,
                "operationConfidence": String(routing.operation.confidence),
                "languageCode": routing.language.languageCode,
                "languageConfidence": String(routing.language.confidence),
                "domain": String(describing: routing.domain.domain),
                "domainConfidence": String(routing.domain.confidence)
            ]
        }
        if let semantic = output as? HomeSemanticNLUResult {
            return [
                "producedFields": "intent,deviceType",
                "mergedAgentIDs": "intentFamily,deviceType",
                "intentFamilies": semantic.intent.topFamilies.map(String.init(describing:)).joined(separator: ","),
                "intentConfidence": String(semantic.intent.confidence),
                "deviceTypes": semantic.deviceType.deviceTypes.joined(separator: ","),
                "deviceTypeConfidence": String(semantic.deviceType.confidence)
            ]
        }
        if let aggregation = output as? HomeCandidateAggregationResult {
            return [
                "selectedCandidateIDs": aggregation.finalCandidateIDs.joined(separator: ","),
                "needsClarification": String(aggregation.needsClarification),
                "confidence": String(aggregation.confidence)
            ]
        }
        if let validation = output as? AutomationValidationResult {
            return [
                "validationResult": validation.status.rawValue,
                "requiresConfirmation": String(validation.requiresConfirmation),
                "issueCount": String(validation.issues.count)
            ]
        }
        if let resolution = output as? HomeCommandResolution {
            return [
                "finalOutcome": resolution.displaySummary
            ]
        }
        if let creation = output as? SmartThingsRuleCreationOutput {
            let status = creation.receipt?.status.rawValue ?? (creation.plan.requiresConfirmation ? "confirmationRequired" : "skipped")
            return [
                "validationResult": status,
                "requiresConfirmation": String(creation.plan.requiresConfirmation),
                "finalOutcome": status
            ]
        }
        return [:]
    }

    private static func patchEvaluationPayload(for patch: ResolutionContextPatch) -> [String: String] {
        var payload: [String: String] = [:]
        if let aggregation = patch.updates[ResolutionContextPatchKey.aggregation.rawValue]?.get(HomeCandidateAggregationResult.self) {
            payload["selectedCandidateIDs"] = aggregation.finalCandidateIDs.joined(separator: ",")
        }
        if let decision = patch.updates[ResolutionContextPatchKey.capabilityDecision.rawValue]?.get(HomeCapabilityDecision.self) {
            payload["selectedCapability"] = decision.selectedCapability ?? ""
            payload["selectedCommand"] = decision.selectedCommand ?? ""
            payload["targetDeviceID"] = decision.targetDeviceID ?? ""
        }
        if let resolution = patch.updates[ResolutionContextPatchKey.resolution.rawValue]?.get(HomeCommandResolution.self) {
            payload["finalOutcome"] = resolution.displaySummary
        }
        if let validation = patch.scopedUpdates[.root]?[ResolutionContextPatchKey.automationValidation.rawValue]?.get(AutomationValidationResult.self) {
            payload["validationResult"] = validation.status.rawValue
        }
        if let transition = patch.transitionRequest {
            payload["graphTransitionKind"] = transition.kind
            payload["graphTransitionReason"] = transition.reason
        }
        if patch.updates[ResolutionContextPatchKey.operation.rawValue]?.get(HomeOperationDetectionResult.self) != nil,
           patch.updates[ResolutionContextPatchKey.language.rawValue]?.get(HomeLanguageDetectionResult.self) != nil,
           patch.updates[ResolutionContextPatchKey.domain.rawValue]?.get(HomeDomainClassificationResult.self) != nil {
            payload["producedFields"] = "operation,language,domain"
            payload["mergedAgentIDs"] = "operationDetection,language,domain"
        }
        if patch.updates[ResolutionContextPatchKey.intent.rawValue]?.get(HomeIntentFamilyResult.self) != nil,
           patch.updates[ResolutionContextPatchKey.deviceType.rawValue]?.get(HomeDeviceTypeResult.self) != nil {
            payload["producedFields"] = "intent,deviceType"
            payload["mergedAgentIDs"] = "intentFamily,deviceType"
        }
        return payload
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
        },
        smartThingsRuleCreator: (any SmartThingsRuleCreating)? = nil
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
        let registryBox = AgentRegistryBox()

        let agents: [any AnyHomeAgent] = [
            ContextualHomeAgent(
                agent: OperationDetectionAgent(
                    worker: OperationDetectionWorkerSession(
                        ruleDetect: { text in HomeOperationDetectionService().analyzeSemantics(text) },
                        foundationModelAvailability: foundationModelAvailability
                    )
                ),
                makeInput: { $0.request.text },
                makePatch: { output, _ in
                    patch(
                        .operationDetection,
                        [
                            ResolutionContextPatchKey.operation.rawValue: output.operation,
                            ResolutionContextPatchKey.language.rawValue: output.language,
                            ResolutionContextPatchKey.domain.rawValue: output.domain
                        ]
                    )
                }
            ),
            ContextualHomeAgent(
                agent: SemanticNLUAgent(
                    worker: SemanticNLUWorkerSession(foundationModelAvailability: foundationModelAvailability),
                    contextRetriever: contextRetriever
                ),
                makeInput: { $0.request.text },
                makePatch: { output, _ in
                    patch(
                        .semanticNLU,
                        [
                            ResolutionContextPatchKey.intent.rawValue: output.intent,
                            ResolutionContextPatchKey.deviceType.rawValue: output.deviceType
                        ]
                    )
                }
            ),
            ContextualHomeAgent(
                agent: SlotExtractionAgent(
                    worker: SlotExtractionAgentWorkerSession(foundationModelAvailability: foundationModelAvailability),
                    contextRetriever: contextRetriever
                ),
                makeInput: { $0.request.text },
                makePatch: { output, _ in patch(.slotExtraction, [ResolutionContextPatchKey.slots.rawValue: output]) }
            ),
            ContextualHomeAgent(
                agent: RiskClassificationAgent(
                    worker: RiskClassificationAgentWorkerSession(foundationModelAvailability: foundationModelAvailability),
                    contextRetriever: contextRetriever
                ),
                makeInput: { $0.request.text },
                makePatch: { output, _ in patch(.riskClassification, [ResolutionContextPatchKey.risk.rawValue: output]) }
            ),
            ContextualHomeAgent(
                agent: AutomationDraftExtractionAgent(
                    draftAgent: AutomationDraftAgent(
                        worker: AutomationDraftWorkerSession(
                            foundationModelAvailability: foundationModelAvailability,
                            contextRetriever: contextRetriever
                        )
                    )
                ),
                makeInput: { context in
                    AutomationDraftInput(
                        text: context.request.text,
                        operation: context.operation ?? HomeOperationDetectionService().analyzeSemantics(context.request.text)
                    )
                },
                makePatch: { output, _ in
                    var patch = ResolutionContextPatch(
                        agentID: .automationDraft,
                        updates: [
                            ResolutionContextPatchKey.retrievalReports.rawValue: AnySendableValue(output.retrievalReports)
                        ]
                    )
                    patch.setArtifact(output.ruleDraft, for: ContextArtifactKeys.automationRuleDraft())
                    return patch
                }
            ),
            ContextualHomeAgent(
                agent: AutomationConditionOperandResolutionAgent(
                    resolveDraft: AutomationConditionOperandResolver(
                        registry: registry,
                        foundationModelAvailability: foundationModelAvailability
                    ).resolveDraft
                ),
                makeInput: { context in
                    try context.requireArtifact(for: ContextArtifactKeys.automationRuleDraft())
                },
                makePatch: { output, _ in
                    automationConditionPatch(output)
                }
            ),
            ContextualHomeAgent(
                agent: AutomationActionResolutionAgent(
                    resolveActions: { actionDescriptions, eventBus, runID in
                        guard let agentRegistry = registryBox.registry else {
                            return []
                        }
                        let resolver = AutomationActionResolver(
                            registry: agentRegistry,
                            graphPlanner: GraphPlanner(
                                policy: OrchestratorPolicyEngine(isModelAvailable: foundationModelAvailability)
                            ),
                            policy: OrchestratorPolicyEngine(isModelAvailable: foundationModelAvailability)
                        )
                        return await resolver.resolveAll(
                            actionDescriptions,
                            eventBus: eventBus,
                            runID: runID
                        )
                    }
                ),
                makeInput: { context in
                    try context.requireArtifact(for: ContextArtifactKeys.automationRuleDraft()).actionDescriptions
                },
                makePatch: automationActionPatch
            ),
            ContextualHomeAgent(
                agent: AutomationValidationAgent(),
                makeInput: { context in
                    let draft = try context.requireArtifact(for: ContextArtifactKeys.automationRuleDraft())
                    let aggregate = context.scopedValue(for: AutomationRuntimeContextKeys.actionResolutionAggregate)
                    return AutomationValidationInput(
                        ruleDraft: draft,
                        resolvedActions: aggregate?.resolvedActions ?? []
                    )
                },
                makePatch: { output, _ in
                    scopedPatch(
                        .automationValidation,
                        scope: .root,
                        [
                            ContextArtifactKeys.validation().name: output
                        ]
                    )
                }
            ),
            ContextualHomeAgent(
                agent: SmartThingsCompilationAgent(),
                makeInput: { context in
                    let draft = try context.requireArtifact(for: ContextArtifactKeys.automationRuleDraft())
                    guard let aggregate = context.scopedValue(for: AutomationRuntimeContextKeys.actionResolutionAggregate) else {
                        throw AgentContextInputError(agentID: .smartThingsCompilation, message: "Missing resolved automation actions")
                    }
                    return SmartThingsCompilationInput(
                        ruleDraft: draft,
                        resolvedActions: aggregate.resolvedActions,
                        requiresConfirmation: aggregate.requiresConfirmation,
                        validation: context.artifact(for: ContextArtifactKeys.validation())
                    )
                },
                makePatch: smartThingsCompilationPatch
            ),
            ContextualHomeAgent(
                agent: SmartThingsRuleCreationAgent(creator: smartThingsRuleCreator),
                makeInput: { context in
                    guard let compilation = context.scopedValue(for: AutomationRuntimeContextKeys.smartThingsCompilation) else {
                        throw AgentContextInputError(agentID: .smartThingsRuleCreation, message: "Missing SmartThings compilation output")
                    }
                    return SmartThingsRuleCreationInput(
                        plan: compilation.plan,
                        document: compilation.document,
                        validation: context.artifact(for: ContextArtifactKeys.validation()),
                        options: context.request.automationCreationOptions
                    )
                },
                makePatch: smartThingsRuleCreationPatch
            ),
            ContextualHomeAgent(
                agent: AutomationResultAssemblyAgent(),
                makeInput: { $0 },
                makePatch: { output, _ in
                    patch(.automationResultAssembly, [ResolutionContextPatchKey.resolverResult.rawValue: output])
                }
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
                    candidateRetrievalInput(from: context)
                },
                makePatch: { output, _ in patch(.candidateRetrieval, [ResolutionContextPatchKey.retrievedCandidates.rawValue: output]) }
            ),
            ContextualHomeAgent(
                agent: CandidateRankingAgent(resolver: candidateResolver),
                makeInput: { context in
                    try candidateRankingInput(from: context)
                },
                makePatch: { output, _ in
                    var updates: [String: any Sendable] = [
                        ResolutionContextPatchKey.aggregation.rawValue: output,
                        ResolutionContextPatchKey.selectedCandidateIDs.rawValue: output.finalCandidateIDs
                    ]
                    if output.needsClarification {
                        updates[ResolutionContextPatchKey.resolution.rawValue] = HomeCommandResolution.needsClarification(
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
                makePatch: { output, _ in patch(.candidateShard, [ResolutionContextPatchKey.selectedCandidateIDs.rawValue: output.selectedCandidateIDs]) }
            ),
            ContextualHomeAgent(
                agent: CandidateHydrationAgent(registry: registry),
                makeInput: { context in
                    candidateHydrationInput(from: context)
                },
                makePatch: { output, _ in patch(.candidateHydration, [ResolutionContextPatchKey.hydratedCandidates.rawValue: output]) }
            ),
            ContextualHomeAgent(
                agent: CapabilityResolutionAgent(),
                makeInput: { context in
                    try capabilityResolutionInput(from: context)
                },
                makePatch: capabilityResolutionPatch
            ),
            ContextualHomeAgent(
                agent: InstructionComposerAgent(factory: instructionFactory),
                makeInput: finalInput,
                makePatch: { output, _ in patch(.instructionComposer, [ResolutionContextPatchKey.instructionPackage.rawValue: output]) }
            ),
            ContextualHomeAgent(
                agent: DraftGenerationAgent(resolver: draftResolver),
                makeInput: { context in
                    guard let package = context.instructionPackage else {
                        throw AgentContextInputError(agentID: .draftGeneration, message: "Missing instruction package")
                    }
                    return package
                },
                makePatch: { output, _ in patch(.draftGeneration, [ResolutionContextPatchKey.draft.rawValue: output]) }
            ),
            ContextualHomeAgent(
                agent: DraftRepairAgent(resolver: draftResolver),
                makeInput: { context in
                    guard let package = context.instructionPackage else {
                        throw AgentContextInputError(agentID: .draftRepair, message: "Missing instruction package")
                    }
                    return package
                },
                makePatch: { output, _ in patch(.draftRepair, [ResolutionContextPatchKey.draft.rawValue: output.draft]) }
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
                    var updates: [String: any Sendable] = [ResolutionContextPatchKey.resolution.rawValue: output]
                    if case .readyToExecute(let plan) = output {
                        updates[ResolutionContextPatchKey.executionPlan.rawValue] = plan
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
                        : patch(.parameterValidation, [ResolutionContextPatchKey.resolution.rawValue: HomeCommandResolution.needsClarification("Some command values are invalid or missing.")])
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
                        return patch(.confirmationPolicy, [ResolutionContextPatchKey.resolution.rawValue: HomeCommandResolution.requiresConfirmation(draft)])
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
                            ResolutionContextPatchKey.executionPlan.rawValue: output,
                            ResolutionContextPatchKey.resolution.rawValue: HomeCommandResolution.readyToExecute(output)
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
                    return patch(.mockExecution, [ResolutionContextPatchKey.resolution.rawValue: HomeCommandResolution.executed(plan, updatedDevice: output)])
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
                makePatch: { output, _ in patch(.ruleFallback, [ResolutionContextPatchKey.resolverResult.rawValue: output]) }
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
                            ResolutionContextPatchKey.aggregation.rawValue: aggregation,
                            ResolutionContextPatchKey.hydratedCandidates.rawValue: [first.device],
                            ResolutionContextPatchKey.draft.rawValue: first.draft
                        ]
                    )
                }
            ),
            ContextualHomeAgent(
                agent: UnsupportedCommandAgent(reasonBuilder: { $0 }),
                makeInput: { context in
                    if context.operation?.operation == .unsupported {
                        return context.operation?.reason ?? "This command is not supported."
                    }
                    return "This command is not supported."
                },
                makePatch: { output, _ in patch(.unsupportedCommand, [ResolutionContextPatchKey.resolution.rawValue: output]) }
            ),
            ContextualHomeAgent(
                agent: ClarificationAgent(),
                makeInput: { context in context.aggregation?.clarificationQuestion ?? "Which device do you want to control?" },
                makePatch: { output, _ in patch(.clarification, [ResolutionContextPatchKey.resolution.rawValue: output]) }
            ),
            ContextualHomeAgent(
                agent: ResultSummaryAgent(),
                makeInput: { context in context.resolution ?? .unsupported("No resolution produced") },
                makePatch: { _, _ in patch(.resultSummary, [:]) }
            )
        ]

        let modules = Self.agentModules(from: agents)
        let finalRegistry = AgentRegistry(agents: modules.flatMap { $0.makeAgents() })
        registryBox.registry = finalRegistry
        return finalRegistry
    }

    private static func agentModules(from agents: [any AnyHomeAgent]) -> [any AgentModule] {
        let agentsByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        let moduleDefinitions: [(name: String, ids: [AgentID])] = [
            ("operationDetection", [.operationDetection]),
            ("nlu", [.semanticNLU, .slotExtraction, .riskClassification]),
            ("automation", [
                .automationDraft,
                .automationConditionOperandResolution,
                .automationActionResolution,
                .automationValidation,
                .automationResultAssembly
            ]),
            ("smartThings", [.smartThingsCompilation, .smartThingsRuleCreation]),
            ("knowledge", [.capabilityKnowledge, .bixbyKnowledge, .commandExample, .retrievalJudge]),
            ("candidates", [.candidateRetrieval, .candidateRanking, .candidateShard, .candidateHydration, .capabilityResolution]),
            ("draft", [.instructionComposer, .draftGeneration, .draftRepair]),
            ("safety", [.safetyValidation, .parameterValidation, .confirmationPolicy]),
            ("execution", [.executionPlanning, .mockExecution]),
            ("fallback", [.ruleFallback, .bixbyFallback, .unsupportedCommand]),
            ("response", [.clarification, .resultSummary])
        ]

        var assignedIDs = Set<AgentID>()
        var modules: [any AgentModule] = moduleDefinitions.map { definition in
            assignedIDs.formUnion(definition.ids)
            return StaticAgentModule(
                name: definition.name,
                agents: definition.ids.compactMap { agentsByID[$0] }
            )
        }

        let remainingAgents = agents.filter { !assignedIDs.contains($0.id) }
        if !remainingAgents.isEmpty {
            modules.append(StaticAgentModule(name: "unassigned", agents: remainingAgents))
        }
        return modules
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
                ResolutionContextPatchKey.knowledgeSnippets.rawValue: output.snippets,
                ResolutionContextPatchKey.retrievalReports.rawValue: output.reports
            ]
        )
    }

    private static func scopedPatch(
        _ agentID: AgentID,
        scope: ContextScope,
        _ values: [String: any Sendable]
    ) -> ResolutionContextPatch {
        ResolutionContextPatch(
            agentID: agentID,
            scopedUpdates: [
                scope: values.mapValues { AnySendableValue($0) }
            ]
        )
    }

    private static func automationConditionPatch(
        _ output: AutomationConditionResolutionOutput
    ) -> ResolutionContextPatch {
        var scopedUpdates: [ContextScope: [String: AnySendableValue]] = [
            .root: [
                ContextArtifactKeys.automationRuleDraft().name: AnySendableValue(output.ruleDraft),
                AutomationRuntimeContextKeys.conditionOperandResolutionRecords.name: AnySendableValue(output.records)
            ]
        ]

        for record in output.records {
            let scope = ContextScope.condition(record.id)
            scopedUpdates[scope] = [
                AutomationRuntimeContextKeys.conditionOperandResolution(in: scope).name: AnySendableValue(record)
            ]
        }

        return ResolutionContextPatch(
            agentID: .automationConditionOperandResolution,
            scopedUpdates: scopedUpdates
        )
    }

    private static func automationActionPatch(
        _ output: AutomationActionResolutionAggregate,
        _ context: ResolutionContext
    ) -> ResolutionContextPatch {
        var scopedUpdates: [ContextScope: [String: AnySendableValue]] = [
            .root: [
                AutomationRuntimeContextKeys.actionResolutionAggregate.name: AnySendableValue(output),
                ResolutionContextPatchKey.automationResolvedActions.rawValue: AnySendableValue(output.resolvedActions)
            ]
        ]

        for (index, result) in output.results.enumerated() {
            let scope = ContextScope.action("a\(index + 1)")
            var values: [String: AnySendableValue] = [
                "resolution": AnySendableValue(result.resolution)
            ]
            if let draft = result.draft {
                values[ContextArtifactKeys.commandDraft(in: scope).name] = AnySendableValue(draft)
            }
            if let resolvedAction = result.resolvedAction {
                values[ContextArtifactKeys.resolvedAction(in: scope).name] = AnySendableValue(resolvedAction)
            }
            scopedUpdates[scope] = values
        }

        return ResolutionContextPatch(
            agentID: .automationActionResolution,
            scopedUpdates: scopedUpdates
        )
    }

    private static func smartThingsCompilationPatch(
        _ output: SmartThingsCompilationOutput,
        _ context: ResolutionContext
    ) -> ResolutionContextPatch {
        var backendValues: [String: AnySendableValue] = [
            AutomationRuntimeContextKeys.smartThingsCompilation.name: AnySendableValue(output)
        ]
        if let document = output.document {
            backendValues[ContextArtifactKeys.smartThingsRule().name] = AnySendableValue(document)
        }

        return ResolutionContextPatch(
            agentID: .smartThingsCompilation,
            scopedUpdates: [
                .root: [
                    ContextArtifactKeys.automationPlan().name: AnySendableValue(output.plan)
                ],
                .backend("smartthings"): backendValues
            ]
        )
    }

    private static func smartThingsRuleCreationPatch(
        _ output: SmartThingsRuleCreationOutput,
        _ context: ResolutionContext
    ) -> ResolutionContextPatch {
        var backendValues: [String: AnySendableValue] = [
            AutomationRuntimeContextKeys.smartThingsRuleCreation.name: AnySendableValue(output)
        ]
        if let receipt = output.receipt {
            backendValues[ContextArtifactKeys.smartThingsRuleCreation().name] = AnySendableValue(receipt)
        }

        return ResolutionContextPatch(
            agentID: .smartThingsRuleCreation,
            scopedUpdates: [
                .root: [
                    ContextArtifactKeys.automationPlan().name: AnySendableValue(output.plan)
                ],
                .backend("smartthings"): backendValues
            ]
        )
    }

    private static func candidateRetrievalInput<Context: NLUContextFacet & KnowledgeContextFacet>(
        from context: Context
    ) -> CandidateRetrievalInput {
        CandidateRetrievalInput(
            text: context.request.text,
            state: context.resolutionState ?? fallbackState(for: context.request.text),
            memoryHints: context.memoryHints
        )
    }

    private static func candidateRankingInput<Context: NLUContextFacet & CandidateContextFacet & KnowledgeContextFacet>(
        from context: Context
    ) throws -> CandidateRankingInput {
        CandidateRankingInput(
            text: context.request.text,
            state: try state(from: context, agentID: .candidateRanking),
            candidates: context.retrievedCandidates.map(\.compactView),
            memoryHints: context.memoryHints
        )
    }

    private static func candidateHydrationInput<Context: CandidateContextFacet>(
        from context: Context
    ) -> CandidateHydrationInput {
        CandidateHydrationInput(
            candidateIDs: context.aggregation?.finalCandidateIDs ?? context.selectedCandidateIDs
        )
    }

    private static func capabilityResolutionInput<Context: CapabilityContextFacet>(
        from context: Context
    ) throws -> CapabilityResolutionInput {
        CapabilityResolutionInput(
            rawText: context.request.text,
            resolutionState: try state(from: context, agentID: .capabilityResolution),
            hydratedCandidates: context.hydratedCandidates,
            aggregation: context.aggregation ?? HomeCandidateAggregationResult(
                finalCandidateIDs: context.selectedCandidateIDs,
                needsClarification: false,
                confidence: 0
            ),
            knowledgeSnippets: context.knowledgeSnippets
        )
    }

    private static func capabilityResolutionPatch(
        _ output: HomeCapabilityDecision,
        _ context: ResolutionContext
    ) -> ResolutionContextPatch {
        var transition: GraphTransitionRequest?
        if output.confidence < 0.45 {
            transition = .routeToClarification(
                question: "Which capability or command should I use for this device?",
                reason: "Capability resolution confidence \(output.confidence) is below the clarification threshold."
            )
        } else if output.confidence < 0.7, let alternative = output.alternatives.dropFirst().first {
            transition = .retryWithAlternateCapability(
                capability: alternative.capability,
                command: alternative.command,
                reason: "Capability resolution confidence \(output.confidence) is medium and an alternative is available."
            )
        }
        return ResolutionContextPatch(
            agentID: .capabilityResolution,
            updates: [ResolutionContextPatchKey.capabilityDecision.rawValue: AnySendableValue(output)],
            transitionRequest: transition
        )
    }

    private static func state<Context: NLUContextFacet>(from context: Context, agentID: AgentID) throws -> HomeResolutionState {
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
            ),
            capabilityDecision: context.capabilityDecision
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
