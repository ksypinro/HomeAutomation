import Foundation
import HomeAutomationCore

public struct ExecutionPlanningInput: Sendable {
    public let draft: HomeCommandDraft
    public let device: HomeCandidateRecord

    public init(draft: HomeCommandDraft, device: HomeCandidateRecord) {
        self.draft = draft
        self.device = device
    }
}

public enum AgentExecutionPlanner {
    public static func isRelativeChange(_ draft: HomeCommandDraft) -> Bool {
        draft.intent == .increaseValue ||
            draft.intent == .decreaseValue ||
            draft.command == "increaseValue" ||
            draft.command == "decreaseValue"
    }

    public static func supportedSetterCommand(for capability: String, device: HomeCandidateRecord) -> String? {
        guard let setter = setterCommand(for: capability),
              device.supportedCommands[capability, default: []].contains(setter) else {
            return nil
        }
        return setter
    }

    public static func relativeDeltaString(from parameters: [HomeResolvedParameter]) -> String? {
        guard let parameter = parameters.first else { return nil }
        if let numericValue = parameter.numericValue, numericValue > 0 {
            if numericValue.rounded() == numericValue {
                return String(Int(numericValue))
            }
            return String(numericValue)
        }
        guard let value = parameter.value, Double(value).map({ $0 > 0 }) == true else {
            return nil
        }
        return value
    }

    public static func plan(from draft: HomeCommandDraft, device: HomeCandidateRecord) -> HomeAutomationExecutionPlan {
        if device.type == .routine, draft.command == "run" {
            return HomeAutomationExecutionPlan(
                steps: routineSteps(for: device),
                requiresConfirmation: draft.requiresConfirmation
            )
        }

        guard isRelativeChange(draft) else {
            let step = HomeAutomationExecutionStep(
                type: draft.intent == .getStatus || draft.command == "getStatus" ? "query" : "command",
                deviceID: device.id,
                deviceName: device.displayName,
                capability: draft.capability ?? "",
                command: draft.command ?? "getStatus",
                value: valueString(from: draft.parameters)
            )
            return HomeAutomationExecutionPlan(
                steps: [step],
                requiresConfirmation: draft.requiresConfirmation
            )
        }

        let capability = draft.capability ?? ""
        let attribute = primaryAttribute(for: capability)
        let delta = relativeDeltaString(from: draft.parameters)
        let isDecrease = draft.intent == .decreaseValue || draft.command == "decreaseValue"
        let setter = supportedSetterCommand(for: capability, device: device)

        let readStep = HomeAutomationExecutionStep(
            type: "readAttribute",
            deviceID: device.id,
            deviceName: device.displayName,
            capability: capability,
            command: "getStatus",
            value: currentValue(for: capability, in: device),
            attribute: attribute
        )
        let commandStep = HomeAutomationExecutionStep(
            type: "command",
            deviceID: device.id,
            deviceName: device.displayName,
            capability: capability,
            command: setter ?? draft.command ?? (isDecrease ? "decreaseValue" : "increaseValue"),
            value: setter == nil ? delta : nil,
            attribute: attribute,
            valueFormula: setter.flatMap { _ in
                delta.map { "current \(isDecrease ? "-" : "+") \($0)" }
            }
        )

        return HomeAutomationExecutionPlan(
            steps: [readStep, commandStep],
            requiresConfirmation: draft.requiresConfirmation
        )
    }

    private static func routineSteps(for device: HomeCandidateRecord) -> [HomeAutomationExecutionStep] {
        switch device.id {
        case "movie_time":
            return [
                HomeAutomationExecutionStep(
                    type: "command",
                    deviceID: "living_room_ceiling_light",
                    deviceName: "Living Room Ceiling Light",
                    capability: "switchLevel",
                    command: "setLevel",
                    value: "25"
                ),
                HomeAutomationExecutionStep(
                    type: "command",
                    deviceID: "living_room_blinds",
                    deviceName: "Living Room Blinds",
                    capability: "windowShade",
                    command: "close"
                ),
                HomeAutomationExecutionStep(
                    type: "command",
                    deviceID: "living_room_tv",
                    deviceName: "Living Room TV",
                    capability: "switch",
                    command: "on"
                )
            ]
        default:
            return [
                HomeAutomationExecutionStep(
                    type: "command",
                    deviceID: device.id,
                    deviceName: device.displayName,
                    capability: "routine",
                    command: "run"
                )
            ]
        }
    }

    private static func currentValue(for capability: String, in device: HomeCandidateRecord) -> String? {
        let attributes = HomeCapabilityRegistry.definitions[capability]?.attributeNames ?? []
        for attribute in attributes {
            if let value = device.currentState[attribute] {
                return value
            }
        }
        return nil
    }

    static func primaryAttribute(for capability: String) -> String? {
        switch capability {
        case "switchLevel":
            return "level"
        case "thermostatCoolingSetpoint":
            return "coolingSetpoint"
        case "thermostatHeatingSetpoint":
            return "heatingSetpoint"
        case "audioVolume":
            return "volume"
        case "windowShadeLevel":
            return "shadeLevel"
        default:
            return HomeCapabilityRegistry.definitions[capability]?.attributeNames.first
        }
    }

    static func setterCommand(for capability: String) -> String? {
        switch capability {
        case "switchLevel":
            return "setLevel"
        case "thermostatCoolingSetpoint":
            return "setCoolingSetpoint"
        case "thermostatHeatingSetpoint":
            return "setHeatingSetpoint"
        case "audioVolume":
            return "setVolume"
        case "windowShadeLevel":
            return "setShadeLevel"
        default:
            return nil
        }
    }

    private static func valueString(from parameters: [HomeResolvedParameter]) -> String? {
        guard let parameter = parameters.first else { return nil }
        if let numericValue = parameter.numericValue {
            if numericValue.rounded() == numericValue {
                return String(Int(numericValue))
            }
            return String(numericValue)
        }
        return parameter.value ?? parameter.unit
    }
}

public struct AgentPlanExecutor: Sendable {
    private let registry: MockHomeDeviceRegistry

    public init(registry: MockHomeDeviceRegistry) {
        self.registry = registry
    }

    public func executeLowRiskPlan(_ plan: HomeAutomationExecutionPlan) async throws -> HomeCandidateRecord {
        var lastUpdatedDevice: HomeCandidateRecord?
        for step in plan.steps {
            guard step.type != "query", step.type != "readAttribute" else {
                continue
            }

            let singleStepPlan = HomeAutomationExecutionPlan(
                steps: [step],
                requiresConfirmation: plan.requiresConfirmation
            )
            lastUpdatedDevice = try await registry.executeLowRiskPlan(singleStepPlan)
        }

        if let lastUpdatedDevice {
            return lastUpdatedDevice
        }

        throw FoundationLabCoreError.invalidRequest("Plan contains no executable command steps")
    }
}

public struct ExecutionPlanningAgent: HomeAgent {
    public typealias Input = ExecutionPlanningInput
    public typealias Output = HomeAutomationExecutionPlan

    public let id = AgentID.executionPlanning
    public let capabilities: Set<AgentCapability> = [.executionPlanning]
    public let timeoutNanoseconds: UInt64 = 5_000_000_000
    private let plan: @Sendable (ExecutionPlanningInput) async throws -> HomeAutomationExecutionPlan

    public init(plan: @escaping @Sendable (ExecutionPlanningInput) async throws -> HomeAutomationExecutionPlan) {
        self.plan = plan
    }

    public init() {
        self.plan = { input in
            AgentExecutionPlanner.plan(from: input.draft, device: input.device)
        }
    }

    public func run(_ input: ExecutionPlanningInput, context: ResolutionContext) async throws -> HomeAutomationExecutionPlan {
        try await plan(input)
    }
}

public struct MockExecutionAgent: HomeAgent {
    public typealias Input = HomeAutomationExecutionPlan
    public typealias Output = HomeCandidateRecord

    public let id = AgentID.mockExecution
    public let capabilities: Set<AgentCapability> = [.execution]
    public let timeoutNanoseconds: UInt64 = 5_000_000_000
    private let execute: @Sendable (HomeAutomationExecutionPlan) async throws -> HomeCandidateRecord

    public init(execute: @escaping @Sendable (HomeAutomationExecutionPlan) async throws -> HomeCandidateRecord) {
        self.execute = execute
    }

    public init(registry: MockHomeDeviceRegistry = MockHomeDeviceRegistry()) {
        let executor = AgentPlanExecutor(registry: registry)
        self.execute = executor.executeLowRiskPlan
    }

    public func run(_ input: HomeAutomationExecutionPlan, context: ResolutionContext) async throws -> HomeCandidateRecord {
        try await execute(input)
    }
}
