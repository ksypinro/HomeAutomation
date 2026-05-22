import Foundation
import HomeAutomationCore

public struct AutomationDraftAssemblyAgent: HomeAgent {
    public typealias Input = AutomationDraftAssemblyInput
    public typealias Output = HomeAutomationRuleDraft

    public let id = AgentID.automationDraftAssembly
    public let capabilities: Set<AgentCapability> = [.automationDraftAssembly]
    public let timeoutNanoseconds: UInt64 = 30_000_000_000

    public init() {}

    public func run(
        _ input: AutomationDraftAssemblyInput,
        context: ResolutionContext
    ) async throws -> HomeAutomationRuleDraft {
        let assembledCondition = try assembleCondition(
            tree: input.resolvedComponents.conditionTree,
            results: input.resolvedComponents.conditionResults
        )
        let trigger = trigger(for: input, assembledCondition: assembledCondition)
        let condition = input.componentPlan.trigger?.kindHint == .device ? nil : assembledCondition
        let actions = input.componentPlan.actions
            .sorted { $0.order < $1.order }
            .map(\.rawText)
        guard !actions.isEmpty else {
            throw AutomationDraftError.invalidOutput("component assembly has no actions")
        }

        return HomeAutomationRuleDraft(
            name: name(for: actions, trigger: trigger),
            trigger: trigger,
            condition: condition,
            actionDescriptions: actions,
            confidence: input.componentPlan.confidence
        )
    }

    private func trigger(
        for input: AutomationDraftAssemblyInput,
        assembledCondition: HomeAutomationCondition?
    ) -> HomeAutomationTrigger? {
        guard input.componentPlan.trigger?.kindHint == .device else {
            return input.resolvedComponents.trigger
        }
        guard let condition = assembledCondition else {
            return input.resolvedComponents.trigger
        }
        return .device(
            HomeAutomationDeviceTrigger(
                description: input.componentPlan.trigger?.rawText ?? "device trigger",
                condition: condition
            )
        )
    }

    private func assembleCondition(
        tree: AutomationConditionTreeDescriptor?,
        results: [AutomationConditionClauseResolutionResult]
    ) throws -> HomeAutomationCondition? {
        guard let tree else {
            return results.compactMap(\.condition).first
        }
        let byID = results.reduce(into: [String: HomeAutomationCondition?]()) { partial, result in
            partial[result.id] = result.condition
        }
        return try assembleCondition(tree, byID: byID)
    }

    private func assembleCondition(
        _ tree: AutomationConditionTreeDescriptor,
        byID: [String: HomeAutomationCondition?]
    ) throws -> HomeAutomationCondition {
        switch tree {
        case .leaf(let id):
            guard let maybeCondition = byID[id], let condition = maybeCondition else {
                throw AutomationDraftError.invalidOutput("missing resolved condition component \(id)")
            }
            return condition
        case .and(let children):
            return .and(try children.map { try assembleCondition($0, byID: byID) })
        case .or(let children):
            return .or(try children.map { try assembleCondition($0, byID: byID) })
        case .not(let child):
            return .not(try assembleCondition(child, byID: byID))
        }
    }

    private func name(for actions: [String], trigger: HomeAutomationTrigger?) -> String {
        let action = actions.first ?? "Automation"
        guard let trigger else { return action }
        return "\(action) \(trigger.displayString)"
    }
}
