import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite
struct MASArchitectureImprovementTests {
    @Test
    func typedArtifactHelpersReadAndWriteScopedValues() throws {
        var context = ResolutionContext(
            request: CommandRequest(text: "turn on ac every day", executeLowRiskCommands: false)
        )
        let draft = HomeAutomationRuleDraft(
            name: "Daily AC",
            trigger: .schedule(
                HomeAutomationScheduleTrigger(
                    repeatRule: .everyDay,
                    timeOfDay: HomeAutomationTimeOfDay(hour: 7, minute: 0),
                    timezoneIdentifier: nil
                )
            ),
            condition: nil,
            actionDescriptions: ["Turn on AC"],
            confidence: 1
        )

        context.setArtifact(draft, for: ContextArtifactKeys.automationRuleDraft())

        #expect(context.artifact(for: ContextArtifactKeys.automationRuleDraft()) == draft)
        #expect(try context.requireArtifact(for: ContextArtifactKeys.automationRuleDraft()) == draft)
    }

    @Test
    func typedArtifactMismatchReportsExpectedAndActualTypes() {
        var context = ResolutionContext(
            request: CommandRequest(text: "turn on ac every day", executeLowRiskCommands: false)
        )
        context.mergeScopedValues(
            [ContextArtifactKeys.automationRuleDraft().name: AnySendableValue("not a draft")],
            in: .root
        )

        do {
            _ = try context.requireArtifact(for: ContextArtifactKeys.automationRuleDraft())
            Issue.record("Expected typed artifact mismatch.")
        } catch let error as ContextArtifactError {
            #expect(error.localizedDescription.contains("automationDraft"))
            #expect(error.localizedDescription.contains("String"))
            #expect(error.localizedDescription.contains("HomeAutomationRuleDraft"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func graphValidatorDetectsTypedArtifactMismatch() {
        let stringArtifact = ContextArtifactKey<String>("automationDraft", scope: .root)
        let registry = AgentRegistry(
            agents: [
                ContractGraphAgent(
                    id: .operationDetection,
                    producesArtifacts: [.required(stringArtifact)],
                    produces: []
                ),
                ContractGraphAgent(
                    id: .automationResultAssembly,
                    consumesArtifacts: [.required(ContextArtifactKeys.automationRuleDraft())],
                    produces: [ResolutionContextPatchKey.resolverResult.rawValue]
                )
            ]
        )
        let graph = OrchestrationGraph(
            id: "typed-artifact-mismatch",
            goal: .automationCreation,
            nodes: [
                GraphNode(id: AgentID.operationDetection.rawValue, requirement: .byID(.operationDetection)),
                GraphNode(id: AgentID.automationResultAssembly.rawValue, requirement: .byID(.automationResultAssembly))
            ],
            edges: [
                GraphEdge(from: AgentID.operationDetection.rawValue, to: AgentID.automationResultAssembly.rawValue)
            ],
            entryNodeIDs: [AgentID.operationDetection.rawValue]
        )

        let errors = GraphValidator().validate(graph, registry: registry)

        #expect(errors.contains {
            if case let .manifestArtifactTypeMismatch(graphID, nodeID, key, scope, expectedType, actualType) = $0 {
                return graphID == "typed-artifact-mismatch" &&
                    nodeID == AgentID.automationResultAssembly.rawValue &&
                    key == "automationDraft" &&
                    scope == ContextScope.root.description &&
                    expectedType.contains("HomeAutomationRuleDraft") &&
                    actualType.contains("String")
            }
            return false
        })
    }

    @Test
    func graphTransitionRoutesToClarification() async {
        let contextStore = ResolutionContextStore(
            request: CommandRequest(text: "turn on the thing", executeLowRiskCommands: false)
        )
        let graph = OrchestrationGraph(
            id: "transition-clarification",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(id: AgentID.capabilityResolution.rawValue, requirement: .byID(.capabilityResolution))
            ],
            edges: [],
            entryNodeIDs: [AgentID.capabilityResolution.rawValue]
        )

        let result = await GraphScheduler().execute(
            graph,
            registry: AgentRegistry(agents: [
                TransitionGraphAgent(
                    id: .capabilityResolution,
                    transition: .routeToClarification(
                        question: "Which capability should I use?",
                        reason: "test low confidence"
                    )
                )
            ]),
            contextStore: contextStore,
            eventBus: AgentEventBus(),
            policy: OrchestratorPolicyEngine(isModelAvailable: { true }),
            circuitBreakers: CircuitBreakerRegistry(),
            runID: UUID()
        )

        let context = await contextStore.snapshot()
        #expect(result.metrics.transitionDecisions.contains { $0.contains("routeToClarification:approved") })
        guard case .needsClarification("Which capability should I use?") = context.resolution else {
            Issue.record("Expected clarification resolution.")
            return
        }
    }

    @Test
    func graphTransitionRejectsUnsafeSafetyGateRoute() async {
        let contextStore = ResolutionContextStore(
            request: CommandRequest(text: "unlock front door", executeLowRiskCommands: false)
        )
        let graph = OrchestrationGraph(
            id: "transition-rejected",
            goal: .executeDeviceCommand,
            nodes: [
                GraphNode(
                    id: AgentID.safetyValidation.rawValue,
                    requirement: .byID(.safetyValidation),
                    executionPolicy: .safetyGate
                )
            ],
            edges: [],
            entryNodeIDs: [AgentID.safetyValidation.rawValue]
        )

        let result = await GraphScheduler().execute(
            graph,
            registry: AgentRegistry(agents: [
                TransitionGraphAgent(
                    id: .safetyValidation,
                    transition: .routeToUnsupported(reason: "unsafe test")
                )
            ]),
            contextStore: contextStore,
            eventBus: AgentEventBus(),
            policy: OrchestratorPolicyEngine(isModelAvailable: { true }),
            circuitBreakers: CircuitBreakerRegistry(),
            runID: UUID()
        )

        #expect(result.metrics.transitionDecisions.contains { $0.contains("routeToUnsupported") && $0.contains("rejected") })
        guard case .terminalFailure = result.exit else {
            Issue.record("Expected rejected transition to fail closed.")
            return
        }
    }

    @Test
    func schedulerStartsNewlyReadyNodeBeforeUnrelatedParallelNodeFinishes() async throws {
        let recorder = PipeliningRecorder()
        let contextStore = ResolutionContextStore(
            request: CommandRequest(text: "pipeline test", executeLowRiskCommands: false)
        )
        let graph = OrchestrationGraph(
            id: "pipelined-readiness",
            goal: .rootRouting,
            nodes: [
                GraphNode(id: AgentID.language.rawValue, requirement: .byID(.language)),
                GraphNode(id: AgentID.domain.rawValue, requirement: .byID(.domain)),
                GraphNode(id: AgentID.intentFamily.rawValue, requirement: .byID(.intentFamily))
            ],
            edges: [
                GraphEdge(from: AgentID.domain.rawValue, to: AgentID.intentFamily.rawValue)
            ],
            entryNodeIDs: [AgentID.language.rawValue, AgentID.domain.rawValue]
        )

        _ = await GraphScheduler().execute(
            graph,
            registry: AgentRegistry(agents: [
                TimedGraphAgent(
                    id: .language,
                    delayNanoseconds: 5_000_000_000,
                    recorder: recorder,
                    endAfterAgentStarts: .intentFamily
                ),
                TimedGraphAgent(id: .domain, delayNanoseconds: 10_000_000, recorder: recorder),
                TimedGraphAgent(id: .intentFamily, delayNanoseconds: 10_000_000, recorder: recorder)
            ]),
            contextStore: contextStore,
            eventBus: AgentEventBus(),
            policy: OrchestratorPolicyEngine(isModelAvailable: { true }),
            circuitBreakers: CircuitBreakerRegistry(),
            runID: UUID()
        )

        let intentStarted = try #require(await recorder.startedAt(.intentFamily))
        let languageEnded = try #require(await recorder.endedAt(.language))
        #expect(intentStarted < languageEnded)
    }

    @Test
    func batchPatchConflictDetectionRejectsDifferentSameKeyValues() async {
        let patches = [
            ResolutionContextPatch(
                agentID: .language,
                updates: [ResolutionContextPatchKey.language.rawValue: AnySendableValue("en")]
            ),
            ResolutionContextPatch(
                agentID: .domain,
                updates: [ResolutionContextPatchKey.language.rawValue: AnySendableValue("fr")]
            )
        ]

        do {
            try ResolutionContextStore.validateNoConflictingWrites(patches)
            Issue.record("Expected a conflict for divergent same-key writes.")
        } catch let error as ResolutionContextPatchConflict {
            #expect(error.localizedDescription.contains(ResolutionContextPatchKey.language.rawValue))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private struct ContractGraphAgent: AnyHomeAgent {
    let id: AgentID
    let capabilities: Set<AgentCapability> = []
    let manifest: AgentManifest
    let timeoutNanoseconds: UInt64 = 1_000_000_000

    init(
        id: AgentID,
        consumesArtifacts: Set<ContextArtifactContract> = [],
        producesArtifacts: Set<ContextArtifactContract> = [],
        produces: Set<String>
    ) {
        self.id = id
        self.manifest = AgentManifest(
            id: id,
            capabilities: [],
            supportedOperations: [.automationCreation, .executeDeviceCommand],
            produces: produces,
            consumedArtifacts: consumesArtifacts,
            producedArtifacts: producesArtifacts
        )
    }

    func run(context: ResolutionContext) async -> AgentRunResult {
        .success(ResolutionContextPatch(agentID: id))
    }
}

private struct TransitionGraphAgent: AnyHomeAgent {
    let id: AgentID
    let capabilities: Set<AgentCapability> = []
    let transition: GraphTransitionRequest
    let timeoutNanoseconds: UInt64 = 1_000_000_000

    var manifest: AgentManifest {
        let defaults = AgentManifestDefaults.manifest(id: id, capabilities: capabilities)
        return AgentManifest(
            id: id,
            capabilities: capabilities,
            supportedOperations: [.executeDeviceCommand],
            consumes: [],
            produces: [ResolutionContextPatchKey.resolution.rawValue],
            safetyRole: defaults.safetyRole,
            retryPolicy: defaults.retryPolicy,
            priority: defaults.priority
        )
    }

    func run(context: ResolutionContext) async -> AgentRunResult {
        .success(
            ResolutionContextPatch(
                agentID: id,
                transitionRequest: transition
            )
        )
    }
}

private actor PipeliningRecorder {
    private var starts: [AgentID: Date] = [:]
    private var ends: [AgentID: Date] = [:]
    private var startWaiters: [AgentID: [CheckedContinuation<Void, Never>]] = [:]

    func markStarted(_ id: AgentID) {
        starts[id] = Date()
        let waiters = startWaiters.removeValue(forKey: id) ?? []
        for waiter in waiters {
            waiter.resume()
        }
    }

    func markEnded(_ id: AgentID) {
        ends[id] = Date()
    }

    func startedAt(_ id: AgentID) -> Date? {
        starts[id]
    }

    func endedAt(_ id: AgentID) -> Date? {
        ends[id]
    }

    func waitForStart(_ id: AgentID) async {
        if starts[id] != nil { return }
        await withCheckedContinuation { continuation in
            startWaiters[id, default: []].append(continuation)
        }
    }
}

private struct TimedGraphAgent: AnyHomeAgent {
    let id: AgentID
    let delayNanoseconds: UInt64
    let recorder: PipeliningRecorder
    var endAfterAgentStarts: AgentID?
    let capabilities: Set<AgentCapability> = []
    let timeoutNanoseconds: UInt64 = 10_000_000_000

    var manifest: AgentManifest {
        AgentManifest(
            id: id,
            capabilities: capabilities,
            supportedOperations: [.executeDeviceCommand],
            produces: [ResolutionContextPatchKey.operation.rawValue]
        )
    }

    func run(context: ResolutionContext) async -> AgentRunResult {
        await recorder.markStarted(id)
        if let endAfterAgentStarts {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await recorder.waitForStart(endAfterAgentStarts)
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: delayNanoseconds)
                }
                _ = await group.next()
                group.cancelAll()
            }
        } else {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        await recorder.markEnded(id)
        return .success(ResolutionContextPatch(agentID: id))
    }
}
