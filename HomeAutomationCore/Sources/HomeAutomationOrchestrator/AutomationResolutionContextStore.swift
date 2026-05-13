import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import OSLog

public actor AutomationResolutionContextStore {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "AutomationResolutionContextStore")
    private var context: AutomationResolutionContext

    public init(
        request: CommandRequest,
        operation: HomeOperationDetectionResult
    ) {
        self.context = AutomationResolutionContext(
            request: request,
            operation: operation
        )
    }

    public init(context: AutomationResolutionContext) {
        self.context = context
    }

    public func snapshot() -> AutomationResolutionContext {
        context
    }

    public func setDraft(_ value: HomeAutomationRuleDraft?) {
        logger.debug("Setting automation rule draft.")
        context.draft = value
    }

    public func setResolvedActions(_ value: [HomeAutomationResolvedAction]) {
        logger.debug("Setting \(value.count, privacy: .public) resolved automation action(s).")
        context.resolvedActions = value
    }

    public func appendResolvedAction(_ value: HomeAutomationResolvedAction) {
        logger.debug("Appending resolved automation action.")
        context.resolvedActions.append(value)
    }

    public func setValidation(_ value: AutomationValidationResult?) {
        context.validation = value
    }

    public func setSmartThingsRule(_ value: SmartThingsRuleDocument?) {
        context.smartThingsRule = value
    }

    public func setResolution(_ value: AutomationCreationResolution?) {
        context.resolution = value
    }

    public func appendTrace(_ entry: AgentTraceEntry) {
        context.trace.append(entry)
    }

    public func appendError(_ error: AgentFailure) {
        logger.warning("Appending automation error from \(error.agentID.rawValue, privacy: .public): \(error.reason, privacy: .public)")
        context.errors.append(error)
    }
}
