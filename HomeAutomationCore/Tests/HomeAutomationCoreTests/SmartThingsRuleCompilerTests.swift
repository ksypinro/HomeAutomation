import Foundation
import HomeAutomationCore
import Testing

@Suite
struct SmartThingsRuleCompilerTests {
    @Test
    func dailyScheduleCompilesToSpecificMidnightOffsetRule() throws {
        let document = try SmartThingsRuleCompiler().compile(
            makePlan(
                trigger: .schedule(
                    HomeAutomationScheduleTrigger(
                        repeatRule: .everyDay,
                        timeOfDay: HomeAutomationTimeOfDay(hour: 7, minute: 0)
                    )
                ),
                actions: [
                    resolvedAction("turn on bedroom AC", deviceID: "bedroom_ac", capability: "switch", command: "on")
                ]
            )
        )

        let root = try jsonObject(document)
        #expect(root["name"] as? String == "Test automation")
        let every = try firstEveryAction(root)
        let specific = try #require(every["specific"] as? [String: Any])
        #expect(specific["reference"] as? String == "Midnight")
        let offset = try #require(specific["offset"] as? [String: Any])
        let value = try #require(offset["value"] as? [String: Any])
        #expect(value["integer"] as? Int == 420)
        #expect(offset["unit"] as? String == "Minute")

        let command = try firstCommand(in: every)
        #expect(command.devices == ["bedroom_ac"])
        #expect(command.command["capability"] as? String == "switch")
        #expect(command.command["command"] as? String == "on")
        #expect(document.payload?.actions.count == 1)
    }

    @Test
    func multipleCommandActionsPreserveOrder() throws {
        let document = try SmartThingsRuleCompiler().compile(
            makePlan(
                trigger: .schedule(
                    HomeAutomationScheduleTrigger(
                        repeatRule: .everyDay,
                        timeOfDay: HomeAutomationTimeOfDay(hour: 18, minute: 30)
                    )
                ),
                actions: [
                    resolvedAction("turn on bedroom AC", deviceID: "bedroom_ac", capability: "switch", command: "on"),
                    resolvedAction("turn off bedroom lamp", deviceID: "bedroom_lamp", capability: "switch", command: "off")
                ]
            )
        )

        let every = try firstEveryAction(jsonObject(document))
        let actions = try #require(every["actions"] as? [[String: Any]])

        let firstCommand = try commandAction(actions[0])
        let secondCommand = try commandAction(actions[1])
        #expect(firstCommand.devices == ["bedroom_ac"])
        #expect(firstCommand.command["command"] as? String == "on")
        #expect(secondCommand.devices == ["bedroom_lamp"])
        #expect(secondCommand.command["command"] as? String == "off")
    }

    @Test
    func andOrNotConditionsCompileRecursivelyAsPreconditions() throws {
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
        let motionActive = HomeAutomationCondition.comparison(
            HomeAutomationComparisonCondition(
                left: .deviceAttribute(
                    description: "hallway motion sensor",
                    deviceID: "hallway_motion_sensor",
                    capability: "motionSensor",
                    attribute: "motion"
                ),
                operatorName: .equals,
                right: .literalString("active")
            )
        )
        let notUnlocked = HomeAutomationCondition.not(
            .comparison(
                HomeAutomationComparisonCondition(
                    left: .deviceAttribute(
                        description: "front door lock",
                        deviceID: "front_door_lock",
                        capability: "lock",
                        attribute: "lock"
                    ),
                    operatorName: .equals,
                    right: .literalString("unlocked")
                )
            )
        )

        let document = try SmartThingsRuleCompiler().compile(
            makePlan(
                trigger: .schedule(
                    HomeAutomationScheduleTrigger(
                        repeatRule: .everyDay,
                        timeOfDay: HomeAutomationTimeOfDay(hour: 7, minute: 0)
                    )
                ),
                condition: .and([
                    contactClosed,
                    .or([motionActive, notUnlocked])
                ]),
                actions: [
                    resolvedAction("turn on bedroom AC", deviceID: "bedroom_ac", capability: "switch", command: "on")
                ]
            )
        )

        let every = try firstEveryAction(jsonObject(document))
        let actions = try #require(every["actions"] as? [[String: Any]])
        let ifAction = try #require(actions.first?["if"] as? [String: Any])
        let andConditions = try #require(ifAction["and"] as? [[String: Any]])
        #expect(andConditions.count == 2)
        #expect(ifAction["then"] != nil)

        let contactEquals = try #require(andConditions.first?["equals"] as? [String: Any])
        let left = try #require(contactEquals["left"] as? [String: Any])
        let device = try #require(left["device"] as? [String: Any])
        #expect(device["trigger"] as? String == "Never")

        let orCondition = try #require(andConditions[1]["or"] as? [[String: Any]])
        #expect(orCondition.count == 2)
        #expect(orCondition[1]["not"] != nil)
    }

    @Test
    func betweenConditionCompilesToSmartThingsBetweenShape() throws {
        let document = try SmartThingsRuleCompiler().compile(
            makePlan(
                trigger: .schedule(
                    HomeAutomationScheduleTrigger(
                        repeatRule: .everyDay,
                        timeOfDay: HomeAutomationTimeOfDay(hour: 7, minute: 0)
                    )
                ),
                condition: .comparison(
                    HomeAutomationComparisonCondition(
                        left: .deviceAttribute(
                            description: "bedroom lamp level",
                            deviceID: "bedroom_lamp",
                            capability: "switchLevel",
                            attribute: "level"
                        ),
                        operatorName: .between,
                        right: .literalRange(start: 20, end: 80, unit: nil)
                    )
                ),
                actions: [
                    resolvedAction("turn on bedroom AC", deviceID: "bedroom_ac", capability: "switch", command: "on")
                ]
            )
        )

        let every = try firstEveryAction(jsonObject(document))
        let actions = try #require(every["actions"] as? [[String: Any]])
        let ifAction = try #require(actions.first?["if"] as? [String: Any])
        let between = try #require(ifAction["between"] as? [String: Any])
        let value = try #require(between["value"] as? [String: Any])
        let device = try #require(value["device"] as? [String: Any])
        #expect(device["capability"] as? String == "switchLevel")
        #expect(device["attribute"] as? String == "level")
        #expect(device["trigger"] as? String == "Never")
        let start = try #require(between["start"] as? [String: Any])
        let end = try #require(between["end"] as? [String: Any])
        #expect(start["integer"] as? Int == 20)
        #expect(end["integer"] as? Int == 80)
    }

    @Test
    func changesConditionCompilesToSmartThingsChangesShape() throws {
        let triggerCondition = HomeAutomationCondition.changes(
            .comparison(
                HomeAutomationComparisonCondition(
                    left: .deviceAttribute(
                        description: "hallway motion sensor",
                        deviceID: "hallway_motion_sensor",
                        capability: "motionSensor",
                        attribute: "motion"
                    ),
                    operatorName: .equals,
                    right: .literalString("active"),
                    triggerPolicy: .always
                )
            )
        )

        let document = try SmartThingsRuleCompiler().compile(
            makePlan(
                trigger: .device(
                    HomeAutomationDeviceTrigger(
                        description: "hallway motion sensor changes to active",
                        condition: triggerCondition
                    )
                ),
                actions: [
                    resolvedAction("turn on bedroom lamp", deviceID: "bedroom_lamp", capability: "switch", command: "on")
                ]
            )
        )

        let root = try jsonObject(document)
        let actions = try #require(root["actions"] as? [[String: Any]])
        let ifAction = try #require(actions.first?["if"] as? [String: Any])
        let changes = try #require(ifAction["changes"] as? [String: Any])
        let equals = try #require(changes["equals"] as? [String: Any])
        let left = try #require(equals["left"] as? [String: Any])
        let device = try #require(left["device"] as? [String: Any])
        #expect(device["capability"] as? String == "motionSensor")
        #expect(device["attribute"] as? String == "motion")
        #expect(device["trigger"] as? String == "Always")
        #expect(ifAction["then"] != nil)
    }

    @Test
    func unsupportedWeekdayScheduleReturnsTypedError() throws {
        let plan = makePlan(
            trigger: .schedule(
                HomeAutomationScheduleTrigger(
                    repeatRule: .daysOfWeek([.monday]),
                    timeOfDay: HomeAutomationTimeOfDay(hour: 7, minute: 0)
                )
            ),
            actions: [
                resolvedAction("turn on bedroom AC", deviceID: "bedroom_ac", capability: "switch", command: "on")
            ]
        )

        do {
            _ = try SmartThingsRuleCompiler().compile(plan)
            Issue.record("Expected unsupported weekday schedule error")
        } catch let error as SmartThingsRuleCompileError {
            #expect(error == .unsupportedSchedule(.daysOfWeek([.monday])))
        }
    }

    @Test
    func unresolvedConditionOperandReturnsTypedError() throws {
        let plan = makePlan(
            trigger: .schedule(
                HomeAutomationScheduleTrigger(
                    repeatRule: .everyDay,
                    timeOfDay: HomeAutomationTimeOfDay(hour: 7, minute: 0)
                )
            ),
            condition: .comparison(
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
            ),
            actions: [
                resolvedAction("turn on bedroom AC", deviceID: "bedroom_ac", capability: "switch", command: "on")
            ]
        )

        do {
            _ = try SmartThingsRuleCompiler().compile(plan)
            Issue.record("Expected unresolved condition operand error")
        } catch let error as SmartThingsRuleCompileError {
            #expect(error == .unresolvedConditionOperand("bedroom window"))
        }
    }

    private func makePlan(
        trigger: HomeAutomationTrigger,
        condition: HomeAutomationCondition? = nil,
        actions: [HomeAutomationResolvedAction]
    ) -> HomeAutomationCreationPlan {
        let draft = HomeAutomationRuleDraft(
            name: "Test automation",
            trigger: trigger,
            condition: condition,
            actionDescriptions: actions.map(\.originalText),
            confidence: 0.93
        )
        return HomeAutomationCreationPlan(
            name: draft.name,
            ruleDraft: draft,
            resolvedActions: actions,
            smartThingsRuleJSON: nil,
            requiresConfirmation: false,
            unsupportedCompilationReason: nil
        )
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
                confidence: 0.94
            ),
            device: HomeCandidateRecord(
                id: deviceID,
                displayName: deviceID,
                deviceType: "switch",
                room: nil,
                capabilities: [capability],
                supportedCommands: [capability: [command]]
            ),
            confidence: 0.94
        )
    }

    private func jsonObject(_ document: SmartThingsRuleDocument) throws -> [String: Any] {
        let data = try #require(document.jsonString.data(using: .utf8))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func firstEveryAction(_ root: [String: Any]) throws -> [String: Any] {
        let actions = try #require(root["actions"] as? [[String: Any]])
        return try #require(actions.first?["every"] as? [String: Any])
    }

    private func firstCommand(in every: [String: Any]) throws -> (devices: [String], command: [String: Any]) {
        let actions = try #require(every["actions"] as? [[String: Any]])
        return try commandAction(try #require(actions.first))
    }

    private func commandAction(_ action: [String: Any]) throws -> (devices: [String], command: [String: Any]) {
        let commandAction = try #require(action["command"] as? [String: Any])
        let devices = try #require(commandAction["devices"] as? [String])
        let commands = try #require(commandAction["commands"] as? [[String: Any]])
        return (devices, try #require(commands.first))
    }
}
