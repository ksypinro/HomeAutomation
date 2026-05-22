import Foundation
import FoundationModels
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationRAG
import OSLog

/// A factory for assembling the default set of home automation agents.
/// 
/// This factory configures each agent with its necessary workers, dependencies,
/// and contextual mappers, yielding a ready-to-use `AgentRegistry`.
public enum DefaultAgentRegistryFactory {
    public static func make(
        registry: any DeviceRegistryProtocol = MockHomeDeviceRegistry(),
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
                agent: AutomationComponentSegmentationAgent(
                    worker: AutomationComponentSegmentationWorkerSession(
                        foundationModelAvailability: foundationModelAvailability
                    )
                ),
                makeInput: { $0.request.text },
                makePatch: { output, _ in automationComponentPlanPatch(output) }
            ),
            ContextualHomeAgent(
                agent: AutomationComponentFanOutAgent(
                    resolveComponents: { componentPlan, context in
                        guard let agentRegistry = registryBox.registry else {
                            return AutomationResolvedComponentSet(
                                trigger: nil,
                                actionResults: [],
                                conditionResults: [],
                                conditionTree: componentPlan.conditionTree,
                                unsupportedFragments: ["Agent registry unavailable"]
                            )
                        }
                        let actionResolver = AutomationActionResolver(
                            registry: agentRegistry,
                            graphPlanner: GraphPlanner(
                                policy: OrchestratorPolicyEngine(isModelAvailable: foundationModelAvailability)
                            ),
                            policy: OrchestratorPolicyEngine(isModelAvailable: foundationModelAvailability)
                        )
                        let runner = AutomationComponentFanOutRunner(
                            triggerAgent: AutomationTriggerResolutionAgent(
                                worker: AutomationTriggerResolutionWorkerSession(
                                    foundationModelAvailability: foundationModelAvailability
                                )
                            ),
                            conditionAgent: AutomationConditionClauseResolutionAgent(
                                worker: AutomationConditionClauseResolutionWorkerSession(
                                    foundationModelAvailability: foundationModelAvailability
                                )
                            ),
                            actionResolver: actionResolver,
                            registry: registry
                        )
                        return await runner.resolve(plan: componentPlan, context: context)
                    }
                ),
                makeInput: { context in
                    try context.requireArtifact(for: ContextArtifactKeys.automationComponentPlan())
                },
                makePatch: { output, _ in automationResolvedComponentsPatch(output) }
            ),
            ContextualHomeAgent(
                agent: AutomationDraftAssemblyAgent(),
                makeInput: { context in
                    AutomationDraftAssemblyInput(
                        componentPlan: try context.requireArtifact(for: ContextArtifactKeys.automationComponentPlan()),
                        resolvedComponents: try context.requireArtifact(for: ContextArtifactKeys.automationResolvedComponents())
                    )
                },
                makePatch: { output, _ in automationDraftAssemblyPatch(output) }
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
}
