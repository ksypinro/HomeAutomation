import Foundation
import HomeAutomationCore
import HomeAutomationRAG

public enum EvaluationCorpus {
    public static let defaultCases: [EvaluationCase] = [
        EvaluationCase(
            id: "operation-routing.daily-ac",
            suite: "operation-routing",
            tags: ["automation", "schedule"],
            input: "Turn on bedroom AC every day at 7 AM",
            expected: EvaluationExpectedOutput(
                operation: .automationCreation,
                domain: .homeAutomation,
                languageCode: "en",
                expectedDeviceIDs: ["bedroom_ac"],
                actionCount: 1,
                allowedOutcome: .drafted
            )
        ),
        EvaluationCase(
            id: "semantic-nlu.turn-on-ac",
            suite: "semantic-nlu",
            tags: ["direct-command", "device-type"],
            input: "Turn on bedroom AC",
            expected: EvaluationExpectedOutput(
                expectedDeviceIDs: ["bedroom_ac"],
                capability: "switch",
                command: "on",
                allowedOutcome: .ready
            )
        ),
        EvaluationCase(
            id: "candidate-filtering.numbered-bulb",
            suite: "candidate-filtering",
            tags: ["direct-command", "numbered-device-name"],
            input: "Turn on bulb 2",
            fixture: EvaluationFixture(devices: numberedBulbs),
            expected: EvaluationExpectedOutput(
                expectedDeviceIDs: ["bulb_2"],
                capability: "switch",
                command: "on",
                allowedOutcome: .ready
            )
        ),
        EvaluationCase(
            id: "capability-command.bedroom-lamp-off",
            suite: "capability-command",
            tags: ["direct-command", "switch"],
            input: "Turn off the bedroom lamp",
            expected: EvaluationExpectedOutput(
                expectedDeviceIDs: ["bedroom_lamp"],
                capability: "switch",
                command: "off",
                allowedOutcome: .ready
            )
        ),
        EvaluationCase(
            id: "automation-segmentation.two-actions-two-conditions",
            suite: "automation-segmentation",
            tags: ["automation", "fan-out"],
            input: "Turn on bedroom AC and turn off the bedroom lamp every day at 7 AM if living room ceiling light is off and living room tv is off",
            expected: EvaluationExpectedOutput(
                expectedDeviceIDs: ["bedroom_ac", "bedroom_lamp"],
                actionCount: 2,
                conditionCount: 3,
                allowedOutcome: .drafted
            )
        ),
        EvaluationCase(
            id: "trigger-resolution.daily-time",
            suite: "trigger-resolution",
            tags: ["automation", "schedule"],
            input: "Turn on bedroom AC everyday at 7 AM",
            expected: EvaluationExpectedOutput(
                expectedDeviceIDs: ["bedroom_ac"],
                actionCount: 1,
                allowedOutcome: .drafted
            )
        ),
        EvaluationCase(
            id: "condition-resolution.entry-contact",
            suite: "condition-resolution",
            tags: ["automation", "condition"],
            input: "Turn on bedroom AC everyday at 7 AM if the entry contact sensor is closed",
            expected: EvaluationExpectedOutput(
                expectedDeviceIDs: ["bedroom_ac"],
                actionCount: 1,
                conditionCount: 1,
                allowedOutcome: .drafted
            )
        ),
        EvaluationCase(
            id: "smartthings-compilation.daily-schedule",
            suite: "smartthings-compilation",
            tags: ["automation", "smartthings"],
            input: "Turn on bedroom AC every day at 7 AM",
            expected: EvaluationExpectedOutput(
                expectedDeviceIDs: ["bedroom_ac"],
                actionCount: 1,
                allowedOutcome: .drafted
            )
        ),
        EvaluationCase(
            id: "rag-retrieval.smartthings-every-specific",
            suite: "rag-retrieval",
            tags: ["rag", "smartthings"],
            input: "SmartThings daily schedule rule with every specific actions",
            expected: EvaluationExpectedOutput(
                smartThingsJSONContains: [KnowledgeSource.smartThingsRuleSchema.rawValue],
                allowedOutcome: .ready
            )
        ),
        EvaluationCase(
            id: "end-to-end-direct-command.lamp-on",
            suite: "end-to-end-direct-command",
            tags: ["direct-command"],
            input: "Turn on the bedroom lamp",
            expected: EvaluationExpectedOutput(
                expectedDeviceIDs: ["bedroom_lamp"],
                capability: "switch",
                command: "on",
                allowedOutcome: .ready
            )
        ),
        EvaluationCase(
            id: "end-to-end-automation.or-condition",
            suite: "end-to-end-automation",
            tags: ["automation", "condition-tree"],
            input: "Turn on bedroom AC and turn off the bedroom lamp every day at 7 AM if front door is locked or living room light is off",
            expected: EvaluationExpectedOutput(
                expectedDeviceIDs: ["bedroom_ac", "bedroom_lamp"],
                actionCount: 2,
                conditionCount: 3,
                allowedOutcome: .drafted
            )
        ),
        EvaluationCase(
            id: "observability-contract.direct-command",
            suite: "observability-contract",
            tags: ["observability", "metrics-v2"],
            input: "Turn on the bedroom lamp",
            expected: EvaluationExpectedOutput(
                expectedDeviceIDs: ["bedroom_lamp"],
                capability: "switch",
                command: "on",
                allowedOutcome: .ready
            )
        )
    ]

    private static let numberedBulbs: [HomeCandidateRecord] = [
        numberedBulb(id: "bulb_1", displayName: "Bulb 1"),
        numberedBulb(id: "bulb_2", displayName: "Bulb 2"),
        numberedBulb(id: "bulb_3", displayName: "Bulb 3")
    ]

    private static func numberedBulb(id: String, displayName: String) -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: id,
            displayName: displayName,
            deviceType: "light",
            room: "living room",
            capabilities: ["switch"],
            supportedCommands: ["switch": ["on", "off"]],
            supportedModes: ["on", "off"],
            currentState: ["switch": "off"]
        )
    }
}
