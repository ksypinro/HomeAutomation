import Foundation
import HomeAutomationCore

public struct DocumentChunker: Sendable {
    public init() {}

    public func capabilityChunks(
        definitions: [String: HomeCapabilityDefinition] = HomeCapabilityRegistry.definitions
    ) -> [DocumentChunk] {
        definitions
            .keys
            .sorted()
            .compactMap { capabilityID in
                guard let definition = definitions[capabilityID] else { return nil }
                let content = [
                    "Capability \(definition.id)",
                    "Display name \(definition.displayName)",
                    "Commands \(definition.commands.joined(separator: " "))",
                    "Attributes \(definition.attributeNames.joined(separator: " "))",
                    "Enum values \(definition.enumValues.joined(separator: " "))",
                    "Risk \(definition.riskLevel)"
                ].joined(separator: ". ")
                let semanticContent = [
                    definition.id,
                    definition.displayName,
                    definition.commands.joined(separator: " "),
                    definition.attributeNames.joined(separator: " "),
                    definition.enumValues.joined(separator: " ")
                ].joined(separator: " ")
                let relatedDeviceTypes = Self.relatedDeviceTypes(for: definition.id)

                return DocumentChunk(
                    id: "capability:\(definition.id)",
                    content: content,
                    semanticContent: semanticContent,
                    source: .capability,
                    metadata: [
                        "capabilityId": definition.id,
                        "commands": definition.commands.joined(separator: ","),
                        "risk": String(describing: definition.riskLevel),
                        "relatedDeviceTypes": relatedDeviceTypes.joined(separator: ",")
                    ]
                )
            }
    }

    public func deviceChunks(devices: [HomeCandidateRecord]) -> [DocumentChunk] {
        devices.map { device in
            let content = [
                "Device \(device.displayName)",
                "ID \(device.id)",
                "Type \(device.deviceType)",
                "Room \(device.room ?? "none")",
                "Capabilities \(device.capabilities.joined(separator: " "))",
                "Commands \(device.supportedCommands.map { "\($0.key) \($0.value.joined(separator: " "))" }.joined(separator: " "))",
                "Modes \(device.supportedModes.joined(separator: " "))",
                "State \(device.currentState.map { "\($0.key) \($0.value)" }.joined(separator: " "))",
                "Risk \(device.riskLevel)"
            ].joined(separator: ". ")
            let semanticContent = [
                device.displayName,
                device.deviceType,
                device.room ?? "",
                device.capabilities.joined(separator: " "),
                device.metadata["nickname"] ?? "",
                device.metadata["aliases"] ?? "",
                device.metadata["description"] ?? ""
            ].joined(separator: " ")

            return DocumentChunk(
                id: "device:\(device.id)",
                content: content,
                semanticContent: semanticContent,
                source: .device,
                metadata: [
                    "deviceId": device.id,
                    "room": device.room ?? "",
                    "deviceType": device.deviceType,
                    "capabilities": device.capabilities.joined(separator: ",")
                ]
            )
        }
    }

    public func bixbyCommandChunks(
        commands: [HomeBixbyVoiceCommand] = HomeBixbyCommandCatalog.commands
    ) -> [DocumentChunk] {
        commands.map { command in
            let content = [
                "Bixby command \(command.capabilityAction)",
                "Capability \(command.capability)",
                "Action \(command.action)",
                "Method \(command.method)",
                "Access \(command.accessLevel)",
                "Hint \(command.hint)"
            ].joined(separator: ". ")
            let semanticContent = [
                command.capabilityAction,
                command.capability,
                command.action,
                command.method,
                command.hint
            ].joined(separator: " ")
            let relatedDeviceTypes = Self.relatedDeviceTypes(for: command.capability)

            return DocumentChunk(
                id: "bixby:\(stableID(command.id))",
                content: content,
                semanticContent: semanticContent,
                source: .bixbyCommand,
                metadata: [
                    "capability": command.capability,
                    "action": command.action,
                    "method": command.method,
                    "relatedDeviceTypes": relatedDeviceTypes.joined(separator: ",")
                ]
            )
        }
    }

    public func nlDatasetChunks(
        examples: [HomeGeneratedCommandExample] = HomeAutomationKnowledgeBase.generatedDatasetCommands()
    ) -> [DocumentChunk] {
        examples.map { example in
            let content = [
                "Natural language example \(example.text)",
                "Language \(example.language)",
                "Device type \(example.deviceType)",
                "Device name \(example.deviceName)",
                "Room \(example.room)",
                "Capability \(example.capability)",
                "Command \(example.command)",
                "Intent \(example.intent)",
                "Risk \(example.riskLevel)"
            ].joined(separator: ". ")

            return DocumentChunk(
                id: "nl:\(example.id)",
                content: content,
                semanticContent: example.text,
                source: .nlDataset,
                metadata: [
                    "exampleId": example.id,
                    "language": example.language,
                    "deviceType": example.deviceType,
                    "capability": example.capability,
                    "command": example.command
                ]
            )
        }
    }

    public func automationChunks() -> [DocumentChunk] {
        automationPatternChunks() +
            automationRuleExampleChunks() +
            automationConditionOperatorChunks() +
            smartThingsRuleSchemaChunks()
    }

    public func automationPatternChunks() -> [DocumentChunk] {
        automationKnowledgeEntries(for: .automationPattern).map(makeAutomationChunk)
    }

    public func automationRuleExampleChunks() -> [DocumentChunk] {
        automationKnowledgeEntries(for: .automationRuleExample).map(makeAutomationChunk)
    }

    public func automationConditionOperatorChunks() -> [DocumentChunk] {
        automationKnowledgeEntries(for: .automationConditionOperator).map(makeAutomationChunk)
    }

    public func smartThingsRuleSchemaChunks() -> [DocumentChunk] {
        automationKnowledgeEntries(for: .smartThingsRuleSchema).map(makeAutomationChunk)
    }

    public func allChunks(devices: [HomeCandidateRecord]) -> [DocumentChunk] {
        capabilityChunks() +
            deviceChunks(devices: devices) +
            bixbyCommandChunks() +
            nlDatasetChunks() +
            automationChunks()
    }

    private func stableID(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func relatedDeviceTypes(for capabilityID: String) -> [String] {
        capabilityDeviceTypes()[capabilityID] ?? []
    }

    private static func capabilityDeviceTypes() -> [String: [String]] {
        var mapping: [String: Set<String>] = [:]
        let devices = MockHomeDeviceRegistry.defaultDevices + HomeAutomationKnowledgeBase.shared.makeCatalogDeviceRecords()
        for device in devices {
            for capability in device.capabilities {
                mapping[capability, default: []].insert(device.deviceType)
            }
        }
        return mapping.mapValues { $0.sorted() }
    }

    private func makeAutomationChunk(_ entry: AutomationKnowledgeEntry) -> DocumentChunk {
        let content = [
            entry.title,
            entry.content,
            "Concepts \(entry.concepts.joined(separator: " "))",
            "Condition operators \(entry.conditionOperators.joined(separator: " "))",
            "Repeat hints \(entry.repeatHints.joined(separator: " "))",
            "Schema keys \(entry.schemaKeys.joined(separator: " "))"
        ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: ". ")
        let semanticContent = [
            entry.title,
            entry.semanticContent,
            entry.concepts.joined(separator: " "),
            entry.conditionOperators.joined(separator: " "),
            entry.repeatHints.joined(separator: " "),
            entry.schemaKeys.joined(separator: " ")
        ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")

        return DocumentChunk(
            id: "\(entry.source.rawValue):\(stableID(entry.id))",
            content: content,
            semanticContent: semanticContent,
            source: entry.source,
            metadata: [
                "operation": HomeAutomationOperationKind.automationCreation.rawValue,
                "automationConcepts": entry.concepts.joined(separator: ","),
                "conditionOperators": entry.conditionOperators.joined(separator: ","),
                "repeatHints": entry.repeatHints.joined(separator: ","),
                "schemaKeys": entry.schemaKeys.joined(separator: ","),
                "patternKind": entry.patternKind
            ]
        )
    }

    private func automationKnowledgeEntries(for source: KnowledgeSource) -> [AutomationKnowledgeEntry] {
        Self.automationKnowledgeEntries.filter { $0.source == source }
    }

    private struct AutomationKnowledgeEntry: Sendable, Hashable {
        let id: String
        let source: KnowledgeSource
        let title: String
        let content: String
        let semanticContent: String
        let concepts: [String]
        let conditionOperators: [String]
        let repeatHints: [String]
        let schemaKeys: [String]
        let patternKind: String
    }

    private static let automationKnowledgeEntries: [AutomationKnowledgeEntry] = [
        AutomationKnowledgeEntry(
            id: "daily-schedule-pattern",
            source: .automationPattern,
            title: "Automation pattern daily schedule",
            content: "User commands such as turn on AC every day at 7 AM create an automation with a schedule trigger, repeatRule everyDay, time 07:00, and one or more actionDescriptions. Simple daily schedules do not need extra RAG context when parser confidence is high.",
            semanticContent: "daily schedule everyday every day at 7 AM turn on AC schedule trigger repeatRule everyDay time actionDescriptions",
            concepts: ["schedule", "dailySchedule", "automationCreation", "actionDescription"],
            conditionOperators: [],
            repeatHints: ["everyDay", "daily", "every day", "everyday"],
            schemaKeys: ["every", "specific", "command"],
            patternKind: "dailySchedule"
        ),
        AutomationKnowledgeEntry(
            id: "interval-schedule-pattern",
            source: .automationPattern,
            title: "Automation pattern interval schedule",
            content: "Commands such as run the purifier every 30 minutes or turn off the fan every 2 hours are interval schedule automations. Preserve interval value and unit separately from action text and keep actionDescriptions as immediate device commands.",
            semanticContent: "interval schedule every 30 minutes every 2 hours repeatRule interval value unit actionDescriptions",
            concepts: ["schedule", "intervalSchedule", "automationCreation", "repeatRule"],
            conditionOperators: [],
            repeatHints: ["interval", "minute", "minutes", "hour", "hours", "every 30 minutes"],
            schemaKeys: ["every", "specific", "command"],
            patternKind: "intervalSchedule"
        ),
        AutomationKnowledgeEntry(
            id: "weekday-unsupported-pattern",
            source: .automationPattern,
            title: "Automation pattern weekday schedule",
            content: "Commands mentioning weekdays, weekends, or every Monday can be parsed as daysOfWeek, but the current SmartThings compiler treats those repeat rules as unsupported until day-specific schedule compilation is added. Preserve the fragment for clarification or fallback.",
            semanticContent: "weekday schedule weekdays weekends every monday daysOfWeek unsupportedFragments unsupported schedule",
            concepts: ["schedule", "daysOfWeek", "unsupportedFragment", "automationCreation"],
            conditionOperators: [],
            repeatHints: ["weekdays", "weekends", "monday", "daysOfWeek"],
            schemaKeys: ["every", "specific"],
            patternKind: "weekdaySchedule"
        ),
        AutomationKnowledgeEntry(
            id: "device-trigger-pattern",
            source: .automationPattern,
            title: "Automation pattern device trigger",
            content: "Commands beginning with when or whenever should create a device trigger. The trigger condition uses triggerPolicy always, while additional if conditions are preconditions with triggerPolicy never.",
            semanticContent: "when whenever device trigger triggerPolicy always precondition never condition actionDescriptions",
            concepts: ["deviceTrigger", "precondition", "automationCreation", "triggerPolicy"],
            conditionOperators: ["equals", "changes"],
            repeatHints: [],
            schemaKeys: ["if", "then", "trigger", "command"],
            patternKind: "deviceTrigger"
        ),
        AutomationKnowledgeEntry(
            id: "device-attribute-condition-pattern",
            source: .automationPattern,
            title: "Automation pattern device attribute condition",
            content: "Device attribute conditions such as window is closed, motion is detected, temperature above 75, or switch is on should be represented as comparison conditions. The left operand is a deviceAttribute and the right operand is a literal string or number.",
            semanticContent: "device attribute condition window closed motion detected temperature above switch on comparison left deviceAttribute right literalString literalNumber",
            concepts: ["deviceAttribute", "comparisonCondition", "automationCreation", "precondition"],
            conditionOperators: ["equals", "greaterThan", "lessThan"],
            repeatHints: [],
            schemaKeys: ["if", "device", "trigger"],
            patternKind: "deviceAttributeCondition"
        ),
        AutomationKnowledgeEntry(
            id: "multiple-action-pattern",
            source: .automationPattern,
            title: "Automation pattern multiple actions",
            content: "A command may request multiple actions, for example turn on AC and turn off bedroom lamp every day at 7 AM. Keep each action as its own actionDescription so downstream direct-command agents can resolve each action independently.",
            semanticContent: "multiple actions turn on AC turn off bedroom lamp actionDescriptions downstream command agents resolve independently",
            concepts: ["multipleActions", "actionDescription", "automationCreation"],
            conditionOperators: [],
            repeatHints: ["everyDay"],
            schemaKeys: ["command"],
            patternKind: "multipleActions"
        ),
        AutomationKnowledgeEntry(
            id: "daily-rule-example",
            source: .automationRuleExample,
            title: "Automation rule example daily command",
            content: "Example: Turn on AC every day at 7 AM. Draft output should contain trigger schedule repeatRule everyDay time 07:00, no condition, and actionDescriptions containing Turn on AC. SmartThings output should wrap a command action inside every.specific.",
            semanticContent: "turn on AC every day at 7 AM trigger schedule repeatRule everyDay time 07:00 actionDescriptions SmartThings every specific command",
            concepts: ["schedule", "dailySchedule", "ruleExample", "automationCreation"],
            conditionOperators: [],
            repeatHints: ["everyDay", "daily"],
            schemaKeys: ["every", "specific", "command"],
            patternKind: "dailyRuleExample"
        ),
        AutomationKnowledgeEntry(
            id: "compound-condition-rule-example",
            source: .automationRuleExample,
            title: "Automation rule example compound condition",
            content: "Example: Turn on AC every day at 7 AM if bedroom window is closed and motion is detected. Draft output should use schedule trigger everyDay at 07:00, actionDescriptions Turn on AC, and condition and([window equals closed, motion equals active]).",
            semanticContent: "compound condition and window closed motion detected schedule trigger everyDay at 07:00 actionDescriptions",
            concepts: ["schedule", "compoundCondition", "deviceAttribute", "ruleExample", "automationCreation"],
            conditionOperators: ["and", "equals"],
            repeatHints: ["everyDay"],
            schemaKeys: ["if", "and", "then", "command"],
            patternKind: "compoundConditionRuleExample"
        ),
        AutomationKnowledgeEntry(
            id: "device-trigger-rule-example",
            source: .automationRuleExample,
            title: "Automation rule example device trigger",
            content: "Example: When the front door opens, turn on hallway light. Draft output should create a device trigger whose condition is front door equals open with triggerPolicy always, and one actionDescription turn on hallway light.",
            semanticContent: "when front door opens turn on hallway light device trigger equals open triggerPolicy always actionDescription",
            concepts: ["deviceTrigger", "ruleExample", "automationCreation", "triggerPolicy"],
            conditionOperators: ["equals", "changes"],
            repeatHints: [],
            schemaKeys: ["if", "then", "trigger", "command"],
            patternKind: "deviceTriggerRuleExample"
        ),
        AutomationKnowledgeEntry(
            id: "logical-condition-operators",
            source: .automationConditionOperator,
            title: "Automation condition operators and or not",
            content: "Use and and or to preserve grouped condition trees. Use not to invert a single child condition. Do not flatten and/or groups across different natural-language connectors because the command semantics can change.",
            semanticContent: "and or not preserve grouped condition tree logical condition operator invert child condition",
            concepts: ["compoundCondition", "conditionTree", "automationCreation"],
            conditionOperators: ["and", "or", "not"],
            repeatHints: [],
            schemaKeys: ["if", "then", "else"],
            patternKind: "logicalOperator"
        ),
        AutomationKnowledgeEntry(
            id: "between-condition-operator",
            source: .automationConditionOperator,
            title: "Automation condition operator between",
            content: "Use between for ranges such as temperature between 68 and 74 or level between 50 and 75. SmartThings represents this as between with value, start, and end operands.",
            semanticContent: "between condition operator temperature between 68 and 74 level between 50 and 75 value start end operands",
            concepts: ["rangeCondition", "deviceAttribute", "automationCreation"],
            conditionOperators: ["between"],
            repeatHints: [],
            schemaKeys: ["between", "value", "start", "end"],
            patternKind: "betweenOperator"
        ),
        AutomationKnowledgeEntry(
            id: "changes-condition-operator",
            source: .automationConditionOperator,
            title: "Automation condition operator changes",
            content: "Use changes when a rule should fire only when an inner comparison transitions from false to true, for example temperature changes to below 50. This prevents repeated execution while a value remains below or above a threshold.",
            semanticContent: "changes condition operator transition false true temperature changes below threshold repeated execution",
            concepts: ["transitionCondition", "deviceTrigger", "automationCreation"],
            conditionOperators: ["changes", "lessThan", "greaterThan"],
            repeatHints: [],
            schemaKeys: ["changes", "lessThan", "greaterThan"],
            patternKind: "changesOperator"
        ),
        AutomationKnowledgeEntry(
            id: "smartthings-every-specific-schema",
            source: .smartThingsRuleSchema,
            title: "SmartThings rule schema every specific",
            content: "SmartThings schedule rules use an every action with a specific operand, then an actions array. For a daily time trigger, compile repeatRule everyDay and time into every.specific and place resolved command actions in the nested actions array.",
            semanticContent: "SmartThings every specific schedule daily time trigger repeatRule everyDay actions array resolved command actions",
            concepts: ["smartThingsSchema", "schedule", "dailySchedule", "automationCreation"],
            conditionOperators: [],
            repeatHints: ["everyDay", "daily"],
            schemaKeys: ["every", "specific", "actions"],
            patternKind: "smartThingsEverySpecific"
        ),
        AutomationKnowledgeEntry(
            id: "smartthings-if-then-else-schema",
            source: .smartThingsRuleSchema,
            title: "SmartThings rule schema if then else",
            content: "SmartThings conditional rules use an if action containing a condition such as equals, and, or, not, between, or changes. The then array contains actions to execute, and else is optional.",
            semanticContent: "SmartThings if then else condition equals and or not between changes actions array",
            concepts: ["smartThingsSchema", "conditionTree", "automationCreation"],
            conditionOperators: ["equals", "and", "or", "not", "between", "changes"],
            repeatHints: [],
            schemaKeys: ["if", "then", "else"],
            patternKind: "smartThingsIfThenElse"
        ),
        AutomationKnowledgeEntry(
            id: "smartthings-command-schema",
            source: .smartThingsRuleSchema,
            title: "SmartThings rule schema command",
            content: "SmartThings command actions contain devices and commands. Each command includes component main, capability, command, and arguments. Automation action resolution must provide the device IDs, capability, and command before compilation.",
            semanticContent: "SmartThings command action devices commands component main capability command arguments resolved action device IDs",
            concepts: ["smartThingsSchema", "resolvedAction", "automationCreation"],
            conditionOperators: [],
            repeatHints: [],
            schemaKeys: ["command", "devices", "commands", "component", "capability", "arguments"],
            patternKind: "smartThingsCommand"
        ),
        AutomationKnowledgeEntry(
            id: "smartthings-trigger-policy-schema",
            source: .smartThingsRuleSchema,
            title: "SmartThings rule schema trigger policy",
            content: "SmartThings device operands can specify trigger Always or Never. Use Always for the event that starts a device-triggered automation and Never for preconditions that should only gate execution.",
            semanticContent: "SmartThings trigger policy Always Never device operand trigger precondition gate execution",
            concepts: ["smartThingsSchema", "triggerPolicy", "deviceTrigger", "precondition", "automationCreation"],
            conditionOperators: ["equals", "changes"],
            repeatHints: [],
            schemaKeys: ["trigger", "Always", "Never", "device"],
            patternKind: "smartThingsTriggerPolicy"
        )
    ]
}
