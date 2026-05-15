import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite
struct AutomationActionResolverTests {

    // MARK: - AutomationActionResolver Tests

    @Test
    func singleActionResolvesToSwitchOnCommand() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on bedroom AC everyday at 7 AM",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.resolvedActions.count == 1)
        #expect(plan.resolvedActions[0].draft.capability == "switch")
        #expect(plan.resolvedActions[0].draft.command == "on")
        #expect(plan.resolvedActions[0].originalText.lowercased().contains("turn on"))
    }

    @Test
    func singleActionResolvesTargetDevice() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on bedroom AC everyday at 7 AM",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.resolvedActions[0].device?.id == "bedroom_ac")
    }

    @Test
    func multipleActionDescriptionsResolveIndependently() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on AC and turn off the bedroom lamp every day at 7 AM",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.resolvedActions.count >= 1)
        // First action should always be present and resolved
        let first = plan.resolvedActions.first
        #expect(first?.draft.capability != nil)
        #expect(first?.draft.command != nil)
    }

    @Test
    func resolvedActionDoesNotMockExecute() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on bedroom lamp everyday at 7 AM",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(result.resolution.displaySummary)")
            return
        }
        // The action should NOT have been executed — it should be draft-only.
        // An executed resolution would be `.executed(...)`, not `.automationDrafted(...)`.
        #expect(plan.resolvedActions.count == 1)
        #expect(plan.resolvedActions[0].draft.capability == "switch")
    }

    @Test
    func automationDraftContainsSmartThingsJSON() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on bedroom AC everyday at 7 AM",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.smartThingsRuleJSON != nil)
        #expect(plan.smartThingsRuleJSON?.contains("\"every\"") == true)
        #expect(plan.smartThingsRuleJSON?.contains("\"command\"") == true)
    }

    @Test
    func automationDraftContainsTriggerInfo() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on bedroom AC everyday at 7 AM",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted, got \(result.resolution.displaySummary)")
            return
        }
        guard case .schedule(let schedule) = plan.ruleDraft.trigger else {
            Issue.record("Expected schedule trigger")
            return
        }
        #expect(schedule.repeatRule == .everyDay)
        #expect(schedule.timeOfDay?.hour == 7)
        #expect(schedule.timeOfDay?.minute == 0)
    }

    @Test
    func unsupportedWeekdayScheduleProducesCompilationReason() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on AC every Monday at 7 AM",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automationDrafted with unsupported compilation reason")
            return
        }
        #expect(plan.smartThingsRuleJSON == nil)
        #expect(plan.unsupportedCompilationReason != nil)
    }

    // MARK: - Direct Command Regression

    @Test
    func directCommandStillWorksAfterRefactor() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on the bedroom lamp",
            executeLowRiskCommands: false
        )

        guard case .readyToExecute = result.resolution else {
            Issue.record("Expected direct command readyToExecute, got \(result.resolution.displaySummary)")
            return
        }
        #expect(result.draft?.targetDeviceID == "bedroom_lamp")
    }

    // MARK: - AutomationActionResolutionResult Model Tests

    @Test
    func resultNeedsClarificationProperty() {
        let result = AutomationActionResolutionResult(
            resolvedAction: nil,
            retrievedCandidates: [],
            hydratedCandidates: [],
            selectedCandidateIDs: [],
            draft: nil,
            resolution: .needsClarification("Which AC?"),
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: [],
                needsClarification: true,
                confidence: 0
            )
        )
        #expect(result.needsClarification == true)
        #expect(result.isResolved == false)
        #expect(result.isUnsupported == false)
    }

    @Test
    func resultUnsupportedProperty() {
        let result = AutomationActionResolutionResult(
            resolvedAction: nil,
            retrievedCandidates: [],
            hydratedCandidates: [],
            selectedCandidateIDs: [],
            draft: nil,
            resolution: .unsupported("Not supported"),
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: [],
                needsClarification: false,
                confidence: 0
            )
        )
        #expect(result.isUnsupported == true)
        #expect(result.isResolved == false)
        #expect(result.needsClarification == false)
    }

    @Test
    func resultRequiresConfirmationProperty() {
        let result = AutomationActionResolutionResult(
            resolvedAction: nil,
            retrievedCandidates: [],
            hydratedCandidates: [],
            selectedCandidateIDs: [],
            draft: nil,
            resolution: .requiresConfirmation(
                HomeCommandDraft(
                    intent: .lock,
                    targetDeviceID: "lock",
                    capability: "lock",
                    command: "lock",
                    needsClarification: false,
                    requiresConfirmation: true,
                    confidence: 0.9
                )
            ),
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: [],
                needsClarification: false,
                confidence: 0.9
            )
        )
        #expect(result.requiresConfirmation == true)
    }

    // MARK: - Operation Detection Regression

    @Test
    func operationDetectorRoutesDailySchedule() {
        let detector = HomeOperationDetectionService()
        let result = detector.detect("Turn on AC everyday at 7 AM")
        #expect(result.operation == .automationCreation)
    }

    @Test
    func operationDetectorRoutesDirectCommand() {
        let detector = HomeOperationDetectionService()
        let result = detector.detect("Turn on the TV")
        #expect(result.operation == .executeDeviceCommand)
    }

    @Test
    func operationDetectorRoutesDeviceTrigger() {
        let detector = HomeOperationDetectionService()
        let result = detector.detect("When motion is detected turn on the hallway light")
        #expect(result.operation == .automationCreation)
    }
}
