import Foundation
import HomeAutomationCore

/// Mandatory fail-closed gate that enforces confirmation requirements for high-risk commands.
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
