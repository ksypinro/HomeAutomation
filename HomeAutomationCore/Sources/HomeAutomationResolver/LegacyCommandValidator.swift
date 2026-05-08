import Foundation
import HomeAutomationCore

public struct LegacyCommandValidator: Sendable {
    public init() {}

    public func validate(
        _ draft: HomeCommandDraft,
        input: HomeFinalResolutionInput
    ) -> HomeCommandResolution {
        let normalizedDraft: HomeCommandDraft
        if draft.command == nil, draft.intent == .getStatus {
            normalizedDraft = HomeCommandDraft(
                intent: draft.intent,
                targetDeviceID: draft.targetDeviceID,
                targetGroupID: draft.targetGroupID,
                capability: draft.capability,
                command: "getStatus",
                parameters: draft.parameters,
                needsClarification: draft.needsClarification,
                clarificationQuestion: draft.clarificationQuestion,
                requiresConfirmation: draft.requiresConfirmation,
                confidence: draft.confidence
            )
        } else {
            normalizedDraft = draft
        }

        if normalizedDraft.needsClarification {
            return .needsClarification(normalizedDraft.clarificationQuestion ?? "Which device do you mean?")
        }

        guard let deviceID = normalizedDraft.targetDeviceID else {
            return .needsClarification(normalizedDraft.clarificationQuestion ?? "Which device do you want to control?")
        }

        guard let device = input.hydratedCandidates.first(where: { $0.id == deviceID }) else {
            return .unsupported("The selected device does not exist in the hydrated candidate set.")
        }

        guard let capability = normalizedDraft.capability,
              device.capabilities.contains(capability) else {
            return .unsupported("\(device.displayName) does not support that capability.")
        }

        guard let command = normalizedDraft.command else {
            return .unsupported("\(device.displayName) does not support that command.")
        }

        let isRelativeChange = LegacyExecutionPlanner.isRelativeChange(normalizedDraft)
        let supportedCommands = device.supportedCommands[capability, default: []]
        if command != "getStatus",
           !supportedCommands.contains(command),
           !(isRelativeChange && LegacyExecutionPlanner.supportedSetterCommand(for: capability, device: device) != nil) {
            return .unsupported("\(device.displayName) does not support that command.")
        }

        if HomeRiskPolicy.requiresConfirmation(
            intent: normalizedDraft.intent,
            capability: capability,
            deviceType: device.deviceType,
            candidateRisk: device.riskLevel,
            command: command
        ) || normalizedDraft.requiresConfirmation {
            return .requiresConfirmation(normalizedDraft)
        }

        if isRelativeChange {
            guard LegacyExecutionPlanner.relativeDeltaString(from: normalizedDraft.parameters) != nil else {
                return .needsClarification("Some command values are invalid or missing.")
            }
        } else {
            guard HomeParameterValidator.validate(
                normalizedDraft.parameters,
                capability: capability,
                command: command,
                device: device
            ) else {
                return .needsClarification("Some command values are invalid or missing.")
            }
        }

        return .readyToExecute(LegacyExecutionPlanner.plan(from: normalizedDraft, device: device))
    }
}

public enum LegacyExecutionPlanner {
    static func isRelativeChange(_ draft: HomeCommandDraft) -> Bool {
        draft.intent == .increaseValue ||
            draft.intent == .decreaseValue ||
            draft.command == "increaseValue" ||
            draft.command == "decreaseValue"
    }

    static func supportedSetterCommand(for capability: String, device: HomeCandidateRecord) -> String? {
        guard let setter = setterCommand(for: capability),
              device.supportedCommands[capability, default: []].contains(setter) else {
            return nil
        }
        return setter
    }

    static func relativeDeltaString(from parameters: [HomeResolvedParameter]) -> String? {
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

    public static func plan(
        from draft: HomeCommandDraft,
        device: HomeCandidateRecord
    ) -> HomeAutomationExecutionPlan {
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

public struct LegacyPlanExecutor: Sendable {
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
