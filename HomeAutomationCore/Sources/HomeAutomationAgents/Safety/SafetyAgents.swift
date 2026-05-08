import Foundation
import HomeAutomationCore

public struct SafetyValidationInput: Sendable {
    public let draft: HomeCommandDraft
    public let finalInput: HomeFinalResolutionInput

    public init(draft: HomeCommandDraft, finalInput: HomeFinalResolutionInput) {
        self.draft = draft
        self.finalInput = finalInput
    }
}

public struct ParameterValidationInput: Sendable {
    public let parameters: [HomeResolvedParameter]
    public let capability: String
    public let command: String
    public let device: HomeCandidateRecord

    public init(
        parameters: [HomeResolvedParameter],
        capability: String,
        command: String,
        device: HomeCandidateRecord
    ) {
        self.parameters = parameters
        self.capability = capability
        self.command = command
        self.device = device
    }
}

public struct ConfirmationPolicyInput: Sendable, Hashable {
    public let intent: HomeAutomationIntent
    public let capability: String?
    public let deviceType: String
    public let candidateRisk: HomeAutomationRiskLevel
    public let command: String?
    public let memoryContributedTarget: Bool

    public init(
        intent: HomeAutomationIntent,
        capability: String?,
        deviceType: String,
        candidateRisk: HomeAutomationRiskLevel,
        command: String?,
        memoryContributedTarget: Bool = false
    ) {
        self.intent = intent
        self.capability = capability
        self.deviceType = deviceType
        self.candidateRisk = candidateRisk
        self.command = command
        self.memoryContributedTarget = memoryContributedTarget
    }
}

public struct AgentCommandValidator: Sendable {
    public init() {}

    public func validate(_ draft: HomeCommandDraft, input: HomeFinalResolutionInput) -> HomeCommandResolution {
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

        let isRelativeChange = AgentExecutionPlanner.isRelativeChange(normalizedDraft)
        let supportedCommands = device.supportedCommands[capability, default: []]
        if command != "getStatus",
           !supportedCommands.contains(command),
           !(isRelativeChange && AgentExecutionPlanner.supportedSetterCommand(for: capability, device: device) != nil) {
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
            guard AgentExecutionPlanner.relativeDeltaString(from: normalizedDraft.parameters) != nil else {
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

        return .readyToExecute(AgentExecutionPlanner.plan(from: normalizedDraft, device: device))
    }
}

public struct SafetyValidationAgent: HomeAgent {
    public typealias Input = SafetyValidationInput
    public typealias Output = HomeCommandResolution

    public let id = AgentID.safetyValidation
    public let capabilities: Set<AgentCapability> = [.safetyValidation]
    public let timeoutNanoseconds: UInt64 = 5_000_000_000
    private let validate: @Sendable (SafetyValidationInput) async throws -> HomeCommandResolution

    public init(validate: @escaping @Sendable (SafetyValidationInput) async throws -> HomeCommandResolution) {
        self.validate = validate
    }

    public init(validator: AgentCommandValidator = AgentCommandValidator()) {
        self.validate = { input in
            validator.validate(input.draft, input: input.finalInput)
        }
    }

    public func run(_ input: SafetyValidationInput, context: ResolutionContext) async throws -> HomeCommandResolution {
        try await validate(input)
    }
}

public struct ParameterValidationAgent: HomeAgent {
    public typealias Input = ParameterValidationInput
    public typealias Output = Bool

    public let id = AgentID.parameterValidation
    public let capabilities: Set<AgentCapability> = [.parameterValidation]
    public let timeoutNanoseconds: UInt64 = 5_000_000_000
    private let validate: @Sendable (ParameterValidationInput) async throws -> Bool

    public init(validate: @escaping @Sendable (ParameterValidationInput) async throws -> Bool) {
        self.validate = validate
    }

    public init() {
        self.validate = { input in
            HomeParameterValidator.validate(
                input.parameters,
                capability: input.capability,
                command: input.command,
                device: input.device
            )
        }
    }

    public func run(_ input: ParameterValidationInput, context: ResolutionContext) async throws -> Bool {
        try await validate(input)
    }
}

public struct ConfirmationPolicyAgent: HomeAgent {
    public typealias Input = ConfirmationPolicyInput
    public typealias Output = Bool

    public let id = AgentID.confirmationPolicy
    public let capabilities: Set<AgentCapability> = [.confirmationPolicy]
    public let timeoutNanoseconds: UInt64 = 5_000_000_000
    private let requiresConfirmation: @Sendable (ConfirmationPolicyInput) async throws -> Bool

    public init(requiresConfirmation: @escaping @Sendable (ConfirmationPolicyInput) async throws -> Bool) {
        self.requiresConfirmation = requiresConfirmation
    }

    public init() {
        self.requiresConfirmation = { input in
            if input.memoryContributedTarget,
               Self.requiresExplicitConfirmationForMemoryHint(input) {
                return true
            }
            return HomeRiskPolicy.requiresConfirmation(
                intent: input.intent,
                capability: input.capability,
                deviceType: input.deviceType,
                candidateRisk: input.candidateRisk,
                command: input.command
            )
        }
    }

    public func run(_ input: ConfirmationPolicyInput, context: ResolutionContext) async throws -> Bool {
        try await requiresConfirmation(input)
    }

    private static func requiresExplicitConfirmationForMemoryHint(_ input: ConfirmationPolicyInput) -> Bool {
        if input.candidateRisk == .high || input.candidateRisk == .critical {
            return true
        }

        let deviceType = normalized(input.deviceType)
        if ["camera", "valve", "oven", "stove", "lock", "garagedoor", "garage door", "door"].contains(deviceType) {
            return true
        }

        switch input.intent {
        case .unlock, .lock, .open, .close:
            return true
        case .start:
            return ["oven", "stove", "washer", "dryer"].contains(deviceType)
        default:
            break
        }

        if let capability = input.capability {
            let risk = HomeCapabilityRegistry.riskLevel(for: capability)
            if risk == .high || risk == .critical {
                return true
            }
        }

        return ["unlock", "lock", "open", "close", "setCode", "deleteCode", "startStream", "take", "setOvenMode", "setOvenSetpoint"]
            .contains(input.command ?? "")
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}
