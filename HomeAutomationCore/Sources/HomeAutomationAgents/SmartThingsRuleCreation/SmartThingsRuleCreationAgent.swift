import Foundation
import HomeAutomationCore

public struct SmartThingsRuleCreationAgent: HomeAgent {
    public typealias Input = SmartThingsRuleCreationInput
    public typealias Output = SmartThingsRuleCreationOutput

    public let id = AgentID.smartThingsRuleCreation
    public let capabilities: Set<AgentCapability> = [.smartThingsRuleCreation]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let creator: (any SmartThingsRuleCreating)?

    public init(creator: (any SmartThingsRuleCreating)? = nil) {
        self.creator = creator
    }

    public func run(
        _ input: SmartThingsRuleCreationInput,
        context: ResolutionContext
    ) async throws -> SmartThingsRuleCreationOutput {
        guard input.options.mode == .create else {
            return SmartThingsRuleCreationOutput(
                plan: input.plan,
                receipt: nil,
                detail: "dry-run"
            )
        }

        guard input.validation?.isValid != false else {
            return skipped(
                input: input,
                status: .skipped,
                message: input.validation?.blockingMessage ?? "Automation validation blocked SmartThings rule creation."
            )
        }

        guard let document = input.document else {
            return skipped(
                input: input,
                status: .skipped,
                message: input.plan.unsupportedCompilationReason ?? "SmartThings rule JSON is unavailable."
            )
        }

        if input.plan.requiresConfirmation && !input.options.confirmsHighRiskAutomation {
            return skipped(
                input: input,
                status: .confirmationRequired,
                message: "Explicit confirmation is required before creating this high-risk automation."
            )
        }

        guard let locationID = input.options.locationID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !locationID.isEmpty else {
            return skipped(
                input: input,
                status: .skipped,
                message: "SmartThings location ID is required before creating a rule."
            )
        }

        guard let creator else {
            return skipped(
                input: input,
                status: .skipped,
                message: "SmartThings rule creator backend is not configured."
            )
        }

        do {
            let receipt = try await creator.createRule(
                SmartThingsRuleCreationRequest(
                    document: document,
                    locationID: locationID,
                    plan: input.plan
                )
            )
            return SmartThingsRuleCreationOutput(
                plan: plan(input.plan, receipt: receipt, requiresConfirmation: false),
                receipt: receipt,
                detail: receipt.message
            )
        } catch {
            let receipt = SmartThingsRuleCreationReceipt(
                status: .failed,
                locationID: locationID,
                message: error.localizedDescription
            )
            return SmartThingsRuleCreationOutput(
                plan: plan(
                    input.plan,
                    receipt: receipt,
                    requiresConfirmation: remainingConfirmationRequired(for: input, status: .failed)
                ),
                receipt: receipt,
                detail: receipt.message
            )
        }
    }

    private func skipped(
        input: SmartThingsRuleCreationInput,
        status: SmartThingsRuleCreationStatus,
        message: String
    ) -> SmartThingsRuleCreationOutput {
        let receipt = SmartThingsRuleCreationReceipt(
            status: status,
            locationID: input.options.locationID,
            message: message
        )
        return SmartThingsRuleCreationOutput(
            plan: plan(
                input.plan,
                receipt: receipt,
                requiresConfirmation: remainingConfirmationRequired(for: input, status: status)
            ),
            receipt: receipt,
            detail: message
        )
    }

    private func plan(
        _ plan: HomeAutomationCreationPlan,
        receipt: SmartThingsRuleCreationReceipt,
        requiresConfirmation: Bool? = nil
    ) -> HomeAutomationCreationPlan {
        HomeAutomationCreationPlan(
            name: plan.name,
            ruleDraft: plan.ruleDraft,
            resolvedActions: plan.resolvedActions,
            smartThingsRuleJSON: plan.smartThingsRuleJSON,
            requiresConfirmation: requiresConfirmation ?? plan.requiresConfirmation,
            unsupportedCompilationReason: plan.unsupportedCompilationReason,
            backendResponse: receipt
        )
    }

    private func remainingConfirmationRequired(
        for input: SmartThingsRuleCreationInput,
        status: SmartThingsRuleCreationStatus
    ) -> Bool {
        if status == .confirmationRequired {
            return true
        }
        if input.options.mode == .create && input.options.confirmsHighRiskAutomation {
            return false
        }
        return input.plan.requiresConfirmation
    }
}
