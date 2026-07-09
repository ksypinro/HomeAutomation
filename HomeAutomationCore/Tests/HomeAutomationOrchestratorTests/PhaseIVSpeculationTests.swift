import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Phase IV — Speculation (Segmentation Overlap & Speculative Compilation)")
struct PhaseIVSpeculationTests {

    // MARK: - Plan Diffing

    @Test("Identical plans produce empty diff")
    func identicalPlansDiffEmpty() {
        let plan = AutomationComponentPlan(
            trigger: AutomationTriggerComponent(id: "t1", rawText: "every day at 7 PM", kindHint: .schedule),
            actions: [
                AutomationActionComponent(id: "a1", rawText: "turn on bedroom lamp", order: 0),
                AutomationActionComponent(id: "a2", rawText: "turn off kitchen light", order: 1),
            ],
            conditions: [
                AutomationConditionComponent(id: "c1", rawText: "front door is locked", order: 0),
            ],
            conditionTree: .leaf("c1"),
            unsupportedFragments: [],
            confidence: 0.85
        )

        let diff = AutomationComponentFanOutRunner.diffPlans(deterministic: plan, refined: plan)
        #expect(diff.isEmpty)
    }

    @Test("Changed action rawText produces diff")
    func changedActionRawTextProducesDiff() {
        let detPlan = AutomationComponentPlan(
            trigger: AutomationTriggerComponent(id: "t1", rawText: "every day at 7 PM", kindHint: .schedule),
            actions: [
                AutomationActionComponent(id: "a1", rawText: "turn on bedroom lamp", order: 0),
            ],
            conditions: [],
            conditionTree: nil,
            unsupportedFragments: [],
            confidence: 0.85
        )
        let fmPlan = AutomationComponentPlan(
            trigger: AutomationTriggerComponent(id: "t1", rawText: "every day at 7 PM", kindHint: .schedule),
            actions: [
                AutomationActionComponent(id: "a1", rawText: "turn on the bedroom lamp to 80%", order: 0),
            ],
            conditions: [],
            conditionTree: nil,
            unsupportedFragments: [],
            confidence: 0.92
        )

        let diff = AutomationComponentFanOutRunner.diffPlans(deterministic: detPlan, refined: fmPlan)
        #expect(diff.count == 1)
        #expect(diff.first?.id == "a1")
        #expect(diff.first?.kind == "action")
    }

    @Test("Changed trigger rawText produces diff")
    func changedTriggerProducesDiff() {
        let detPlan = AutomationComponentPlan(
            trigger: AutomationTriggerComponent(id: "t1", rawText: "every day at 7 PM", kindHint: .schedule),
            actions: [AutomationActionComponent(id: "a1", rawText: "turn on lamp", order: 0)],
            conditions: [],
            conditionTree: nil,
            unsupportedFragments: [],
            confidence: 0.85
        )
        let fmPlan = AutomationComponentPlan(
            trigger: AutomationTriggerComponent(id: "t1", rawText: "every weekday at 7 PM", kindHint: .schedule),
            actions: [AutomationActionComponent(id: "a1", rawText: "turn on lamp", order: 0)],
            conditions: [],
            conditionTree: nil,
            unsupportedFragments: [],
            confidence: 0.92
        )

        let diff = AutomationComponentFanOutRunner.diffPlans(deterministic: detPlan, refined: fmPlan)
        #expect(diff.contains { $0.kind == "trigger" })
    }

    @Test("Added condition in FM plan produces diff")
    func addedConditionProducesDiff() {
        let detPlan = AutomationComponentPlan(
            trigger: AutomationTriggerComponent(id: "t1", rawText: "every day at 7 PM", kindHint: .schedule),
            actions: [AutomationActionComponent(id: "a1", rawText: "turn on lamp", order: 0)],
            conditions: [],
            conditionTree: nil,
            unsupportedFragments: [],
            confidence: 0.85
        )
        let fmPlan = AutomationComponentPlan(
            trigger: AutomationTriggerComponent(id: "t1", rawText: "every day at 7 PM", kindHint: .schedule),
            actions: [AutomationActionComponent(id: "a1", rawText: "turn on lamp", order: 0)],
            conditions: [AutomationConditionComponent(id: "c1", rawText: "motion is active", order: 0)],
            conditionTree: .leaf("c1"),
            unsupportedFragments: [],
            confidence: 0.92
        )

        let diff = AutomationComponentFanOutRunner.diffPlans(deterministic: detPlan, refined: fmPlan)
        #expect(diff.contains { $0.kind == "condition" })
    }

    @Test("Removed action produces diff")
    func removedActionProducesDiff() {
        let detPlan = AutomationComponentPlan(
            trigger: nil,
            actions: [
                AutomationActionComponent(id: "a1", rawText: "turn on lamp", order: 0),
                AutomationActionComponent(id: "a2", rawText: "turn off fan", order: 1),
            ],
            conditions: [],
            conditionTree: nil,
            unsupportedFragments: [],
            confidence: 0.85
        )
        let fmPlan = AutomationComponentPlan(
            trigger: nil,
            actions: [
                AutomationActionComponent(id: "a1", rawText: "turn on lamp", order: 0),
            ],
            conditions: [],
            conditionTree: nil,
            unsupportedFragments: [],
            confidence: 0.92
        )

        let diff = AutomationComponentFanOutRunner.diffPlans(deterministic: detPlan, refined: fmPlan)
        #expect(diff.contains { $0.kind == "action.removed" })
    }

    // MARK: - Speculative Compilation Result

    @Test("SpeculativeCompilationResult carries ruleDraft and JSON")
    func speculativeCompilationResultFields() {
        let draft = HomeAutomationRuleDraft(
            name: "Turn on lamp every day at 7 PM",
            trigger: .schedule(HomeAutomationScheduleTrigger(
                repeatRule: .everyDay,
                timeOfDay: HomeAutomationTimeOfDay(hour: 19, minute: 0),
                timezoneIdentifier: nil
            )),
            condition: nil,
            actionDescriptions: ["Turn on lamp"],
            confidence: 0.85
        )

        let result = SpeculativeCompilationResult(
            ruleDraft: draft,
            smartThingsRuleJSON: "{\"name\":\"test\"}",
            compilationDetail: "speculative-compiled"
        )

        #expect(result.ruleDraft.name == "Turn on lamp every day at 7 PM")
        #expect(result.smartThingsRuleJSON != nil)
        #expect(result.compilationDetail == "speculative-compiled")
    }

    @Test("AutomationResolvedComponentSet carries speculativeCompilation when set")
    func resolvedComponentSetCarriesSpeculativeCompilation() {
        let draft = HomeAutomationRuleDraft(
            name: "Test",
            trigger: nil,
            condition: nil,
            actionDescriptions: ["turn on lamp"],
            confidence: 0.85
        )
        let compilation = SpeculativeCompilationResult(
            ruleDraft: draft,
            smartThingsRuleJSON: "{}",
            compilationDetail: "test"
        )

        let set = AutomationResolvedComponentSet(
            trigger: nil,
            actionResults: [],
            conditionResults: [],
            conditionTree: nil,
            speculativeCompilation: compilation
        )

        #expect(set.speculativeCompilation != nil)
        #expect(set.speculativeCompilation?.compilationDetail == "test")
    }

    @Test("AutomationResolvedComponentSet defaults to nil speculativeCompilation")
    func resolvedComponentSetDefaultsToNilSpeculative() {
        let set = AutomationResolvedComponentSet(
            trigger: nil,
            actionResults: [],
            conditionResults: [],
            conditionTree: nil
        )

        #expect(set.speculativeCompilation == nil)
    }

    // MARK: - Speculative Segmentation Worker

    @Test("Segmentation worker in speculative mode returns deterministic plan")
    func segmentationWorkerSpeculativeMode() async throws {
        let worker = AutomationComponentSegmentationWorkerSession(
            foundationModelAvailability: { false },
            speculativeMode: true
        )

        let plan = try await worker.segment(
            "Every day at 7 PM turn on bedroom lamp if front door is locked"
        )

        #expect(plan.actions.count >= 1)
        #expect(plan.trigger != nil)
    }

    @Test("Segmentation worker non-speculative mode follows normal τ-gate")
    func segmentationWorkerNonSpeculativeMode() async throws {
        let worker = AutomationComponentSegmentationWorkerSession(
            foundationModelAvailability: { false },
            speculativeMode: false
        )

        let plan = try await worker.segment(
            "Every day at 7 PM turn on bedroom lamp"
        )

        #expect(plan.actions.count >= 1)
    }

    // MARK: - Assembly Agent Short-Circuit

    @Test("AutomationDraftAssemblyAgent short-circuits with speculative compilation")
    func assemblyAgentShortCircuitsWithSpeculative() async throws {
        let draft = HomeAutomationRuleDraft(
            name: "Speculative Draft",
            trigger: .schedule(HomeAutomationScheduleTrigger(
                repeatRule: .everyDay,
                timeOfDay: HomeAutomationTimeOfDay(hour: 19, minute: 0),
                timezoneIdentifier: nil
            )),
            condition: nil,
            actionDescriptions: ["turn on lamp"],
            confidence: 0.9
        )
        let compilation = SpeculativeCompilationResult(
            ruleDraft: draft,
            smartThingsRuleJSON: "{}",
            compilationDetail: "speculative-compiled"
        )

        let plan = AutomationComponentPlan(
            trigger: AutomationTriggerComponent(id: "t1", rawText: "every day at 7 PM", kindHint: .schedule),
            actions: [AutomationActionComponent(id: "a1", rawText: "turn on lamp", order: 0)],
            conditions: [],
            conditionTree: nil,
            unsupportedFragments: [],
            confidence: 0.85
        )
        let resolved = AutomationResolvedComponentSet(
            trigger: nil,
            actionResults: [],
            conditionResults: [],
            conditionTree: nil,
            speculativeCompilation: compilation
        )

        let agent = AutomationDraftAssemblyAgent()
        let input = AutomationDraftAssemblyInput(
            componentPlan: plan,
            resolvedComponents: resolved
        )
        let context = ResolutionContext(
            request: CommandRequest(text: "test", executeLowRiskCommands: false)
        )
        let result = try await agent.run(input, context: context)

        #expect(result.name == "Speculative Draft")
        #expect(result.actionDescriptions == ["turn on lamp"])
    }

    // MARK: - End-to-end Speculative Flow

    @Test("Full automation resolution with speculative mode produces valid plan")
    func fullAutomationWithSpeculation() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Every day at 7 PM turn on bedroom lamp if front door is locked",
            executeLowRiskCommands: false
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.resolvedActions.count >= 1)
        #expect(plan.smartThingsRuleJSON != nil)
    }
}
