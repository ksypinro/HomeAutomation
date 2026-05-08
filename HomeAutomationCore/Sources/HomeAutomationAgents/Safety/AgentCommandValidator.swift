import Foundation
import HomeAutomationCore

/// Deterministic validator for target device, capability, command, risk, and plan eligibility.
///
/// `AgentCommandValidator` is the core safety logic used by `SafetyValidationAgent`.
/// It performs a sequence of deterministic checks against canonical registries
/// and produces one of four outcomes:
/// - `.readyToExecute(plan)` — command is safe and valid
/// - `.needsClarification(question)` — target or parameters are ambiguous
/// - `.unsupported(reason)` — device/capability/command is not supported
/// - `.requiresConfirmation(draft)` — command requires explicit user confirmation
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
