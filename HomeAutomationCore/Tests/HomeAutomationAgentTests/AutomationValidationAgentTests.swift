import HomeAutomationAgents
import HomeAutomationCore
import Testing

@Suite
struct AutomationValidationAgentTests {
    @Test
    func validDailySchedulePlusSwitchActionPasses() async throws {
        let draft = ruleDraft(actionDescriptions: ["Turn on bedroom lamp"])
        let action = resolvedAction(
            "Turn on bedroom lamp",
            deviceID: "bedroom_lamp",
            capability: "switch",
            command: "on"
        )

        let result = try await AutomationValidationAgent().run(
            AutomationValidationInput(ruleDraft: draft, resolvedActions: [action]),
            context: context()
        )

        #expect(result.status == .valid)
        #expect(result.isValid)
        #expect(result.requiresConfirmation == false)
    }

    @Test
    func multipleValidActionsPass() async throws {
        let draft = ruleDraft(actionDescriptions: [
            "Turn on bedroom lamp",
            "Turn on bedroom AC"
        ])
        let actions = [
            resolvedAction("Turn on bedroom lamp", deviceID: "bedroom_lamp", capability: "switch", command: "on"),
            resolvedAction("Turn on bedroom AC", deviceID: "bedroom_ac", capability: "switch", command: "on")
        ]

        let result = try await AutomationValidationAgent().run(
            AutomationValidationInput(ruleDraft: draft, resolvedActions: actions),
            context: context()
        )

        #expect(result.status == .valid)
        #expect(result.issues.filter { $0.severity == .error }.isEmpty)
    }

    @Test
    func unsupportedWeekdayScheduleIsPreservedAsCompilationWarning() async throws {
        let draft = ruleDraft(
            trigger: .schedule(
                HomeAutomationScheduleTrigger(
                    repeatRule: .daysOfWeek([.monday]),
                    timeOfDay: HomeAutomationTimeOfDay(hour: 7, minute: 0)
                )
            ),
            actionDescriptions: ["Turn on bedroom AC"]
        )
        let action = resolvedAction(
            "Turn on bedroom AC",
            deviceID: "bedroom_ac",
            capability: "switch",
            command: "on"
        )

        let result = try await AutomationValidationAgent().run(
            AutomationValidationInput(ruleDraft: draft, resolvedActions: [action]),
            context: context()
        )

        #expect(result.status == .valid)
        #expect(result.unsupportedCompilationReason?.contains("weekday") == true)
        #expect(result.issues.contains { $0.code == "automation.schedule.unsupportedCompilation" })
    }

    @Test
    func lockUnlockActionRequiresConfirmation() async throws {
        let draft = ruleDraft(actionDescriptions: ["Unlock front door"])
        let action = resolvedAction(
            "Unlock front door",
            deviceID: "front_door_lock",
            capability: "lock",
            command: "unlock",
            deviceType: "lock",
            riskLevel: .high
        )

        let result = try await AutomationValidationAgent().run(
            AutomationValidationInput(ruleDraft: draft, resolvedActions: [action]),
            context: context()
        )

        #expect(result.status == .requiresConfirmation)
        #expect(result.requiresConfirmation)
        #expect(result.issues.contains { $0.code == "automation.action.requiresConfirmation" })
    }

    @Test
    func unresolvedDeviceConditionNeedsClarification() async throws {
        let condition = HomeAutomationCondition.comparison(
            HomeAutomationComparisonCondition(
                left: .deviceAttribute(
                    description: "bedroom window",
                    deviceID: nil,
                    capability: nil,
                    attribute: nil
                ),
                operatorName: .equals,
                right: .literalString("closed")
            )
        )
        let draft = ruleDraft(
            condition: condition,
            actionDescriptions: ["Turn on bedroom AC"]
        )
        let action = resolvedAction(
            "Turn on bedroom AC",
            deviceID: "bedroom_ac",
            capability: "switch",
            command: "on"
        )

        let result = try await AutomationValidationAgent().run(
            AutomationValidationInput(ruleDraft: draft, resolvedActions: [action]),
            context: context()
        )

        #expect(result.status == .needsClarification)
        #expect(result.clarificationQuestion?.contains("bedroom window") == true)
    }

    @Test
    func nestedConditionTreeRemainsValidWhenOperandsAreResolved() async throws {
        let contactClosed = HomeAutomationCondition.comparison(
            HomeAutomationComparisonCondition(
                left: .deviceAttribute(
                    description: "entry contact sensor",
                    deviceID: "entry_contact_sensor",
                    capability: "contactSensor",
                    attribute: "contact"
                ),
                operatorName: .equals,
                right: .literalString("closed")
            )
        )
        let motionInactive = HomeAutomationCondition.comparison(
            HomeAutomationComparisonCondition(
                left: .deviceAttribute(
                    description: "hallway motion sensor",
                    deviceID: "hallway_motion_sensor",
                    capability: "motionSensor",
                    attribute: "motion"
                ),
                operatorName: .equals,
                right: .literalString("inactive")
            )
        )
        let condition = HomeAutomationCondition.and([
            contactClosed,
            .or([
                motionInactive,
                .not(contactClosed)
            ])
        ])
        let draft = ruleDraft(
            condition: condition,
            actionDescriptions: ["Turn on bedroom lamp"]
        )
        let action = resolvedAction(
            "Turn on bedroom lamp",
            deviceID: "bedroom_lamp",
            capability: "switch",
            command: "on"
        )

        let result = try await AutomationValidationAgent().run(
            AutomationValidationInput(ruleDraft: draft, resolvedActions: [action]),
            context: context()
        )

        #expect(result.status == .valid)
        #expect(draft.condition == condition)
    }

    private func ruleDraft(
        trigger: HomeAutomationTrigger? = .schedule(
            HomeAutomationScheduleTrigger(
                repeatRule: .everyDay,
                timeOfDay: HomeAutomationTimeOfDay(hour: 7, minute: 0)
            )
        ),
        condition: HomeAutomationCondition? = nil,
        actionDescriptions: [String]
    ) -> HomeAutomationRuleDraft {
        HomeAutomationRuleDraft(
            name: "Test automation",
            trigger: trigger,
            condition: condition,
            actionDescriptions: actionDescriptions,
            confidence: 0.9
        )
    }

    private func resolvedAction(
        _ originalText: String,
        deviceID: String,
        capability: String,
        command: String,
        deviceType: String = "switch",
        riskLevel: HomeAutomationRiskLevel = .low
    ) -> HomeAutomationResolvedAction {
        HomeAutomationResolvedAction(
            originalText: originalText,
            draft: HomeCommandDraft(
                intent: command == "on" ? .turnOn : command == "off" ? .turnOff : .unlock,
                targetDeviceID: deviceID,
                capability: capability,
                command: command,
                needsClarification: false,
                requiresConfirmation: riskLevel == .high || riskLevel == .critical,
                confidence: 0.92
            ),
            device: HomeCandidateRecord(
                id: deviceID,
                displayName: deviceID,
                deviceType: deviceType,
                room: nil,
                capabilities: [capability],
                supportedCommands: [capability: [command]],
                riskLevel: riskLevel
            ),
            confidence: 0.92
        )
    }

    private func context() -> ResolutionContext {
        ResolutionContext(
            request: CommandRequest(text: "Create automation", executeLowRiskCommands: false)
        )
    }
}
