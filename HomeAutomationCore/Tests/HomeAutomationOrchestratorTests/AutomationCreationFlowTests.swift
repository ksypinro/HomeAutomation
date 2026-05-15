import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite
struct AutomationCreationFlowTests {
    @Test
    func operationDetectionRoutesScheduledCommandToAutomationCreation() {
        let detector = HomeOperationDetectionService()

        let result = detector.detect("Turn on AC everyday at 7 AM")

        #expect(result.domain == .homeAutomation)
        #expect(result.operation == .automationCreation)
        #expect(result.confidence > 0.7)
    }

    @Test
    func operationDetectionRecognizesOutOfScopeAutomationRequests() {
        let detector = HomeOperationDetectionService()

        #expect(detector.detect("Delete my morning automation").operation == .automationDeletion)
        #expect(detector.detect("Disable the night light rule").operation == .automationUpdate)
        #expect(detector.detect("List automations").operation == .automationQuery)
    }

    @Test
    func patternParserExtractsDailyScheduleAndAction() throws {
        let parser = AutomationPatternParser()

        let output = try #require(parser.parse("Turn on AC everyday at 7 AM"))
        let draft = try output.makeRuleDraft()

        #expect(draft.intent == .createAutomation)
        #expect(draft.actionDescriptions == ["Turn on AC"])
        guard case .schedule(let schedule) = draft.trigger else {
            Issue.record("Expected schedule trigger")
            return
        }
        #expect(schedule.repeatRule == .everyDay)
        #expect(schedule.timeOfDay?.hour == 7)
        #expect(schedule.timeOfDay?.minute == 0)
    }

    @Test
    func orchestratorCreatesAutomationDraftWithResolvedActionAndSmartThingsJSON() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on bedroom AC everyday at 7 AM",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automation draft, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.ruleDraft.intent == .createAutomation)
        #expect(plan.resolvedActions.count == 1)
        #expect(plan.resolvedActions.first?.draft.capability == "switch")
        #expect(plan.resolvedActions.first?.draft.command == "on")
        #expect(plan.resolvedActions.first?.device?.id == "bedroom_ac")
        #expect(plan.smartThingsRuleJSON?.contains(#""every""#) == true)
        #expect(plan.smartThingsRuleJSON?.contains(#""command""#) == true)
    }

    @Test
    func automationCreationStreamEmitsPhaseNineEvents() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )
        var stages: [String] = []
        var result: HomeAutomationResolverResult?

        for try await update in orchestrator.resolveStream(
            "Turn on bedroom AC everyday at 7 AM if the entry contact sensor is closed",
            executeLowRiskCommands: true
        ) {
            switch update {
            case .event(let event):
                stages.append(event.stage)
            case .result(let output):
                result = output
            }
        }

        guard case .automationDrafted(let plan) = result?.resolution else {
            Issue.record("Expected automation draft")
            return
        }
        #expect(stages.contains("operationDetection"))
        #expect(stages.contains("automationDraft"))
        #expect(stages.contains("automationActionResolution"))
        #expect(stages.contains("automationConditionOperandResolution"))
        #expect(stages.contains("automationValidation"))
        #expect(stages.contains("smartThingsCompilation"))
        #expect(stages.contains("automationResultAssembly"))
        #expect(plan.smartThingsRuleJSON?.contains(#""trigger" : "Never""#) == true)
    }

    @Test
    func highRiskAutomationRequiresConfirmation() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Unlock front door every day at 7 AM",
            executeLowRiskCommands: true
        )

        guard case .automationRequiresConfirmation(let plan) = result.resolution else {
            Issue.record("Expected high-risk automation confirmation, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.requiresConfirmation)
        #expect(plan.resolvedActions.first?.draft.capability == "lock")
        #expect(plan.resolvedActions.first?.draft.command == "unlock")
    }

    @Test
    func weekdayScheduleIsParsedButSmartThingsCompilationIsUnsupported() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on AC every Monday at 7 AM",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automation draft with unsupported compilation reason")
            return
        }
        #expect(plan.smartThingsRuleJSON == nil)
        #expect(plan.unsupportedCompilationReason?.contains("does not support schedule") == true)
    }

    @Test
    func directCommandStillUsesExistingPath() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on the bedroom lamp",
            executeLowRiskCommands: false
        )

        guard case .readyToExecute = result.resolution else {
            Issue.record("Expected direct command ready to execute")
            return
        }
        #expect(result.draft?.targetDeviceID == "bedroom_lamp")
    }

    @Test
    func nonCreationAutomationRequestsReturnUnsupported() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )
        let commands = [
            "Delete my morning automation",
            "Disable the night light rule",
            "List automations"
        ]

        for command in commands {
            let result = try await orchestrator.resolve(command, executeLowRiskCommands: false)

            guard case .unsupported(let reason) = result.resolution else {
                Issue.record("Expected unsupported for \(command), got \(result.resolution.displaySummary)")
                continue
            }
            #expect(reason.contains("Only automation creation is currently supported"))
            #expect(result.state.intent.topFamilies == [.unsupported])
        }
    }
}
