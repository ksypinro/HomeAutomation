import Foundation

public extension SmartThingsRuleDocument {
    init(payload: SmartThingsRulePayload) throws {
        self.init(
            name: payload.name,
            jsonString: try payload.jsonString(),
            payload: payload
        )
    }
}

public indirect enum SmartThingsRuleJSONValue: Sendable, Hashable, Codable {
    case null
    case string(String)
    case integer(Int)
    case decimal(Double)
    case bool(Bool)
    case array([SmartThingsRuleJSONValue])
    case object([String: SmartThingsRuleJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .decimal(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SmartThingsRuleJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: SmartThingsRuleJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .decimal(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let values):
            try container.encode(values)
        case .object(let values):
            try container.encode(values)
        }
    }
}

public struct SmartThingsRulePayload: Sendable, Hashable, Codable {
    public let name: String
    public let actions: [SmartThingsRuleAction]

    public init(name: String, actions: [SmartThingsRuleAction]) {
        self.name = name
        self.actions = actions
    }

    public var jsonValue: SmartThingsRuleJSONValue {
        .object([
            "name": .string(name),
            "actions": .array(actions.map(\.jsonValue))
        ])
    }

    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(jsonValue)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

public indirect enum SmartThingsRuleAction: Sendable, Hashable, Codable {
    case command(SmartThingsCommandAction)
    case every(SmartThingsEveryAction)
    case conditional(SmartThingsIfAction)

    public var jsonValue: SmartThingsRuleJSONValue {
        switch self {
        case .command(let action):
            return .object(["command": action.jsonValue])
        case .every(let action):
            return .object(["every": action.jsonValue])
        case .conditional(let action):
            return .object(["if": action.jsonValue])
        }
    }
}

public struct SmartThingsEveryAction: Sendable, Hashable, Codable {
    public let schedule: SmartThingsEverySchedule
    public let actions: [SmartThingsRuleAction]

    public init(schedule: SmartThingsEverySchedule, actions: [SmartThingsRuleAction]) {
        self.schedule = schedule
        self.actions = actions
    }

    public var jsonValue: SmartThingsRuleJSONValue {
        var object = schedule.jsonObject
        object["actions"] = .array(actions.map(\.jsonValue))
        return .object(object)
    }
}

public enum SmartThingsEverySchedule: Sendable, Hashable, Codable {
    case specific(reference: String, offsetMinutes: Int)
    case interval(value: Int, unit: String)

    public var jsonObject: [String: SmartThingsRuleJSONValue] {
        switch self {
        case .specific(let reference, let offsetMinutes):
            return [
                "specific": .object([
                    "reference": .string(reference),
                    "offset": .object([
                        "value": .object(["integer": .integer(offsetMinutes)]),
                        "unit": .string("Minute")
                    ])
                ])
            ]
        case .interval(let value, let unit):
            return [
                "interval": .object([
                    "value": .object(["integer": .integer(value)]),
                    "unit": .string(unit)
                ])
            ]
        }
    }
}

public struct SmartThingsIfAction: Sendable, Hashable, Codable {
    public let condition: SmartThingsRuleCondition
    public let thenActions: [SmartThingsRuleAction]
    public let elseActions: [SmartThingsRuleAction]

    public init(
        condition: SmartThingsRuleCondition,
        thenActions: [SmartThingsRuleAction],
        elseActions: [SmartThingsRuleAction] = []
    ) {
        self.condition = condition
        self.thenActions = thenActions
        self.elseActions = elseActions
    }

    public var jsonValue: SmartThingsRuleJSONValue {
        var object = condition.jsonObject
        object["then"] = .array(thenActions.map(\.jsonValue))
        if !elseActions.isEmpty {
            object["else"] = .array(elseActions.map(\.jsonValue))
        }
        return .object(object)
    }
}

public struct SmartThingsCommandAction: Sendable, Hashable, Codable {
    public let devices: [String]
    public let commands: [SmartThingsCommand]

    public init(devices: [String], commands: [SmartThingsCommand]) {
        self.devices = devices
        self.commands = commands
    }

    public var jsonValue: SmartThingsRuleJSONValue {
        .object([
            "devices": .array(devices.map { .string($0) }),
            "commands": .array(commands.map(\.jsonValue))
        ])
    }
}

public struct SmartThingsCommand: Sendable, Hashable, Codable {
    public let component: String
    public let capability: String
    public let command: String
    public let arguments: [SmartThingsRuleJSONValue]

    public init(
        component: String = "main",
        capability: String,
        command: String,
        arguments: [SmartThingsRuleJSONValue] = []
    ) {
        self.component = component
        self.capability = capability
        self.command = command
        self.arguments = arguments
    }

    public var jsonValue: SmartThingsRuleJSONValue {
        .object([
            "component": .string(component),
            "capability": .string(capability),
            "command": .string(command),
            "arguments": .array(arguments)
        ])
    }
}

public indirect enum SmartThingsRuleCondition: Sendable, Hashable, Codable {
    case and([SmartThingsRuleCondition])
    case or([SmartThingsRuleCondition])
    case not(SmartThingsRuleCondition)
    case changes(SmartThingsRuleCondition)
    case between(value: SmartThingsRuleOperand, start: SmartThingsRuleOperand, end: SmartThingsRuleOperand)
    case comparison(operatorName: String, left: SmartThingsRuleOperand, right: SmartThingsRuleOperand)

    public var jsonObject: [String: SmartThingsRuleJSONValue] {
        switch self {
        case .and(let conditions):
            return ["and": .array(conditions.map { .object($0.jsonObject) })]
        case .or(let conditions):
            return ["or": .array(conditions.map { .object($0.jsonObject) })]
        case .not(let condition):
            return ["not": .object(condition.jsonObject)]
        case .changes(let condition):
            return ["changes": .object(condition.jsonObject)]
        case .between(let value, let start, let end):
            return [
                "between": .object([
                    "value": value.jsonValue,
                    "start": start.jsonValue,
                    "end": end.jsonValue
                ])
            ]
        case .comparison(let operatorName, let left, let right):
            return [
                operatorName: .object([
                    "left": left.jsonValue,
                    "right": right.jsonValue
                ])
            ]
        }
    }
}

public enum SmartThingsRuleTriggerPolicy: String, Sendable, Hashable, Codable {
    case always = "Always"
    case never = "Never"
}

public enum SmartThingsRuleOperand: Sendable, Hashable, Codable {
    case deviceAttribute(
        devices: [String],
        component: String,
        capability: String,
        attribute: String,
        trigger: SmartThingsRuleTriggerPolicy?
    )
    case string(String)
    case integer(Int)
    case decimal(Double, unit: String?)
    case locationMode(String)

    public var jsonValue: SmartThingsRuleJSONValue {
        switch self {
        case .deviceAttribute(let devices, let component, let capability, let attribute, let trigger):
            var object: [String: SmartThingsRuleJSONValue] = [
                "devices": .array(devices.map { .string($0) }),
                "component": .string(component),
                "capability": .string(capability),
                "attribute": .string(attribute)
            ]
            if let trigger {
                object["trigger"] = .string(trigger.rawValue)
            }
            return .object(["device": .object(object)])
        case .string(let value):
            return .object(["string": .string(value)])
        case .integer(let value):
            return .object(["integer": .integer(value)])
        case .decimal(let value, let unit):
            var object: [String: SmartThingsRuleJSONValue] = ["decimal": .decimal(value)]
            if let unit {
                object["unit"] = .string(unit)
            }
            return .object(object)
        case .locationMode(let value):
            return .object(["location": .object(["attribute": .string(value)])])
        }
    }
}
