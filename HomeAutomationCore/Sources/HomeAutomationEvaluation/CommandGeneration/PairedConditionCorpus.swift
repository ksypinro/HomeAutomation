import Foundation
import HomeAutomationCore

/// Phase 0 paired-condition corpus: each conditioned automation paired with an identical no-condition twin.
/// Used by OrchestrationComparisonRunner to measure condition-specific overhead.
public struct PairedConditionCase: Sendable, Codable, Identifiable {
    public let id: String

    /// Base command without condition (e.g., "turn on the AC at 7 AM").
    public let baseCommand: String

    /// Same command with one or more conditions appended (e.g., "turn on the AC at 7 AM but only if temperature is above 26").
    public let conditionedCommand: String

    /// Number of condition leaves in the conditioned version.
    public let conditionLeafCount: Int

    /// Condition form: "state" | "comparison" | "range" | "changes" | "mixed".
    public let conditionForm: String

    /// Device resolution expectation: "unique" | "ambiguous" | "missing" | "unsupported".
    public let conditionResolution: String

    /// Condition tree structure: "leaf" | "and" | "or" | "not" | "mixed".
    public let conditionTree: String

    /// Number of actions in both versions.
    public let actionCount: Int

    /// Trigger type: "schedule" | "device".
    public let triggerType: String

    /// Risk level: "low" | "medium" | "high".
    public let riskLevel: String

    /// Device registry size hint: "small" | "medium" | "large".
    public let registrySize: String

    /// Expected condition completeness if fully resolved: "complete" | "partial" | "ambiguous" | "unsupported".
    public let expectedCompleteness: String

    /// Expected deterministic acceptance (true if completeness=complete and all checks pass deterministically).
    public let expectedDeterministicAcceptance: Bool

    public init(
        id: String,
        baseCommand: String,
        conditionedCommand: String,
        conditionLeafCount: Int,
        conditionForm: String,
        conditionResolution: String,
        conditionTree: String,
        actionCount: Int,
        triggerType: String,
        riskLevel: String,
        registrySize: String,
        expectedCompleteness: String,
        expectedDeterministicAcceptance: Bool
    ) {
        self.id = id
        self.baseCommand = baseCommand
        self.conditionedCommand = conditionedCommand
        self.conditionLeafCount = conditionLeafCount
        self.conditionForm = conditionForm
        self.conditionResolution = conditionResolution
        self.conditionTree = conditionTree
        self.actionCount = actionCount
        self.triggerType = triggerType
        self.riskLevel = riskLevel
        self.registrySize = registrySize
        self.expectedCompleteness = expectedCompleteness
        self.expectedDeterministicAcceptance = expectedDeterministicAcceptance
    }
}

/// Phase 0 paired corpus seed: representative cases covering key dimensions.
public struct ConditionalLatencyV1Corpus {
    public static let cases: [PairedConditionCase] = [
        // Single-condition schedule automations (deterministic-complete)
        PairedConditionCase(
            id: "cond-001-sched-temp-unique",
            baseCommand: "turn on the AC at 7 AM",
            conditionedCommand: "turn on the AC at 7 AM but only if the living room temperature is above 26",
            conditionLeafCount: 1,
            conditionForm: "comparison",
            conditionResolution: "unique",
            conditionTree: "leaf",
            actionCount: 1,
            triggerType: "schedule",
            riskLevel: "low",
            registrySize: "medium",
            expectedCompleteness: "complete",
            expectedDeterministicAcceptance: true
        ),
        PairedConditionCase(
            id: "cond-002-sched-motion-unique",
            baseCommand: "turn on the lights at 7 PM",
            conditionedCommand: "turn on the lights at 7 PM but only if motion is detected",
            conditionLeafCount: 1,
            conditionForm: "state",
            conditionResolution: "unique",
            conditionTree: "leaf",
            actionCount: 1,
            triggerType: "schedule",
            riskLevel: "low",
            registrySize: "medium",
            expectedCompleteness: "complete",
            expectedDeterministicAcceptance: true
        ),
        PairedConditionCase(
            id: "cond-003-sched-contact-unique",
            baseCommand: "lock the front door at 10 PM",
            conditionedCommand: "lock the front door at 10 PM but only if the front door is closed",
            conditionLeafCount: 1,
            conditionForm: "state",
            conditionResolution: "unique",
            conditionTree: "leaf",
            actionCount: 1,
            triggerType: "schedule",
            riskLevel: "high",
            registrySize: "medium",
            expectedCompleteness: "complete",
            expectedDeterministicAcceptance: true
        ),

        // Single-condition with ambiguity (requires FM)
        PairedConditionCase(
            id: "cond-004-sched-temp-ambiguous",
            baseCommand: "turn on the AC at 7 AM",
            conditionedCommand: "turn on the AC at 7 AM but only if temperature is above 26",
            conditionLeafCount: 1,
            conditionForm: "comparison",
            conditionResolution: "ambiguous",
            conditionTree: "leaf",
            actionCount: 1,
            triggerType: "schedule",
            riskLevel: "low",
            registrySize: "large",
            expectedCompleteness: "partial",
            expectedDeterministicAcceptance: false
        ),

        // Range condition (currently not round-trip safe in verifier; stays FM)
        PairedConditionCase(
            id: "cond-005-sched-range",
            baseCommand: "turn on the AC at 7 AM",
            conditionedCommand: "turn on the AC at 7 AM but only if temperature is between 20 and 26",
            conditionLeafCount: 1,
            conditionForm: "range",
            conditionResolution: "unique",
            conditionTree: "leaf",
            actionCount: 1,
            triggerType: "schedule",
            riskLevel: "low",
            registrySize: "medium",
            expectedCompleteness: "complete",
            expectedDeterministicAcceptance: true
        ),

        // Two-condition AND (batched FM)
        PairedConditionCase(
            id: "cond-006-sched-and-two",
            baseCommand: "turn on the AC at 7 AM",
            conditionedCommand: "turn on the AC at 7 AM but only if temperature is above 26 and motion is detected",
            conditionLeafCount: 2,
            conditionForm: "comparison,state",
            conditionResolution: "unique,unique",
            conditionTree: "and",
            actionCount: 1,
            triggerType: "schedule",
            riskLevel: "low",
            registrySize: "medium",
            expectedCompleteness: "complete",
            expectedDeterministicAcceptance: true
        ),

        // Device-triggered condition (may have different resolution latency)
        PairedConditionCase(
            id: "cond-007-device-trigger-cond",
            baseCommand: "turn on the lights when motion is detected",
            conditionedCommand: "turn on the lights when motion is detected but only if it is after 10 PM",
            conditionLeafCount: 1,
            conditionForm: "unsupported-time",
            conditionResolution: "unsupported",
            conditionTree: "leaf",
            actionCount: 1,
            triggerType: "device",
            riskLevel: "low",
            registrySize: "medium",
            expectedCompleteness: "unsupported",
            expectedDeterministicAcceptance: false
        ),

        // Multi-action with condition
        PairedConditionCase(
            id: "cond-008-multi-action",
            baseCommand: "turn on the Bedroom AC and turn on the Living Room Lights at 7 AM",
            conditionedCommand: "turn on the Bedroom AC and turn on the Living Room Lights at 7 AM but only if temperature is above 26",
            conditionLeafCount: 1,
            conditionForm: "comparison",
            conditionResolution: "unique",
            conditionTree: "leaf",
            actionCount: 2,
            triggerType: "schedule",
            riskLevel: "low",
            registrySize: "medium",
            expectedCompleteness: "complete",
            expectedDeterministicAcceptance: true
        ),

        // High-risk condition
        PairedConditionCase(
            id: "cond-009-high-risk",
            baseCommand: "unlock the Front Door Lock at 7 AM",
            conditionedCommand: "unlock the Front Door Lock at 7 AM but only if someone is home",
            conditionLeafCount: 1,
            conditionForm: "state",
            conditionResolution: "unique",
            conditionTree: "leaf",
            actionCount: 1,
            triggerType: "schedule",
            riskLevel: "high",
            registrySize: "medium",
            expectedCompleteness: "complete",
            expectedDeterministicAcceptance: true
        ),
    ]

    public static func evaluationCases() -> [EvaluationCase] {
        cases.flatMap { paired in
            [
                evaluationCase(for: paired, variant: .base),
                evaluationCase(for: paired, variant: .conditioned)
            ]
        }
    }

    private enum Variant {
        case base
        case conditioned
    }

    private static func evaluationCase(
        for paired: PairedConditionCase,
        variant: Variant
    ) -> EvaluationCase {
        let isConditioned = variant == .conditioned
        let suffix = isConditioned ? "conditioned" : "base"
        return EvaluationCase(
            id: "\(paired.id).\(suffix)",
            suite: "conditional-latency",
            tags: [
                "automation",
                "conditional-latency",
                "pair:\(paired.id)",
                suffix,
                "conditionForm:\(paired.conditionForm)",
                "conditionResolution:\(paired.conditionResolution)",
                "conditionTree:\(paired.conditionTree)",
                "conditionLeaves:\(paired.conditionLeafCount)",
                "trigger:\(paired.triggerType)",
                "risk:\(paired.riskLevel)",
                "registry:\(paired.registrySize)"
            ],
            input: isConditioned ? paired.conditionedCommand : paired.baseCommand,
            fixture: EvaluationFixture(devices: fixtureDevices(for: paired)),
            expected: EvaluationExpectedOutput(
                actionCount: paired.actionCount,
                conditionCount: isConditioned ? paired.conditionLeafCount : 0,
                allowedOutcome: allowedOutcome(for: paired, isConditioned: isConditioned)
            )
        )
    }

    private static func allowedOutcome(
        for paired: PairedConditionCase,
        isConditioned: Bool
    ) -> EvaluationAllowedOutcome {
        if isConditioned, paired.conditionResolution == "unsupported" {
            return .unsupported
        }
        if isConditioned, paired.conditionResolution == "ambiguous" {
            return .clarification
        }
        if paired.riskLevel == "high" {
            return .confirmation
        }
        return .drafted
    }

    private static func fixtureDevices(for paired: PairedConditionCase) -> [HomeCandidateRecord] {
        var devices = commonFixtureDevices()
        if paired.conditionResolution == "ambiguous" || paired.registrySize == "large" {
            devices.append(contentsOf: [
                temperatureSensor(id: "latency_office_temperature_sensor", name: "Office Temperature Sensor", room: "office", temperature: "24"),
                temperatureSensor(id: "latency_guest_temperature_sensor", name: "Guest Temperature Sensor", room: "guest room", temperature: "23")
            ])
        }
        return devices
    }

    private static func commonFixtureDevices() -> [HomeCandidateRecord] {
        [
            HomeCandidateRecord(
                id: "latency_bedroom_ac",
                displayName: "Bedroom AC",
                deviceType: "airConditioner",
                room: "bedroom",
                capabilities: [
                    "switch",
                    "temperatureMeasurement",
                    "relativeHumidityMeasurement",
                    "thermostatCoolingSetpoint",
                    "airConditionerMode",
                    "airConditionerFanMode"
                ],
                supportedCommands: [
                    "switch": ["on", "off"],
                    "thermostatCoolingSetpoint": ["setCoolingSetpoint"],
                    "airConditionerMode": ["setAirConditionerMode"],
                    "airConditionerFanMode": ["setFanMode"]
                ],
                currentState: [
                    "switch": "off",
                    "temperature": "25",
                    "humidity": "55",
                    "coolingSetpoint": "24"
                ],
                riskLevel: .medium
            ),
            HomeCandidateRecord(
                id: "latency_living_room_lights",
                displayName: "Living Room Lights",
                deviceType: "light",
                room: "living room",
                capabilities: ["switch", "switchLevel"],
                supportedCommands: ["switch": ["on", "off"]],
                currentState: ["switch": "off", "level": "60"]
            ),
            HomeCandidateRecord(
                id: "latency_living_room_blinds",
                displayName: "Living Room Blinds",
                deviceType: "blind",
                room: "living room",
                capabilities: ["windowShade", "windowShadeLevel"],
                supportedCommands: ["windowShade": ["open", "close"]],
                currentState: ["windowShade": "closed", "shadeLevel": "0"],
                riskLevel: .medium
            ),
            HomeCandidateRecord(
                id: "latency_front_door_lock",
                displayName: "Front Door Lock",
                deviceType: "lock",
                room: "entry",
                capabilities: ["lock", "contactSensor", "battery"],
                supportedCommands: ["lock": ["lock", "unlock"]],
                currentState: ["lock": "locked", "contact": "closed", "battery": "85"],
                riskLevel: .high
            ),
            HomeCandidateRecord(
                id: "latency_entry_contact_sensor",
                displayName: "Entry Contact Sensor",
                deviceType: "contactSensor",
                room: "entry",
                capabilities: ["contactSensor", "battery"],
                supportedCommands: [:],
                currentState: ["contact": "closed", "battery": "90"]
            ),
            HomeCandidateRecord(
                id: "latency_hallway_motion_sensor",
                displayName: "Hallway Motion Sensor",
                deviceType: "motionSensor",
                room: "hallway",
                capabilities: ["motionSensor", "battery"],
                supportedCommands: [:],
                currentState: ["motion": "inactive", "battery": "86"]
            ),
            HomeCandidateRecord(
                id: "latency_home_presence_sensor",
                displayName: "Home Presence Sensor",
                deviceType: "presenceSensor",
                room: "home",
                capabilities: ["presenceSensor"],
                supportedCommands: [:],
                currentState: ["presence": "present"]
            ),
            temperatureSensor(
                id: "latency_living_room_temperature_sensor",
                name: "Living Room Temperature Sensor",
                room: "living room",
                temperature: "25"
            )
        ]
    }

    private static func temperatureSensor(
        id: String,
        name: String,
        room: String,
        temperature: String
    ) -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: id,
            displayName: name,
            deviceType: "temperatureSensor",
            room: room,
            capabilities: ["temperatureMeasurement", "battery"],
            supportedCommands: [:],
            currentState: ["temperature": temperature, "battery": "92"]
        )
    }
}
