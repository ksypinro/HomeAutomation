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
    func patternParserExtractsDailyScheduleAndAction() throws {
        let parser = AutomationPatternParser()

        let draft = try #require(parser.parse("Turn on AC everyday at 7 AM"))

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
}
