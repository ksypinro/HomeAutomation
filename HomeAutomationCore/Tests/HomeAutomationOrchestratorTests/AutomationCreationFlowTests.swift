import Foundation
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
    func operationDetectionRoutesConversationalRoutineToAutomationCreation() {
        let detector = HomeOperationDetectionService()

        let result = detector.detect(
            "Today is quite hot. The temperature sensor is showing 25 Degree celcius. I want you to remember this and always turn on the Bedroom AC in similar situation"
        )

        #expect(result.domain == .homeAutomation)
        #expect(result.operation == .automationCreation)
        #expect(result.confidence > 0.8)
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
    func patternParserExtractsBetweenCondition() throws {
        let parser = AutomationPatternParser()

        let output = try #require(parser.parse("Turn on bedroom lamp every day at 7 AM if bedroom lamp level is between 20 and 80"))
        let draft = try output.makeRuleDraft()

        guard case .comparison(let comparison) = draft.condition else {
            Issue.record("Expected between comparison condition")
            return
        }
        #expect(comparison.operatorName == .between)
        guard case .literalRange(let start, let end, _) = comparison.right else {
            Issue.record("Expected literal range right operand")
            return
        }
        #expect(start == 20)
        #expect(end == 80)
    }

    @Test
    func patternParserExtractsChangesCondition() throws {
        let parser = AutomationPatternParser()

        let output = try #require(parser.parse("When hallway motion sensor changes to active turn on bedroom lamp"))
        let draft = try output.makeRuleDraft()

        guard case .device(let trigger) = draft.trigger else {
            Issue.record("Expected device trigger")
            return
        }
        guard case .changes(let child) = trigger.condition,
              case .comparison(let comparison) = child else {
            Issue.record("Expected changes condition wrapping a comparison")
            return
        }
        #expect(comparison.operatorName == .equals)
        #expect(comparison.triggerPolicy == .always)
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
    func conversationalTemperatureRoutineCreatesResolvedAutomation() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Today is quite hot. The temperature sensor is showing 25 Degree celcius. I want you to remember this and always turn on the Bedroom AC in similar situation",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automation draft, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.ruleDraft.actionDescriptions == ["Turn on the Bedroom AC"])
        #expect(plan.resolvedActions.first?.device?.id == "bedroom_ac")
        #expect(plan.resolvedActions.first?.draft.capability == "switch")
        #expect(plan.resolvedActions.first?.draft.command == "on")

        guard case .device(let trigger) = plan.ruleDraft.trigger else {
            Issue.record("Expected temperature reading to become a device trigger")
            return
        }
        guard case .comparison(let comparison) = trigger.condition else {
            Issue.record("Expected comparison trigger condition")
            return
        }
        guard case .deviceAttribute(_, let deviceID, let capability, let attribute) = comparison.left else {
            Issue.record("Expected resolved device attribute condition")
            return
        }
        #expect(deviceID == "bedroom_temperature_sensor")
        #expect(capability == "temperatureMeasurement")
        #expect(attribute == "temperature")
        #expect(comparison.operatorName == .greaterThanOrEquals)
        #expect(comparison.right == .literalNumber(25, unit: "celsius"))
        #expect(plan.smartThingsRuleJSON?.contains("bedroom_temperature_sensor") == true)
        #expect(plan.smartThingsRuleJSON?.contains("bedroom_ac") == true)
        #expect(plan.smartThingsRuleJSON?.contains("greaterThanOrEquals") == true)
    }

    @Test
    func graphNativeAutomationCreationUsesGraphOnlyOutput() async throws {
        let command = "Turn on bedroom AC everyday at 7 AM"
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(command, executeLowRiskCommands: true)
        let metrics = try #require(await orchestrator.lastMetrics())

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected graph automation path to draft an automation.")
            return
        }

        #expect(plan.ruleDraft.actionDescriptions == ["Turn on bedroom AC"])
        #expect(plan.resolvedActions.first?.device?.id == "bedroom_ac")
        #expect(plan.smartThingsRuleJSON?.contains("bedroom_ac") == true)
        #expect(result.aggregation.finalCandidateIDs == ["bedroom_ac"])
        #expect(metrics.graphRun?.graphID == "automation-creation-graph")
    }

    @Test
    func graphNativeAutomationCreationRecordsActualGraphMetrics() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        _ = try await orchestrator.resolve(
            "Turn on bedroom AC everyday at 7 AM",
            executeLowRiskCommands: true
        )
        let metrics = try #require(await orchestrator.lastMetrics())
        let graphRun = try #require(metrics.graphRun)

        #expect(graphRun.graphID == "automation-creation-graph")
        #expect(metrics.agentTraces.contains { $0.agentID == .operationDetection })
        #expect(graphRun.nodeStatuses[AgentID.automationComponentSegmentation.rawValue] == GraphNodeRunStatus.completed)
        #expect(graphRun.nodeStatuses[AgentID.automationComponentFanOut.rawValue] == GraphNodeRunStatus.completed)
        #expect(graphRun.nodeStatuses[AgentID.automationDraftAssembly.rawValue] == GraphNodeRunStatus.completed)
        #expect(graphRun.nodeStatuses[AgentID.automationValidation.rawValue] == GraphNodeRunStatus.completed)
        #expect(graphRun.nodeStatuses[AgentID.smartThingsCompilation.rawValue] == GraphNodeRunStatus.completed)
        #expect(graphRun.nodeStatuses[AgentID.automationResultAssembly.rawValue] == GraphNodeRunStatus.completed)
        #expect(graphRun.nodeDurations.isEmpty == false)
        #expect(metrics.automationMetrics.graphNodeStatuses == graphRun.nodeStatuses.mapValues { $0.rawValue })
    }

    @Test
    func graphNativeAutomationCreationAddsDynamicFanOutMetrics() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on bedroom AC and turn off kitchen strip light every day at 7 AM if entry contact sensor is closed and porch light is off",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automation draft, got \(String(describing: result.resolution.displaySummary))")
            return
        }
        #expect(plan.resolvedActions.map { $0.originalText } == [
            "Turn on bedroom AC",
            "Turn off kitchen strip light"
        ])
        #expect(plan.resolvedActions.map { $0.device?.id } == [
            "bedroom_ac",
            "kitchen_strip_light"
        ])

        let metrics = try #require(await orchestrator.lastMetrics())
        let graphRun = try #require(metrics.graphRun)
        #expect(graphRun.nodeStatuses["automationActionResolution:a1"] == GraphNodeRunStatus.completed)
        #expect(graphRun.nodeStatuses["automationActionResolution:a2"] == GraphNodeRunStatus.completed)
        #expect(graphRun.nodeStatuses["automationConditionOperandResolution:c1"] == GraphNodeRunStatus.completed)
        #expect(graphRun.nodeStatuses["automationConditionOperandResolution:c2"] == GraphNodeRunStatus.completed)
        #expect(metrics.automationMetrics.graphNodeStatuses == graphRun.nodeStatuses.mapValues { $0.rawValue })
    }

    @Test
    func automationCreationStreamEmitsPhaseNineEvents() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )
        var stages: [String] = []
        var agentIDs: [String] = []
        var result: HomeAutomationResolverResult?

        for try await update in orchestrator.resolveStream(
            "Turn on bedroom AC everyday at 7 AM if the entry contact sensor is closed",
            executeLowRiskCommands: true
        ) {
            switch update {
            case .event(let event):
                stages.append(event.stage)
                if let agentID = event.agentID {
                    agentIDs.append(agentID)
                }
            case .result(let output):
                result = output
            }
        }

        guard case .automationDrafted(let plan) = result?.resolution else {
            Issue.record("Expected automation draft")
            return
        }
        #expect(stages.contains("operationDetection"))
        #expect(stages.contains("automationComponentSegmentation"))
        #expect(stages.contains("automationComponentFanOut"))
        #expect(stages.contains("automationDraftAssembly"))
        #expect(stages.contains("automationComponentFanOut/trigger:t1"))
        #expect(stages.contains("automationComponentFanOut/action:a1"))
        #expect(stages.contains("automationComponentFanOut/condition:c1"))
        #expect(stages.contains("automationValidation"))
        #expect(stages.contains("smartThingsCompilation"))
        #expect(stages.contains("automationResultAssembly"))
        #expect(agentIDs.contains("ruleFallback"))
        #expect(agentIDs.contains("bixbyFallback"))
        #expect(plan.smartThingsRuleJSON?.contains(#""trigger" : "Never""#) == true)
    }

    @Test
    func automationActionResolutionStreamEmitsScopedSubAgentStatusesForEachAction() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )
        var agentIDs: [String] = []

        for try await update in orchestrator.resolveStream(
            "Turn on bedroom AC and turn off kitchen strip light every day at 7 AM",
            executeLowRiskCommands: true
        ) {
            if case .event(let event) = update, let agentID = event.agentID {
                agentIDs.append(agentID)
            }
        }

        #expect(agentIDs.contains(AgentID.automationComponentFanOut.rawValue))
        #expect(agentIDs.contains("ruleFallback"))
        #expect(agentIDs.contains("bixbyFallback"))
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
    func conditionalUnlockUsesIfConditionAsDeviceTrigger() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Unlock the front door if bedroom ac is turned on",
            executeLowRiskCommands: true
        )

        guard case .automationRequiresConfirmation(let plan) = result.resolution else {
            Issue.record("Expected high-risk automation confirmation, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.ruleDraft.actionDescriptions == ["Unlock the front door"])
        guard case .device(let trigger) = plan.ruleDraft.trigger else {
            Issue.record("Expected bedroom AC state to be represented as a device trigger")
            return
        }
        #expect(trigger.description == "bedroom ac is turned on")
        #expect(plan.resolvedActions.first?.originalText == "Unlock the front door")
        #expect(plan.resolvedActions.first?.device?.id == "front_door_lock")
        #expect(plan.smartThingsRuleJSON?.contains("front_door_lock") == true)
        #expect(plan.smartThingsRuleJSON?.contains("bedroom_ac") == true)
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
    func betweenConditionCompilesEndToEnd() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on bedroom AC every day at 7 AM if bedroom lamp level is between 20 and 80",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automation draft, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.smartThingsRuleJSON?.contains(#""between""#) == true)
        #expect(plan.smartThingsRuleJSON?.contains(#""switchLevel""#) == true)
        #expect(plan.smartThingsRuleJSON?.contains(#""level""#) == true)
    }

    @Test
    func oneTimeScheduleRemainsDraftedWithUnsupportedCompilationReason() async throws {
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on bedroom AC once at 7 AM",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automation draft with unsupported compilation reason")
            return
        }
        #expect(plan.smartThingsRuleJSON == nil)
        #expect(plan.unsupportedCompilationReason?.contains("one-time schedule") == true)
    }

    @Test
    func defaultAutomationCreationDoesNotCallSmartThingsBackend() async throws {
        let creator = RecordingSmartThingsRuleCreator()
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false },
            smartThingsRuleCreator: creator
        )

        let result = try await orchestrator.resolve(
            "Turn on bedroom AC every day at 7 AM",
            executeLowRiskCommands: true
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected automation draft, got \(result.resolution.displaySummary)")
            return
        }
        #expect(plan.smartThingsRuleJSON != nil)
        #expect(plan.backendResponse == nil)
        #expect(await creator.callCount == 0)
    }

    @Test
    func explicitCreatePersistsCompiledSmartThingsRule() async throws {
        let creator = RecordingSmartThingsRuleCreator()
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false },
            smartThingsRuleCreator: creator
        )

        let result = try await orchestrator.resolve(
            "Turn on bedroom AC every day at 7 AM",
            executeLowRiskCommands: true,
            automationCreationOptions: .create(locationID: "location-1")
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected created automation draft, got \(result.resolution.displaySummary)")
            return
        }
        #expect(await creator.callCount == 1)
        #expect(await creator.lastLocationID == "location-1")
        #expect(plan.backendResponse?.status == .created)
        #expect(plan.backendResponse?.ruleID == "rule-1")
        #expect(plan.backendResponse?.locationID == "location-1")
        #expect(result.resolution.displaySummary.contains("Automation created"))
    }

    @Test
    func highRiskPersistentAutomationRequiresExplicitConfirmationBeforeCreate() async throws {
        let creator = RecordingSmartThingsRuleCreator()
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false },
            smartThingsRuleCreator: creator
        )

        let result = try await orchestrator.resolve(
            "Unlock front door every day at 7 AM",
            executeLowRiskCommands: true,
            automationCreationOptions: .create(locationID: "location-1")
        )

        guard case .automationRequiresConfirmation(let plan) = result.resolution else {
            Issue.record("Expected confirmation requirement, got \(result.resolution.displaySummary)")
            return
        }
        #expect(await creator.callCount == 0)
        #expect(plan.backendResponse?.status == .confirmationRequired)
    }

    @Test
    func confirmedHighRiskPersistentAutomationCanCreateRule() async throws {
        let creator = RecordingSmartThingsRuleCreator()
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: MockHomeDeviceRegistry(),
            foundationModelAvailability: { false },
            smartThingsRuleCreator: creator
        )

        let result = try await orchestrator.resolve(
            "Unlock front door every day at 7 AM",
            executeLowRiskCommands: true,
            automationCreationOptions: .create(locationID: "location-1", confirmsHighRiskAutomation: true)
        )

        guard case .automationDrafted(let plan) = result.resolution else {
            Issue.record("Expected confirmed high-risk automation to be created, got \(result.resolution.displaySummary)")
            return
        }
        #expect(await creator.callCount == 1)
        #expect(plan.requiresConfirmation == false)
        #expect(plan.backendResponse?.status == .created)
    }

    @Test
    func ruleCreationAgentDoesNotCallBackendWhenValidationFailed() async throws {
        let creator = RecordingSmartThingsRuleCreator()
        let draft = HomeAutomationRuleDraft(
            name: "Invalid automation",
            trigger: .schedule(
                HomeAutomationScheduleTrigger(
                    repeatRule: .everyDay,
                    timeOfDay: HomeAutomationTimeOfDay(hour: 7, minute: 0)
                )
            ),
            condition: nil,
            actionDescriptions: ["Turn on AC"],
            confidence: 0.7
        )
        let plan = HomeAutomationCreationPlan(
            name: draft.name,
            ruleDraft: draft,
            resolvedActions: [],
            smartThingsRuleJSON: #"{"name":"Invalid automation","actions":[]}"#,
            requiresConfirmation: false,
            unsupportedCompilationReason: nil
        )
        let validation = AutomationValidationResult(
            issues: [
                AutomationValidationIssue(
                    code: "automation.action.missing",
                    message: "Automation action did not validate.",
                    severity: .error
                )
            ],
            status: .unsupported
        )

        let output = try await SmartThingsRuleCreationAgent(creator: creator).run(
            SmartThingsRuleCreationInput(
                plan: plan,
                document: SmartThingsRuleDocument(name: draft.name, jsonString: plan.smartThingsRuleJSON ?? "{}"),
                validation: validation,
                options: .create(locationID: "location-1")
            ),
            context: ResolutionContext(
                request: CommandRequest(
                    text: draft.name,
                    executeLowRiskCommands: false,
                    automationCreationOptions: .create(locationID: "location-1")
                )
            )
        )

        #expect(output.receipt?.status == .skipped)
        #expect(await creator.callCount == 0)
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

private actor RecordingSmartThingsRuleCreator: SmartThingsRuleCreating {
    private var requests: [SmartThingsRuleCreationRequest] = []

    var callCount: Int {
        requests.count
    }

    var lastLocationID: String? {
        requests.last?.locationID
    }

    func createRule(_ request: SmartThingsRuleCreationRequest) async throws -> SmartThingsRuleCreationReceipt {
        requests.append(request)
        return SmartThingsRuleCreationReceipt(
            status: .created,
            ruleID: "rule-\(requests.count)",
            locationID: request.locationID,
            requestID: "request-\(requests.count)",
            message: "Created by test backend.",
            createdAt: Date(),
            rawResponse: #"{"ruleId":"rule-\#(requests.count)"}"#
        )
    }
}
