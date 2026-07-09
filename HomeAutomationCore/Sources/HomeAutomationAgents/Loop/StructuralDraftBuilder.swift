import Foundation
import HomeAutomationCore

public enum StructuralDraftBuilder {

    public static func commandDraft(
        from section: CommandDraftSection?,
        risk: RiskSection,
        capabilityOverride: HomeCapabilityDecision? = nil
    ) -> HomeCommandDraft? {
        guard let section else { return nil }
        let capability = capabilityOverride?.selectedCapability ?? section.capability
        let commandName = capabilityOverride?.selectedCommand ?? section.commandName
        guard let capability, let commandName else {
            return nil
        }

        let intent = inferIntent(commandName: commandName, capability: capability)

        return HomeCommandDraft(
            intent: intent,
            targetDeviceID: section.targetDeviceID,
            capability: capability,
            command: commandName,
            parameters: section.parameters,
            needsClarification: section.targetDeviceID == nil,
            clarificationQuestion: section.targetDeviceID == nil ? "Which device do you want to control?" : nil,
            requiresConfirmation: risk.level == .high || risk.level == .critical,
            confidence: section.targetDeviceID != nil ? 0.9 : 0.3
        )
    }

    // MARK: - Automation creation plan (H2)

    /// Builds a compiled `HomeAutomationCreationPlan` from an accepted automation
    /// envelope. Pure and deterministic: it maps the envelope's automation
    /// section to the rule-draft/resolved-action model, then runs the
    /// deterministic `SmartThingsRuleCompiler` to produce Rules API JSON.
    ///
    /// Compilation failures (e.g. an unsupported schedule, a device trigger the
    /// envelope can't express structurally, or an action missing a capability)
    /// are surfaced as `unsupportedCompilationReason` rather than thrown —
    /// mirroring `SmartThingsCompilationAgent`.
    public static func automationCreationPlan(
        from envelope: DraftEnvelope,
        compiler: any HomeAutomationRuleCompiling = SmartThingsRuleCompiler()
    ) -> HomeAutomationCreationPlan {
        let automation = envelope.automation
        let requiresConfirmation = envelope.risk.level == .high || envelope.risk.level == .critical

        let resolvedActions = (automation?.actions ?? []).map { action in
            resolvedAction(from: action, risk: envelope.risk)
        }

        let leavesByID = Dictionary(
            (automation?.conditionLeaves ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let condition = automationCondition(
            tree: automation?.conditionTree,
            leaves: automation?.conditionLeaves ?? [],
            leavesByID: leavesByID
        )

        let ruleDraft = HomeAutomationRuleDraft(
            name: ruleName(from: envelope.userText),
            trigger: automationTrigger(from: automation?.trigger),
            condition: condition,
            actionDescriptions: (automation?.actions ?? []).map(\.rawText),
            confidence: envelope.operationConfidence
        )

        let basePlan = HomeAutomationCreationPlan(
            name: ruleDraft.name,
            ruleDraft: ruleDraft,
            resolvedActions: resolvedActions,
            smartThingsRuleJSON: nil,
            requiresConfirmation: requiresConfirmation,
            unsupportedCompilationReason: nil
        )

        do {
            let document = try compiler.compile(basePlan)
            return HomeAutomationCreationPlan(
                name: basePlan.name,
                ruleDraft: ruleDraft,
                resolvedActions: resolvedActions,
                smartThingsRuleJSON: document.jsonString,
                requiresConfirmation: requiresConfirmation,
                unsupportedCompilationReason: nil
            )
        } catch {
            return HomeAutomationCreationPlan(
                name: basePlan.name,
                ruleDraft: ruleDraft,
                resolvedActions: resolvedActions,
                smartThingsRuleJSON: nil,
                requiresConfirmation: requiresConfirmation,
                unsupportedCompilationReason: error.localizedDescription
            )
        }
    }

    private static func resolvedAction(
        from action: ActionDraft,
        risk: RiskSection
    ) -> HomeAutomationResolvedAction {
        let draft = commandDraft(from: action.command, risk: risk)
            ?? HomeCommandDraft(
                intent: .setValue,
                targetDeviceID: action.command.targetDeviceID,
                capability: action.command.capability,
                command: action.command.commandName,
                parameters: action.command.parameters,
                needsClarification: action.command.targetDeviceID == nil,
                clarificationQuestion: nil,
                requiresConfirmation: risk.level == .high || risk.level == .critical,
                confidence: action.command.targetDeviceID != nil ? 0.6 : 0.3
            )

        let device = action.command.targetDeviceID.flatMap { id in
            action.command.candidateTable.first { $0.id == id }
        }.map { compact in
            HomeCandidateRecord(
                id: compact.id,
                displayName: compact.name,
                deviceType: compact.deviceType,
                room: compact.room,
                capabilities: [],
                supportedCommands: [:]
            )
        }

        return HomeAutomationResolvedAction(
            originalText: action.rawText,
            draft: draft,
            device: device,
            confidence: draft.confidence
        )
    }

    private static func automationTrigger(from trigger: TriggerDraft?) -> HomeAutomationTrigger? {
        guard let trigger else { return nil }
        switch trigger.type {
        case .schedule:
            guard let repeatRule = trigger.repeatRule else { return nil }
            return .schedule(
                HomeAutomationScheduleTrigger(
                    repeatRule: repeatRule,
                    timeOfDay: trigger.time,
                    timezoneIdentifier: trigger.timezoneIdentifier
                )
            )
        case .device:
            // The envelope keeps only a description for device triggers; the
            // compiler needs a structured condition, so leave it unmapped and
            // let compilation report the gap (finding H6).
            return nil
        }
    }

    private static func automationCondition(
        tree: ConditionTreeDraft?,
        leaves: [ConditionLeafDraft],
        leavesByID: [String: ConditionLeafDraft]
    ) -> HomeAutomationCondition? {
        if let tree {
            return condition(from: tree, leavesByID: leavesByID)
        }
        let comparisons = leaves.map(comparisonCondition)
        switch comparisons.count {
        case 0: return nil
        case 1: return comparisons[0]
        default: return .and(comparisons)
        }
    }

    private static func condition(
        from tree: ConditionTreeDraft,
        leavesByID: [String: ConditionLeafDraft]
    ) -> HomeAutomationCondition? {
        switch tree {
        case .leaf(let id):
            guard let leaf = leavesByID[id] else { return nil }
            return comparisonCondition(leaf)
        case .and(let children):
            let mapped = children.compactMap { condition(from: $0, leavesByID: leavesByID) }
            return mapped.isEmpty ? nil : .and(mapped)
        case .or(let children):
            let mapped = children.compactMap { condition(from: $0, leavesByID: leavesByID) }
            return mapped.isEmpty ? nil : .or(mapped)
        case .not(let child):
            return condition(from: child, leavesByID: leavesByID).map { .not($0) }
        }
    }

    private static func comparisonCondition(_ leaf: ConditionLeafDraft) -> HomeAutomationCondition {
        let left = HomeAutomationConditionOperand.deviceAttribute(
            description: leaf.rawText,
            deviceID: leaf.target,
            capability: leaf.capability,
            attribute: leaf.attribute
        )
        let right: HomeAutomationConditionOperand
        if let value = leaf.value {
            if let numeric = Double(value) {
                right = .literalNumber(numeric, unit: nil)
            } else {
                right = .literalString(value)
            }
        } else {
            right = .unsupported(rawValue: leaf.rawText)
        }
        return .comparison(
            HomeAutomationComparisonCondition(
                left: left,
                operatorName: leaf.operatorName ?? .equals,
                right: right
            )
        )
    }

    private static func ruleName(from userText: String) -> String {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Automation" }
        let prefix = trimmed.prefix(60)
        return String(prefix)
    }

    private static func inferIntent(commandName: String, capability: String) -> HomeAutomationIntent {
        switch commandName.lowercased() {
        case "on": return .turnOn
        case "off": return .turnOff
        case "open": return .open
        case "close": return .close
        case "lock": return .lock
        case "unlock": return .unlock
        case "setlevel", "settemperature", "setheatingsetpoint", "setcoolingsetpoint",
             "setcolor", "sethue", "setsaturation":
            return .setValue
        case "start": return .start
        case "stop": return .stop
        case "pause": return .pause
        case "resume": return .resume
        default:
            if capability == "lock" && commandName == "lock" { return .lock }
            if capability == "lock" && commandName == "unlock" { return .unlock }
            return .setValue
        }
    }
}
