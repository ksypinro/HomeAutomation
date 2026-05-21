import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite
struct Phase4AutomationContextTests {
    @Test
    func nestedConditionTreeCanRepresentAndOrNotLogic() throws {
        let doorClosed = HomeAutomationCondition.comparison(
            HomeAutomationComparisonCondition(
                left: .deviceAttribute(
                    description: "front door",
                    deviceID: "front_door_sensor",
                    capability: "contactSensor",
                    attribute: "contact"
                ),
                operatorName: .equals,
                right: .literalString("closed")
            )
        )
        let motionDetected = HomeAutomationCondition.comparison(
            HomeAutomationComparisonCondition(
                left: .deviceAttribute(
                    description: "hallway motion",
                    deviceID: "hallway_motion",
                    capability: "motionSensor",
                    attribute: "motion"
                ),
                operatorName: .equals,
                right: .literalString("active")
            )
        )
        let awayMode = HomeAutomationCondition.comparison(
            HomeAutomationComparisonCondition(
                left: .locationMode("mode"),
                operatorName: .equals,
                right: .literalString("Away")
            )
        )
        let condition = HomeAutomationCondition.and([
            doorClosed,
            .or([
                motionDetected,
                .not(awayMode)
            ])
        ])

        let data = try JSONEncoder().encode(condition)
        let decoded = try JSONDecoder().decode(HomeAutomationCondition.self, from: data)

        #expect(decoded == condition)
    }

    @Test
    func ruleDraftCanRepresentMultipleActionDescriptions() {
        let draft = HomeAutomationRuleDraft(
            name: "Morning comfort",
            trigger: .schedule(
                HomeAutomationScheduleTrigger(
                    repeatRule: .everyDay,
                    timeOfDay: HomeAutomationTimeOfDay(hour: 7, minute: 0),
                    timezoneIdentifier: "Asia/Dhaka"
                )
            ),
            condition: .comparison(
                HomeAutomationComparisonCondition(
                    left: .deviceAttribute(
                        description: "bedroom temperature",
                        deviceID: "bedroom_ac",
                        capability: "temperatureMeasurement",
                        attribute: "temperature"
                    ),
                    operatorName: .greaterThan,
                    right: .literalNumber(25, unit: "celsius")
                )
            ),
            actionDescriptions: [
                "turn on bedroom AC",
                "set bedroom lamp to 40 percent"
            ],
            confidence: 0.9
        )

        #expect(draft.intent == .createAutomation)
        #expect(draft.actionDescriptions.count == 2)
        #expect(draft.trigger?.displayString == "every day at 7:00 AM")
    }

    @Test
    func creationPlanCanCarryMultipleResolvedActions() {
        let draft = HomeAutomationRuleDraft(
            name: "Evening setup",
            trigger: .schedule(
                HomeAutomationScheduleTrigger(
                    repeatRule: .everyDay,
                    timeOfDay: HomeAutomationTimeOfDay(hour: 18, minute: 30)
                )
            ),
            condition: nil,
            actionDescriptions: [
                "turn on bedroom lamp",
                "turn on bedroom AC"
            ],
            confidence: 0.88
        )
        let actions = [
            resolvedAction("turn on bedroom lamp", deviceID: "bedroom_lamp", capability: "switch", command: "on"),
            resolvedAction("turn on bedroom AC", deviceID: "bedroom_ac", capability: "switch", command: "on")
        ]
        let plan = HomeAutomationCreationPlan(
            name: draft.name,
            ruleDraft: draft,
            resolvedActions: actions,
            smartThingsRuleJSON: #"{"name":"Evening setup"}"#,
            requiresConfirmation: false,
            unsupportedCompilationReason: nil
        )

        #expect(plan.resolvedActions.map(\.draft.targetDeviceID) == ["bedroom_lamp", "bedroom_ac"])
        #expect(plan.smartThingsRuleJSON != nil)
    }

    @Test
    func automationResolutionContextStoreKeepsAutomationStateSeparate() async {
        let request = CommandRequest(text: "Turn on AC everyday at 7 AM", executeLowRiskCommands: false)
        let operation = HomeOperationDetectionResult(
            domain: .homeAutomation,
            operation: .automationCreation,
            confidence: 0.92,
            reason: "schedule matched"
        )
        let store = AutomationResolutionContextStore(request: request, operation: operation)
        let draft = HomeAutomationRuleDraft(
            name: "Turn on AC at 7:00 AM",
            trigger: .schedule(
                HomeAutomationScheduleTrigger(
                    repeatRule: .everyDay,
                    timeOfDay: HomeAutomationTimeOfDay(hour: 7, minute: 0)
                )
            ),
            condition: nil,
            actionDescriptions: ["turn on AC"],
            confidence: 0.86
        )
        let validation = AutomationValidationResult(
            issues: [
                AutomationValidationIssue(
                    code: "smartthings.preview",
                    message: "Compilation is a draft.",
                    severity: .warning
                )
            ],
            requiresConfirmation: false
        )
        let traceStart = Date()

        await store.setDraft(draft)
        await store.appendResolvedAction(
            resolvedAction("turn on AC", deviceID: "bedroom_ac", capability: "switch", command: "on")
        )
        await store.setValidation(validation)
        await store.setSmartThingsRule(SmartThingsRuleDocument(name: draft.name, jsonString: #"{"name":"Turn on AC"}"#))
        await store.setResolution(
            .drafted(
                HomeAutomationCreationPlan(
                    name: draft.name,
                    ruleDraft: draft,
                    resolvedActions: [],
                    smartThingsRuleJSON: #"{"name":"Turn on AC"}"#,
                    requiresConfirmation: false,
                    unsupportedCompilationReason: nil
                )
            )
        )
        await store.appendTrace(
            AgentTraceEntry(
                agentID: .automationDraft,
                startedAt: traceStart,
                endedAt: Date(),
                result: .success
            )
        )

        let snapshot = await store.snapshot()

        #expect(snapshot.request.text == request.text)
        #expect(snapshot.operation.operation == .automationCreation)
        #expect(snapshot.draft == draft)
        #expect(snapshot.resolvedActions.count == 1)
        #expect(snapshot.validation == validation)
        #expect(snapshot.smartThingsRule?.name == draft.name)
        #expect(snapshot.trace.map(\.agentID) == [.automationDraft])
    }

    @Test
    func scopedContextPreservesRootDirectCommandFields() async {
        let store = ResolutionContextStore(
            request: CommandRequest(text: "Turn on the TV", executeLowRiskCommands: false)
        )
        let rootDraft = HomeCommandDraft(
            intent: .turnOn,
            targetDeviceID: "living_room_tv",
            capability: "switch",
            command: "on",
            needsClarification: false,
            requiresConfirmation: false,
            confidence: 0.91
        )
        let scopedDraft = HomeCommandDraft(
            intent: .turnOff,
            targetDeviceID: "bedroom_lamp",
            capability: "switch",
            command: "off",
            needsClarification: false,
            requiresConfirmation: false,
            confidence: 0.88
        )
        let language = HomeLanguageDetectionResult(
            languageCode: "en",
            isMixedLanguage: false,
            confidence: 0.99,
            unsupportedLanguageLikely: false
        )
        let key = ScopedContextKeys.commandDraft(in: .action("a1"))

        await store.apply(
            ResolutionContextPatch(
                agentID: .operationDetection,
                updates: [
                    ResolutionContextPatchKey.language.rawValue: AnySendableValue(language),
                    ResolutionContextPatchKey.draft.rawValue: AnySendableValue(rootDraft)
                ],
                scopedUpdates: [
                    .action("a1"): [key.name: AnySendableValue(scopedDraft)]
                ]
            )
        )

        let snapshot = await store.snapshot()

        #expect(snapshot.language == language)
        #expect(snapshot.draft == rootDraft)
        #expect(snapshot.scopedValue(for: key) == scopedDraft)
    }

    @Test
    func actionScopesDoNotOverwriteEachOther() async {
        let store = ResolutionContextStore(
            request: CommandRequest(text: "Turn on lamp and turn off AC every day at 7 AM", executeLowRiskCommands: false)
        )
        let actionOne = HomeCommandDraft(
            intent: .turnOn,
            targetDeviceID: "bedroom_lamp",
            capability: "switch",
            command: "on",
            needsClarification: false,
            requiresConfirmation: false,
            confidence: 0.93
        )
        let actionTwo = HomeCommandDraft(
            intent: .turnOff,
            targetDeviceID: "bedroom_ac",
            capability: "switch",
            command: "off",
            needsClarification: false,
            requiresConfirmation: false,
            confidence: 0.9
        )
        let actionOneKey = ScopedContextKeys.commandDraft(in: .action("a1"))
        let actionTwoKey = ScopedContextKeys.commandDraft(in: .action("a2"))

        await store.apply(
            ResolutionContextPatch(
                agentID: .automationActionResolution,
                scopedUpdates: [
                    .action("a1"): [actionOneKey.name: AnySendableValue(actionOne)],
                    .action("a2"): [actionTwoKey.name: AnySendableValue(actionTwo)]
                ]
            )
        )

        let snapshot = await store.snapshot()

        #expect(snapshot.draft == nil)
        #expect(snapshot.scopedValue(for: actionOneKey) == actionOne)
        #expect(snapshot.scopedValue(for: actionTwoKey) == actionTwo)
    }

    @Test
    func conditionScopesDoNotOverwriteEachOther() async {
        let store = ResolutionContextStore(
            request: CommandRequest(text: "Turn on light if door is closed or motion is active", executeLowRiskCommands: false)
        )
        let conditionOne = comparisonCondition(
            description: "front door",
            deviceID: "front_door_sensor",
            capability: "contactSensor",
            attribute: "contact",
            value: "closed"
        )
        let conditionTwo = comparisonCondition(
            description: "hallway motion",
            deviceID: "hallway_motion",
            capability: "motionSensor",
            attribute: "motion",
            value: "active"
        )
        let conditionOneKey = ScopedContextKeys.automationCondition(in: .condition("c1"))
        let conditionTwoKey = ScopedContextKeys.automationCondition(in: .condition("c2"))

        await store.setScopedValue(conditionOne, for: conditionOneKey)
        await store.setScopedValue(conditionTwo, for: conditionTwoKey)

        let snapshot = await store.snapshot()

        #expect(snapshot.scopedValue(for: conditionOneKey) == conditionOne)
        #expect(snapshot.scopedValue(for: conditionTwoKey) == conditionTwo)
    }

    @Test
    func directCommandResolutionContextIsNotExpandedWithAutomationOnlyFields() {
        let context = ResolutionContext(
            request: CommandRequest(text: "Turn on the TV", executeLowRiskCommands: false)
        )
        let labels = Set(Mirror(reflecting: context).children.compactMap(\.label))

        #expect(!labels.contains("resolvedActions"))
        #expect(!labels.contains("smartThingsRule"))
        #expect(!labels.contains("validation"))
    }

    private func resolvedAction(
        _ originalText: String,
        deviceID: String,
        capability: String,
        command: String
    ) -> HomeAutomationResolvedAction {
        HomeAutomationResolvedAction(
            originalText: originalText,
            draft: HomeCommandDraft(
                intent: command == "on" ? .turnOn : .turnOff,
                targetDeviceID: deviceID,
                capability: capability,
                command: command,
                needsClarification: false,
                requiresConfirmation: false,
                confidence: 0.93
            ),
            device: HomeCandidateRecord(
                id: deviceID,
                displayName: deviceID,
                deviceType: "switch",
                room: nil,
                capabilities: [capability],
                supportedCommands: [capability: [command]]
            ),
            confidence: 0.93
        )
    }

    private func comparisonCondition(
        description: String,
        deviceID: String,
        capability: String,
        attribute: String,
        value: String
    ) -> HomeAutomationCondition {
        .comparison(
            HomeAutomationComparisonCondition(
                left: .deviceAttribute(
                    description: description,
                    deviceID: deviceID,
                    capability: capability,
                    attribute: attribute
                ),
                operatorName: .equals,
                right: .literalString(value)
            )
        )
    }
}
