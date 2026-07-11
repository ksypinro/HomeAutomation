import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

/// H6 — the automation repair specialists (`.trigger`, `.conditionClause`,
/// `.segmentation`) wired in `RepairSpecialistRegistry`. All tests run with the
/// foundation model disabled, so they exercise the deterministic seams only.
@Suite("AutomationRepairSpecialists")
struct AutomationRepairSpecialistTests {

    private func makeRegistry(
        registry: any DeviceRegistryProtocol,
        segmentationWorker: AutomationComponentSegmentationWorkerSession? =
            AutomationComponentSegmentationWorkerSession(foundationModelAvailability: { false })
    ) -> RepairSpecialistRegistry {
        let conditionWorker = AutomationConditionClauseResolutionWorkerSession(
            foundationModelAvailability: { false }
        )
        return RepairSpecialistRegistry(
            fragmentNLU: FragmentNLUWorkerSession(foundationModelAvailability: { false }),
            targetResolver: ActionTargetResolver(registry: registry),
            riskAssessor: AutomationRiskAssessor(),
            capabilityWorker: CapabilityResolutionWorker(foundationModelAvailability: { false }),
            triggerWorker: AutomationTriggerResolutionWorkerSession(foundationModelAvailability: { false }),
            conditionClauseWorker: conditionWorker,
            batchedConditionResolver: BatchedConditionClauseResolver(
                singleResolver: conditionWorker,
                foundationModelAvailability: { false }
            ),
            segmentationWorker: segmentationWorker,
            deviceRegistry: registry,
            operationDetection: { _ in nil }
        )
    }

    // MARK: - .trigger

    @Test("trigger dispute repairs a device trigger into a compilable condition")
    func triggerDisputeRepairsDeviceTrigger() async {
        let registry = MockHomeDeviceRegistry()
        let envelope = await DeterministicDraftPipeline(registry: registry)
            .makeAutomationEnvelope(text: "When the entry contact sensor opens, turn on the porch light")
        let specialists = makeRegistry(registry: registry)

        let step = RepairPlanner.RepairStep(
            specialist: .trigger,
            fieldIDs: [.triggerType],
            disputes: [DraftDispute(fieldID: "automation.trigger.type", kind: .wrongValue, evidence: "test")]
        )

        guard case .trigger(let output)? = await specialists.execute(step, envelope) else {
            Issue.record("Expected .trigger repair result")
            return
        }
        guard case .device(let deviceTrigger)? = output.trigger,
              case .comparison(let comparison) = deviceTrigger.condition,
              case .deviceAttribute(_, let deviceID, _, _) = comparison.left else {
            Issue.record("Expected a resolved device-trigger condition")
            return
        }
        #expect(deviceID == "entry_contact_sensor")

        // The repaired trigger, merged back, compiles.
        let merged = EnvelopeMerger.apply(.trigger(output), to: envelope, iteration: 1)
        let plan = StructuralDraftBuilder.automationCreationPlan(from: merged)
        #expect(plan.smartThingsRuleJSON != nil)
    }

    // MARK: - .conditionClause

    @Test("single condition dispute repairs the disputed leaf")
    func conditionDisputeRepairsLeaf() async {
        let registry = MockHomeDeviceRegistry()
        let envelope = await DeterministicDraftPipeline(registry: registry)
            .makeAutomationEnvelope(
                text: "turn on bedroom AC every day at 7 AM if the entry contact sensor is closed"
            )
        #expect(envelope.automation?.conditionLeaves.count == 1)
        let specialists = makeRegistry(registry: registry)

        let step = RepairPlanner.RepairStep(
            specialist: .conditionClause,
            fieldIDs: [.conditionLeaf(0, .target)],
            disputes: [DraftDispute(fieldID: "automation.conditionLeaves[0].target", kind: .wrongValue, evidence: "test")]
        )

        guard case .conditionClause(let index, let result)? = await specialists.execute(step, envelope) else {
            Issue.record("Expected .conditionClause repair result")
            return
        }
        #expect(index == 0)
        #expect(result.condition != nil)
    }

    @Test("two disputed condition leaves repair through the batched resolver")
    func batchedConditionDisputeRepairsLeaves() async {
        let registry = MockHomeDeviceRegistry()
        let envelope = await DeterministicDraftPipeline(registry: registry)
            .makeAutomationEnvelope(
                text: "turn on bedroom AC every day at 7 AM if the entry contact sensor is closed and the front door is locked"
            )
        guard let leafCount = envelope.automation?.conditionLeaves.count, leafCount >= 2 else {
            Issue.record("Expected at least two condition leaves, got \(String(describing: envelope.automation?.conditionLeaves.count))")
            return
        }
        let specialists = makeRegistry(registry: registry)

        let step = RepairPlanner.RepairStep(
            specialist: .conditionClause,
            fieldIDs: [.conditionLeaf(0, .target), .conditionLeaf(1, .target)],
            disputes: [
                DraftDispute(fieldID: "automation.conditionLeaves[0].target", kind: .wrongValue, evidence: "test"),
                DraftDispute(fieldID: "automation.conditionLeaves[1].target", kind: .wrongValue, evidence: "test"),
            ]
        )

        guard case .conditionClauses(let entries)? = await specialists.execute(step, envelope) else {
            Issue.record("Expected .conditionClauses batched repair result")
            return
        }
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.result.condition != nil })
    }

    // MARK: - .segmentation

    @Test("segmentation dispute re-splits a shared-verb mis-split action list")
    func segmentationDisputeCorrectsSharedVerbSplit() async {
        let registry = MockHomeDeviceRegistry()
        let envelope = await DeterministicDraftPipeline(registry: registry)
            .makeAutomationEnvelope(text: "turn on the bedroom AC and the bedroom lamp every day at 7 AM")

        // Injected FM segmentation returns the corrected two-action split.
        let segmentationWorker = AutomationComponentSegmentationWorkerSession(
            foundationModelAvailability: { true },
            segment: { _ in
                AutomationComponentPlanFMOutput(
                    triggerRawText: "every day at 7 AM",
                    triggerKind: .schedule,
                    actionRawTexts: ["turn on the bedroom AC", "turn on the bedroom lamp"],
                    conditionRawTexts: [],
                    conditionConnector: nil,
                    confidence: 0.95
                )
            }
        )
        let specialists = makeRegistry(registry: registry, segmentationWorker: segmentationWorker)

        let step = RepairPlanner.RepairStep(
            specialist: .segmentation,
            fieldIDs: [],
            disputes: [DraftDispute(fieldID: "automation.actions[1].targetDeviceID", kind: .wrongGrouping, evidence: "shared verb")]
        )

        guard case .segmentation(let plan)? = await specialists.execute(step, envelope) else {
            Issue.record("Expected .segmentation repair result")
            return
        }
        #expect(plan.actions.count == 2)
        #expect(plan.actions.map(\.rawText) == ["turn on the bedroom AC", "turn on the bedroom lamp"])

        let merged = EnvelopeMerger.apply(.segmentation(plan), to: envelope, iteration: 1)
        #expect(merged.automation?.actions.count == 2)
    }

    // MARK: - Unsupported kinds & missing workers

    @Test("holisticDraft repair is intentionally unsupported")
    func holisticDraftReturnsNil() async {
        let registry = MockHomeDeviceRegistry()
        let envelope = await DeterministicDraftPipeline(registry: registry)
            .makeAutomationEnvelope(text: "turn on bedroom AC every day at 7 AM")
        let specialists = makeRegistry(registry: registry)

        let step = RepairPlanner.RepairStep(specialist: .holisticDraft, fieldIDs: [], disputes: [])
        let result = await specialists.execute(step, envelope)
        #expect(result == nil)
    }

    @Test("automation specialists defer when their workers are not wired")
    func specialistsWithoutWorkersReturnNil() async {
        let registry = MockHomeDeviceRegistry()
        let envelope = await DeterministicDraftPipeline(registry: registry)
            .makeAutomationEnvelope(text: "When the entry contact sensor opens, turn on the porch light")
        let barebones = RepairSpecialistRegistry(
            fragmentNLU: FragmentNLUWorkerSession(foundationModelAvailability: { false }),
            targetResolver: ActionTargetResolver(registry: registry),
            riskAssessor: AutomationRiskAssessor(),
            operationDetection: { _ in nil }
        )

        let triggerStep = RepairPlanner.RepairStep(
            specialist: .trigger,
            fieldIDs: [.triggerType],
            disputes: [DraftDispute(fieldID: "automation.trigger.type", kind: .wrongValue, evidence: "test")]
        )
        #expect(await barebones.execute(triggerStep, envelope) == nil)

        let segStep = RepairPlanner.RepairStep(
            specialist: .segmentation,
            fieldIDs: [],
            disputes: [DraftDispute(fieldID: "automation.conditionTree.group[0]", kind: .wrongGrouping, evidence: "test")]
        )
        #expect(await barebones.execute(segStep, envelope) == nil)
    }

    // MARK: - End-to-end loop

    @Test("loop with a trigger dispute repairs and accepts instead of escalating")
    func loopRepairsTriggerAndAccepts() async {
        let registry = MockHomeDeviceRegistry()
        let counter = LoopCallCounter()
        let verifier = DraftVerifierWorkerSession(
            verify: { _, _ in
                let count = await counter.increment()
                if count == 1 {
                    return DraftVerdict(
                        accepted: false,
                        disputes: [DraftDispute(fieldID: "automation.trigger.type", kind: .wrongValue, evidence: "verify trigger")],
                        needsClarification: false
                    )
                }
                return DraftVerdict(accepted: true, disputes: [], needsClarification: false)
            },
            foundationModelAvailability: { false }
        )
        let orchestrator = VerifierLoopOrchestrator(
            pipeline: DeterministicDraftPipeline(registry: registry),
            verifier: verifier,
            promptBuilder: VerifierPromptBuilder(),
            planner: RepairPlanner(),
            specialists: makeRegistry(registry: registry),
            policy: VerifierLoopPolicy()
        )

        let output = await orchestrator.run(
            request: CommandRequest(
                text: "When the entry contact sensor opens, turn on the porch light",
                executeLowRiskCommands: false
            ),
            operationHint: HomeOperationDetectionResult(
                domain: .homeAutomation,
                operation: .automationCreation,
                confidence: 0.9,
                reason: "test"
            ),
            eventBus: AgentEventBus(),
            runID: UUID()
        )

        guard case .accepted = output.exit else {
            Issue.record("Expected .accepted, got \(output.exit)")
            return
        }
    }
}

private actor LoopCallCounter {
    private var count = 0
    func increment() -> Int {
        count += 1
        return count
    }
}
