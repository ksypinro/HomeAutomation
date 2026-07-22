import Foundation
import FoundationModels
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("VerifierLoopOrchestrator")
struct VerifierLoopTests {

    private func makeOrchestrator(
        verifyBehavior: @escaping @Sendable (DraftEnvelope, VerifierPrompt) async throws -> DraftVerdict,
        specialistBehavior: @escaping @Sendable (RepairPlanner.RepairStep, DraftEnvelope) async -> RepairResult? = { _, _ in nil },
        policy: VerifierLoopPolicy = VerifierLoopPolicy()
    ) -> VerifierLoopOrchestrator {
        let registry = MockHomeDeviceRegistry()
        let pipeline = DeterministicDraftPipeline(registry: registry)

        let verifier = DraftVerifierWorkerSession(
            verify: verifyBehavior,
            foundationModelAvailability: { false }
        )
        let promptBuilder = VerifierPromptBuilder()
        let planner = RepairPlanner()
        let specialists = RepairSpecialistRegistry(execute: specialistBehavior)

        return VerifierLoopOrchestrator(
            pipeline: pipeline,
            verifier: verifier,
            promptBuilder: promptBuilder,
            planner: planner,
            specialists: specialists,
            policy: policy
        )
    }

    private func makeRequest(_ text: String = "turn on the light") -> CommandRequest {
        CommandRequest(text: text, executeLowRiskCommands: true)
    }

    @Test("accept on first iteration returns accepted exit")
    func acceptOnFirst() async {
        let orchestrator = makeOrchestrator(
            verifyBehavior: { _, _ in
                DraftVerdict(accepted: true, disputes: [], needsClarification: false)
            }
        )

        let output = await orchestrator.run(
            request: makeRequest(),
            operationHint: nil,
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        guard case .accepted(_, let iterations) = output.exit else {
            Issue.record("Expected .accepted, got \(output.exit)")
            return
        }
        #expect(iterations == 1)
        #expect(output.metrics.verifierCallCount == 1)
        #expect(output.metrics.repairCallCount == 0)
        #expect(output.metrics.acceptedOnIteration == 1)
    }

    @Test("precedence-ambiguous automation escalates before any verifier call")
    func preflightEscalatesPrecedenceAmbiguous() async {
        let orchestrator = makeOrchestrator(
            verifyBehavior: { _, _ in
                // Would accept if ever called — so a nonzero verifierCallCount proves the
                // preflight gate did not short-circuit.
                DraftVerdict(accepted: true, disputes: [], needsClarification: false)
            }
        )

        let text = "turn on the bedroom AC and turn off the living room blinds every day at 7 PM if the living room ceiling light is on and the bedroom AC is off or the living room TV is off"
        let output = await orchestrator.run(
            request: makeRequest(text),
            operationHint: HomeOperationDetectionResult(
                domain: .homeAutomation,
                operation: .automationCreation,
                confidence: 0.9,
                reason: "test"
            ),
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        guard case .escalated(_, let reason) = output.exit else {
            Issue.record("Expected .escalated, got \(output.exit)")
            return
        }
        #expect(reason == .preflightUnsupported)
        #expect(output.metrics.verifierCallCount == 0)
        #expect(output.metrics.repairCallCount == 0)
        #expect(output.metrics.preVerifyRepairCount == 0)
    }

    @Test("accepted verdict with disputes is normalized into repair before acceptance")
    func acceptedWithDisputesRequiresRepair() async {
        let callCount = CallCounter()

        let orchestrator = makeOrchestrator(
            verifyBehavior: { _, _ in
                let count = await callCount.increment()
                if count == 1 {
                    return DraftVerdict(
                        accepted: true,
                        disputes: [
                            DraftDispute(
                                fieldID: "command.capability",
                                kind: .wrongValue,
                                evidence: "accepted verdict still carried a dispute"
                            )
                        ],
                        needsClarification: false
                    )
                }
                return DraftVerdict(accepted: true, disputes: [], needsClarification: false)
            },
            specialistBehavior: { _, _ in
                .capability(
                    fieldID: FieldID(rawValue: "command.capability"),
                    HomeCapabilityDecision(
                        selectedCapability: "switch",
                        selectedCommand: "on",
                        targetDeviceID: nil,
                        alternatives: [],
                        evidence: [],
                        confidence: 0.9
                    )
                )
            }
        )

        let output = await orchestrator.run(
            request: makeRequest(),
            operationHint: nil,
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        guard case .accepted(_, let iterations) = output.exit else {
            Issue.record("Expected .accepted after repair, got \(output.exit)")
            return
        }
        #expect(iterations == 2)
        #expect(output.metrics.repairCallCount == 1)
        #expect(output.metrics.disputedFieldIDsPerIteration == [["command.capability"]])
    }

    @Test("accepted verdict with clarification exits as clarification")
    func acceptedWithClarificationIsNotAccepted() async {
        let orchestrator = makeOrchestrator(
            verifyBehavior: { _, _ in
                DraftVerdict(accepted: true, disputes: [], needsClarification: true)
            }
        )

        let output = await orchestrator.run(
            request: makeRequest(),
            operationHint: nil,
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        guard case .clarification = output.exit else {
            Issue.record("Expected clarification, got \(output.exit)")
            return
        }
        #expect(output.metrics.acceptedOnIteration == nil)
    }

    @Test("risk understatement is converted into a risk repair before acceptance")
    func riskUnderstatementRequiresRiskRepair() async {
        let callCount = CallCounter()

        let orchestrator = makeOrchestrator(
            verifyBehavior: { _, _ in
                let count = await callCount.increment()
                if count == 1 {
                    return DraftVerdict(
                        accepted: true,
                        disputes: [],
                        needsClarification: false,
                        riskUnderstated: true
                    )
                }
                return DraftVerdict(accepted: true, disputes: [], needsClarification: false)
            },
            specialistBehavior: { step, _ in
                guard step.specialist == .riskRaise else { return nil }
                return .riskRaise(
                    HomeRiskClassificationResult(
                        riskLevel: .high,
                        requiresConfirmation: true,
                        reason: "test risk raise",
                        confidence: 0.9
                    )
                )
            }
        )

        let output = await orchestrator.run(
            request: makeRequest("unlock the front door"),
            operationHint: nil,
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        guard case .accepted(let envelope, let iterations) = output.exit else {
            Issue.record("Expected .accepted after risk repair, got \(output.exit)")
            return
        }
        #expect(iterations == 2)
        #expect(output.metrics.repairCallCount == 1)
        #expect(output.metrics.disputedFieldIDsPerIteration == [[FieldID.riskLevel.rawValue]])
        #expect(envelope.risk.level == .high)
    }

    @Test("one dispute → repair → accept on second iteration")
    func oneDisputeRepairAccept() async {
        let callCount = CallCounter()

        let orchestrator = makeOrchestrator(
            verifyBehavior: { _, _ in
                let count = await callCount.increment()
                if count == 1 {
                    return DraftVerdict(
                        accepted: false,
                        disputes: [DraftDispute(fieldID: "command.capability", kind: .wrongValue, evidence: "test")],
                        needsClarification: false
                    )
                }
                return DraftVerdict(accepted: true, disputes: [], needsClarification: false)
            },
            specialistBehavior: { step, envelope in
                .capability(fieldID: FieldID(rawValue: "command.capability"), HomeCapabilityDecision(selectedCapability: "switch", selectedCommand: "on", targetDeviceID: nil, alternatives: [], evidence: [], confidence: 0.9))
            }
        )

        let output = await orchestrator.run(
            request: makeRequest(),
            operationHint: nil,
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        guard case .accepted(_, let iterations) = output.exit else {
            Issue.record("Expected .accepted, got \(output.exit)")
            return
        }
        #expect(iterations == 2)
        #expect(output.metrics.verifierCallCount == 2)
        #expect(output.metrics.repairCallCount >= 1)
        #expect(output.metrics.acceptedOnIteration == 2)
    }

    @Test("non-shrinking disputes escalate with noProgress")
    func nonShrinkingDisputes() async {
        let orchestrator = makeOrchestrator(
            verifyBehavior: { _, _ in
                DraftVerdict(
                    accepted: false,
                    disputes: [
                        DraftDispute(fieldID: "command.capability", kind: .wrongValue, evidence: "test"),
                        DraftDispute(fieldID: "command.commandName", kind: .wrongValue, evidence: "test"),
                    ],
                    needsClarification: false
                )
            },
            specialistBehavior: { step, envelope in
                .capability(fieldID: FieldID(rawValue: "command.capability"), HomeCapabilityDecision(selectedCapability: "switch", selectedCommand: "on", targetDeviceID: nil, alternatives: [], evidence: [], confidence: 0.9))
            }
        )

        let output = await orchestrator.run(
            request: makeRequest(),
            operationHint: nil,
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        guard case .escalated(_, let reason) = output.exit else {
            Issue.record("Expected .escalated, got \(output.exit)")
            return
        }
        #expect(reason == .noProgress)
        #expect(output.metrics.escalationReason == "noProgress")
    }

    @Test("same field latched across iterations causes repairLatch escalation")
    func sameFieldLatch() async {
        let callCount = CallCounter()

        let orchestrator = makeOrchestrator(
            verifyBehavior: { _, _ in
                let count = await callCount.increment()
                if count == 1 {
                    return DraftVerdict(
                        accepted: false,
                        disputes: [
                            DraftDispute(fieldID: "command.capability", kind: .wrongValue, evidence: "test"),
                            DraftDispute(fieldID: "command.commandName", kind: .wrongValue, evidence: "test"),
                        ],
                        needsClarification: false
                    )
                }
                return DraftVerdict(
                    accepted: false,
                    disputes: [DraftDispute(fieldID: "command.capability", kind: .wrongValue, evidence: "still wrong")],
                    needsClarification: false
                )
            },
            specialistBehavior: { step, envelope in
                .capability(fieldID: FieldID(rawValue: "command.capability"), HomeCapabilityDecision(selectedCapability: "switch", selectedCommand: "on", targetDeviceID: nil, alternatives: [], evidence: [], confidence: 0.9))
            }
        )

        let output = await orchestrator.run(
            request: makeRequest(),
            operationHint: nil,
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        guard case .escalated(_, let reason) = output.exit else {
            Issue.record("Expected .escalated, got \(output.exit)")
            return
        }
        #expect(reason == .repairLatch || reason == .noProgress)
    }

    @Test("iteration cap reached escalates with iterationCap")
    func iterationCap() async {
        let callCount = CallCounter()
        let disputeFields = ["operation", "risk.level", "command.targetDeviceID"]

        let orchestrator = makeOrchestrator(
            verifyBehavior: { _, _ in
                let count = await callCount.increment()
                let field = disputeFields[min(count - 1, disputeFields.count - 1)]
                return DraftVerdict(
                    accepted: false,
                    disputes: [DraftDispute(fieldID: field, kind: .wrongValue, evidence: "test")],
                    needsClarification: false
                )
            },
            specialistBehavior: { step, _ in
                switch step.specialist {
                case .operationDetection:
                    return .operation(HomeOperationDetectionResult(domain: .homeAutomation, operation: .executeDeviceCommand, confidence: 0.9, reason: "repair"))
                case .riskRaise:
                    return .riskRaise(HomeRiskClassificationResult(riskLevel: .medium, requiresConfirmation: false, reason: "repair", confidence: 0.9))
                case .target:
                    return .target(fieldID: FieldID(rawValue: "command.targetDeviceID"), ActionTargetResult(selectedDeviceID: "dev1", candidateTable: [], confidence: 0.9, isAmbiguous: false))
                default:
                    return nil
                }
            },
            policy: VerifierLoopPolicy(
                maxIterations: 2,
                requireStrictProgress: false
            )
        )

        let output = await orchestrator.run(
            request: makeRequest(),
            operationHint: nil,
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        guard case .escalated(_, let reason) = output.exit else {
            Issue.record("Expected .escalated, got \(output.exit)")
            return
        }
        #expect(reason == .iterationCap)
        #expect(output.metrics.iterations == 2)
        #expect(output.metrics.escalationReason == "iterationCap")
    }

    @Test("clarification exit when verifier sets needsClarification with no disputes")
    func clarificationExit() async {
        let orchestrator = makeOrchestrator(
            verifyBehavior: { _, _ in
                DraftVerdict(accepted: false, disputes: [], needsClarification: true)
            }
        )

        let output = await orchestrator.run(
            request: makeRequest(),
            operationHint: nil,
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        guard case .clarification(_, let question, let iterations) = output.exit else {
            Issue.record("Expected .clarification, got \(output.exit)")
            return
        }
        #expect(iterations == 1)
        #expect(!question.isEmpty)
    }

    @Test("verifier unavailable escalates immediately")
    func verifierUnavailable() async {
        let orchestrator = makeOrchestrator(
            verifyBehavior: { _, _ in
                throw VerifierUnavailable()
            }
        )

        let output = await orchestrator.run(
            request: makeRequest(),
            operationHint: nil,
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        guard case .escalated(_, let reason) = output.exit else {
            Issue.record("Expected .escalated, got \(output.exit)")
            return
        }
        #expect(reason == .verifierUnavailable)
        #expect(output.metrics.verifierCallCount == 0)
    }

    @Test("metrics track per-iteration disputed field IDs")
    func metricsTrackDisputedFields() async {
        let callCount = CallCounter()

        let orchestrator = makeOrchestrator(
            verifyBehavior: { _, _ in
                let count = await callCount.increment()
                if count == 1 {
                    return DraftVerdict(
                        accepted: false,
                        disputes: [DraftDispute(fieldID: "command.capability", kind: .wrongValue, evidence: "test")],
                        needsClarification: false
                    )
                }
                return DraftVerdict(accepted: true, disputes: [], needsClarification: false)
            },
            specialistBehavior: { step, envelope in
                .capability(fieldID: FieldID(rawValue: "command.capability"), HomeCapabilityDecision(selectedCapability: "switch", selectedCommand: "on", targetDeviceID: nil, alternatives: [], evidence: [], confidence: 0.9))
            }
        )

        let output = await orchestrator.run(
            request: makeRequest(),
            operationHint: nil,
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        #expect(output.metrics.disputedFieldIDsPerIteration.count == 1)
        #expect(output.metrics.disputedFieldIDsPerIteration.first?.contains("command.capability") == true)
    }

    @Test("LoopRunMetrics is Codable round-trip")
    func metricsRoundTrip() throws {
        let metrics = LoopRunMetrics(
            iterations: 2,
            acceptedOnIteration: 2,
            verifierCallCount: 2,
            repairCallCount: 1,
            disputedFieldIDsPerIteration: [["command.capability"]],
            escalationReason: nil,
            preVerifyRepairCount: 0
        )

        let data = try JSONEncoder().encode(metrics)
        let decoded = try JSONDecoder().decode(LoopRunMetrics.self, from: data)

        #expect(decoded.iterations == 2)
        #expect(decoded.acceptedOnIteration == 2)
        #expect(decoded.verifierCallCount == 2)
        #expect(decoded.repairCallCount == 1)
    }

    @Test("RepairSpecialistRegistry returns nil for unimplemented specialists")
    func registryReturnsNilForUnimplemented() async {
        let registry = RepairSpecialistRegistry(execute: { _, _ in nil })
        let step = RepairPlanner.RepairStep(
            specialist: .capability,
            fieldIDs: [FieldID(rawValue: "command.capability")],
            disputes: []
        )
        let envelope = DraftEnvelope(
            userText: "test",
            operation: .executeDeviceCommand,
            operationConfidence: 1.0,
            risk: RiskSection(level: .low, floorReason: "test"),
            provenance: [:],
            fieldConfidence: [:]
        )
        let result = await registry.execute(step, envelope)
        #expect(result == nil)
    }

    @Test("VerifierLoopPolicy has sensible defaults")
    func policyDefaults() {
        let policy = VerifierLoopPolicy()
        #expect(policy.maxIterations == 3)
        #expect(policy.maxRepairCallsPerIteration == 3)
        #expect(policy.requireStrictProgress == true)
        #expect(policy.escalation == .legacyGraph)
    }

    @Test("LoopResultBridge bridges accepted exit to resolver result")
    func bridgeAcceptedExit() {
        let envelope = DraftEnvelope(
            userText: "turn on the light",
            operation: .executeDeviceCommand,
            operationConfidence: 1.0,
            command: CommandDraftSection(
                targetDeviceID: "dev1",
                capability: "switch",
                commandName: "on",
                parameters: [],
                room: nil
            ),
            risk: RiskSection(level: .low, floorReason: "test"),
            provenance: [:],
            fieldConfidence: [:]
        )

        let exit = LoopExit.accepted(envelope: envelope, iterations: 1)
        let result = LoopResultBridge.bridgeToResult(exit: exit, operationHint: nil)

        #expect(result.draft != nil)
    }

    @Test("LoopResultBridge bridges clarification exit with question")
    func bridgeClarificationExit() {
        let envelope = DraftEnvelope(
            userText: "turn on the light",
            operation: .executeDeviceCommand,
            operationConfidence: 1.0,
            risk: RiskSection(level: .low, floorReason: "test"),
            clarification: ClarificationSection(
                question: "Which light?",
                ambiguousFieldIDs: [.command(.targetDeviceID)]
            ),
            provenance: [:],
            fieldConfidence: [:]
        )

        let exit = LoopExit.clarification(envelope: envelope, question: "Which light?", iterations: 1)
        let result = LoopResultBridge.bridgeToResult(exit: exit, operationHint: nil)

        if case .needsClarification(let question) = result.resolution {
            #expect(question == "Which light?")
        } else {
            Issue.record("Expected needsClarification resolution")
        }
    }

    @Test("LoopResultBridge bridges accepted schedule automation to automationDrafted with JSON")
    func bridgeAcceptedAutomationExit() {
        let action = ActionDraft(
            rawText: "turn on the bedroom lamp",
            order: 0,
            command: CommandDraftSection(
                targetDeviceID: "bedroom_lamp",
                candidateTable: [
                    CompactCandidate(id: "bedroom_lamp", name: "Bedroom Lamp", room: "bedroom", deviceType: "light"),
                ],
                capability: "switch",
                commandName: "on",
                room: "bedroom"
            )
        )
        let envelope = DraftEnvelope(
            userText: "turn on the bedroom lamp every day at 7 PM",
            operation: .automationCreation,
            operationConfidence: 0.95,
            automation: AutomationDraftSection(
                trigger: TriggerDraft(type: .schedule, time: HomeAutomationTimeOfDay(hour: 19, minute: 0), repeatRule: .everyDay, confidence: 0.9),
                actions: [action]
            ),
            risk: RiskSection(level: .low, floorReason: "safe")
        )

        let exit = LoopExit.accepted(envelope: envelope, iterations: 1)
        let result = LoopResultBridge.bridgeToResult(exit: exit, operationHint: nil)

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.smartThingsRuleJSON != nil)
        #expect(!plan.resolvedActions.isEmpty)
    }
}

private actor CallCounter {
    private var count = 0

    func increment() -> Int {
        count += 1
        return count
    }
}
