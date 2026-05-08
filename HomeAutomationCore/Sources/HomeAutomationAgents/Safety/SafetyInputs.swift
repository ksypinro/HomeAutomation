import Foundation
import HomeAutomationCore

/// Input types and support logic shared across Safety agents.

/// Input for `SafetyValidationAgent` containing the draft and final resolution context.
public struct SafetyValidationInput: Sendable {
    public let draft: HomeCommandDraft
    public let finalInput: HomeFinalResolutionInput

    public init(draft: HomeCommandDraft, finalInput: HomeFinalResolutionInput) {
        self.draft = draft
        self.finalInput = finalInput
    }
}

/// Input for `ParameterValidationAgent` containing parameters and the selected device context.
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

/// Input for `ConfirmationPolicyAgent` containing risk and context factors.
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
