import Foundation

public enum AutomationValidationSeverity: String, Sendable, Hashable, Codable {
    case warning
    case error
}

public struct AutomationValidationIssue: Sendable, Hashable, Codable {
    public let code: String
    public let message: String
    public let severity: AutomationValidationSeverity

    public init(
        code: String,
        message: String,
        severity: AutomationValidationSeverity
    ) {
        self.code = code
        self.message = message
        self.severity = severity
    }
}

public enum AutomationValidationStatus: String, Sendable, Hashable, Codable {
    case valid
    case needsClarification
    case requiresConfirmation
    case unsupported
}

public struct AutomationValidationResult: Sendable, Hashable, Codable {
    public let issues: [AutomationValidationIssue]
    public let requiresConfirmation: Bool
    public let status: AutomationValidationStatus
    public let clarificationQuestion: String?
    public let unsupportedCompilationReason: String?

    public init(
        issues: [AutomationValidationIssue] = [],
        requiresConfirmation: Bool = false,
        status: AutomationValidationStatus? = nil,
        clarificationQuestion: String? = nil,
        unsupportedCompilationReason: String? = nil
    ) {
        self.issues = issues
        self.requiresConfirmation = requiresConfirmation
        self.clarificationQuestion = clarificationQuestion
        self.unsupportedCompilationReason = unsupportedCompilationReason
        self.status = status ?? Self.derivedStatus(
            issues: issues,
            requiresConfirmation: requiresConfirmation
        )
    }

    public var isValid: Bool {
        !issues.contains { $0.severity == .error }
    }

    public var blockingMessage: String? {
        issues.first { $0.severity == .error }?.message
    }

    private static func derivedStatus(
        issues: [AutomationValidationIssue],
        requiresConfirmation: Bool
    ) -> AutomationValidationStatus {
        let errors = issues.filter { $0.severity == .error }
        if errors.contains(where: {
            let code = $0.code.lowercased()
            return code.contains("clarification") || code.contains("unresolved")
        }) {
            return .needsClarification
        }
        if !errors.isEmpty {
            return .unsupported
        }
        if requiresConfirmation {
            return .requiresConfirmation
        }
        return .valid
    }
}

public struct AutomationValidationPolicy: Sendable {
    public let minimumIntervalMinutes: Int

    public init(minimumIntervalMinutes: Int = 5) {
        self.minimumIntervalMinutes = minimumIntervalMinutes
    }

    public func validate(
        draft: HomeAutomationRuleDraft,
        resolvedActions: [HomeAutomationResolvedAction]
    ) -> AutomationValidationResult {
        var issues: [AutomationValidationIssue] = []
        var requiresConfirmation = false
        var clarificationQuestion: String?
        var unsupportedCompilationReason: String?

        validateTriggerAndSchedule(
            draft.trigger,
            condition: draft.condition,
            issues: &issues,
            unsupportedCompilationReason: &unsupportedCompilationReason
        )
        validateActions(
            draft: draft,
            resolvedActions: resolvedActions,
            issues: &issues,
            requiresConfirmation: &requiresConfirmation,
            clarificationQuestion: &clarificationQuestion
        )
        validateConditionTree(
            draft.condition,
            path: "condition",
            issues: &issues,
            clarificationQuestion: &clarificationQuestion
        )
        if case .device(let trigger) = draft.trigger {
            validateConditionTree(
                trigger.condition,
                path: "trigger.condition",
                issues: &issues,
                clarificationQuestion: &clarificationQuestion
            )
        }

        return AutomationValidationResult(
            issues: issues,
            requiresConfirmation: requiresConfirmation,
            clarificationQuestion: clarificationQuestion,
            unsupportedCompilationReason: unsupportedCompilationReason
        )
    }

    private func validateTriggerAndSchedule(
        _ trigger: HomeAutomationTrigger?,
        condition: HomeAutomationCondition?,
        issues: inout [AutomationValidationIssue],
        unsupportedCompilationReason: inout String?
    ) {
        guard let trigger else {
            if condition == nil {
                issues.append(
                    issue(
                        "automation.trigger.missing",
                        "Automation needs a schedule, device trigger, or supported event condition.",
                        .error
                    )
                )
            }
            return
        }

        switch trigger {
        case .schedule(let schedule):
            switch schedule.repeatRule {
            case .everyDay:
                if schedule.timeOfDay == nil {
                    issues.append(
                        issue(
                            "automation.schedule.timeMissing",
                            "Daily schedules need an explicit time.",
                            .error
                        )
                    )
                }
            case .interval(let value, let unit):
                if unit == .minute, value < minimumIntervalMinutes {
                    issues.append(
                        issue(
                            "automation.schedule.tooFrequent",
                            "Automation interval is too frequent for unattended execution.",
                            .error
                        )
                    )
                }
            case .daysOfWeek:
                let reason = "SmartThings Rules v1 compilation does not support schedule: weekday schedule"
                unsupportedCompilationReason = reason
                issues.append(issue("automation.schedule.unsupportedCompilation", reason, .warning))
            case .unsupported(let rawValue):
                let reason = "Unsupported schedule: \(rawValue)"
                unsupportedCompilationReason = reason
                issues.append(issue("automation.schedule.unsupportedCompilation", reason, .warning))
            case .once:
                break
            }
        case .device:
            break
        }
    }

    private func validateActions(
        draft: HomeAutomationRuleDraft,
        resolvedActions: [HomeAutomationResolvedAction],
        issues: inout [AutomationValidationIssue],
        requiresConfirmation: inout Bool,
        clarificationQuestion: inout String?
    ) {
        if draft.actionDescriptions.isEmpty && resolvedActions.isEmpty {
            issues.append(
                issue(
                    "automation.action.missing",
                    "Automation needs at least one action.",
                    .error
                )
            )
            return
        }

        if resolvedActions.count < draft.actionDescriptions.count {
            let missing = draft.actionDescriptions.dropFirst(resolvedActions.count).first ?? "one action"
            clarificationQuestion = "I could not resolve automation action: \(missing). Which device or command should it use?"
            issues.append(
                issue(
                    "automation.action.unresolved",
                    clarificationQuestion ?? "Automation action needs clarification.",
                    .error
                )
            )
        }

        for action in resolvedActions {
            validateAction(
                action,
                trigger: draft.trigger,
                issues: &issues,
                requiresConfirmation: &requiresConfirmation,
                clarificationQuestion: &clarificationQuestion
            )
        }
    }

    private func validateAction(
        _ action: HomeAutomationResolvedAction,
        trigger: HomeAutomationTrigger?,
        issues: inout [AutomationValidationIssue],
        requiresConfirmation: inout Bool,
        clarificationQuestion: inout String?
    ) {
        guard let capability = nonEmpty(action.draft.capability),
              let command = nonEmpty(action.draft.command) else {
            issues.append(
                issue(
                    "automation.action.invalidCommand",
                    "Automation action '\(action.originalText)' did not resolve to a valid command.",
                    .error
                )
            )
            return
        }

        guard let definition = HomeCapabilityRegistry.definitions[capability] else {
            issues.append(
                issue(
                    "automation.action.unsupportedCapability",
                    "Automation action uses unsupported capability '\(capability)'.",
                    .error
                )
            )
            return
        }

        if !definition.commands.contains(command) {
            issues.append(
                issue(
                    "automation.action.unsupportedCommand",
                    "Automation action uses unsupported command '\(command)' for \(capability).",
                    .error
                )
            )
        }

        guard action.device != nil, nonEmpty(action.draft.targetDeviceID) != nil else {
            clarificationQuestion = "Which device should automation action '\(action.originalText)' control?"
            issues.append(
                issue(
                    "automation.action.deviceClarification",
                    clarificationQuestion ?? "Automation action needs a target device.",
                    .error
                )
            )
            return
        }

        let actionRisk = max(
            action.device?.riskLevel ?? .low,
            definition.riskLevel
        )
        if actionRisk.isHighOrCritical || commandRequiresConfirmation(command, capability: capability) {
            requiresConfirmation = true
            issues.append(
                issue(
                    "automation.action.requiresConfirmation",
                    "Automation action '\(action.originalText)' controls a high-risk device or command.",
                    .warning
                )
            )
        }

        if trigger != nil, unattendedCommandRequiresConfirmation(command, capability: capability) {
            requiresConfirmation = true
        }
    }

    private func validateConditionTree(
        _ condition: HomeAutomationCondition?,
        path: String,
        issues: inout [AutomationValidationIssue],
        clarificationQuestion: inout String?
    ) {
        guard let condition else { return }
        switch condition {
        case .and(let children), .or(let children):
            if children.isEmpty {
                issues.append(
                    issue(
                        "automation.condition.emptyGroup",
                        "Automation condition group '\(path)' is empty.",
                        .error
                    )
                )
            }
            for (index, child) in children.enumerated() {
                validateConditionTree(
                    child,
                    path: "\(path).\(index)",
                    issues: &issues,
                    clarificationQuestion: &clarificationQuestion
                )
            }
        case .not(let child):
            validateConditionTree(
                child,
                path: "\(path).not",
                issues: &issues,
                clarificationQuestion: &clarificationQuestion
            )
        case .comparison(let comparison):
            validateOperand(
                comparison.left,
                path: "\(path).left",
                issues: &issues,
                clarificationQuestion: &clarificationQuestion
            )
            validateOperand(
                comparison.right,
                path: "\(path).right",
                issues: &issues,
                clarificationQuestion: &clarificationQuestion
            )
        }
    }

    private func validateOperand(
        _ operand: HomeAutomationConditionOperand,
        path: String,
        issues: inout [AutomationValidationIssue],
        clarificationQuestion: inout String?
    ) {
        switch operand {
        case .deviceAttribute(let description, let deviceID, let capability, let attribute):
            guard nonEmpty(deviceID) != nil,
                  let capability = nonEmpty(capability),
                  let attribute = nonEmpty(attribute) else {
                clarificationQuestion = "Which device or sensor should condition '\(description)' use?"
                issues.append(
                    issue(
                        "automation.condition.operandClarification",
                        clarificationQuestion ?? "Automation condition operand needs clarification.",
                        .error
                    )
                )
                return
            }
            guard let definition = HomeCapabilityRegistry.definitions[capability] else {
                issues.append(
                    issue(
                        "automation.condition.unsupportedCapability",
                        "Condition uses unsupported capability '\(capability)' at \(path).",
                        .error
                    )
                )
                return
            }
            guard definition.attributeNames.contains(attribute) else {
                issues.append(
                    issue(
                        "automation.condition.unreadableAttribute",
                        "Condition uses unreadable attribute '\(attribute)' for \(capability).",
                        .error
                    )
                )
                return
            }
        case .unsupported(let rawValue):
            issues.append(
                issue(
                    "automation.condition.unsupportedOperand",
                    "Unsupported condition operand: \(rawValue)",
                    .error
                )
            )
        case .literalString, .literalNumber, .locationMode:
            break
        }
    }

    private func issue(
        _ code: String,
        _ message: String,
        _ severity: AutomationValidationSeverity
    ) -> AutomationValidationIssue {
        AutomationValidationIssue(code: code, message: message, severity: severity)
    }

    private func commandRequiresConfirmation(_ command: String, capability: String) -> Bool {
        if capability == "lock" && command == "unlock" { return true }
        if ["garageDoorControl", "doorControl", "valve"].contains(capability), command == "open" { return true }
        if ["ovenMode", "ovenSetpoint", "videoStream", "imageCapture"].contains(capability) { return true }
        return false
    }

    private func unattendedCommandRequiresConfirmation(_ command: String, capability: String) -> Bool {
        commandRequiresConfirmation(command, capability: capability)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private extension HomeAutomationRiskLevel {
    var severity: Int {
        switch self {
        case .low:
            return 0
        case .medium:
            return 1
        case .high:
            return 2
        case .critical:
            return 3
        }
    }

    var isHighOrCritical: Bool {
        severity >= HomeAutomationRiskLevel.high.severity
    }
}

private func max(
    _ lhs: HomeAutomationRiskLevel,
    _ rhs: HomeAutomationRiskLevel
) -> HomeAutomationRiskLevel {
    lhs.severity >= rhs.severity ? lhs : rhs
}
