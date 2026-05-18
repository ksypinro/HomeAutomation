import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import OSLog

/// Thread-safe store that owns the mutable context and applies typed updates.
public actor ResolutionContextStore {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "ResolutionContextStore")
    private var context: ResolutionContext

    public init(request: CommandRequest) {
        self.context = ResolutionContext(request: request)
    }

    /// Get a read-only snapshot for agents.
    ///
    /// - Returns: A safe, immutable copy of the current context.
    public func snapshot() -> ResolutionContext {
        context
    }

    /// Apply a patch from an agent. Field-specific updates are intentionally typed below.
    ///
    /// - Parameter patch: The `ResolutionContextPatch` containing key-value updates.
    public func apply(_ patch: ResolutionContextPatch) {
        logger.debug("Applying patch from agent: \(patch.agentID.rawValue, privacy: .public)")
        for (key, value) in patch.updates {
            if let applicator = ResolutionContextPatchApplicators.registry[key] {
                applicator(value, &context)
            }
        }
        for (scope, values) in patch.scopedUpdates {
            context.mergeScopedValues(values, in: scope)
        }
        refreshResolutionStateIfPossible()
    }

    /// Sets the language detection result.
    public func setLanguage(_ value: HomeLanguageDetectionResult) {
        logger.debug("Setting language: \(value.languageCode, privacy: .public)")
        context.language = value
    }

    public func setOperation(_ value: HomeOperationDetectionResult) {
        context.operation = value
    }

    /// Sets the domain classification result.
    public func setDomain(_ value: HomeDomainClassificationResult) {
        context.domain = value
    }

    public func setIntent(_ value: HomeIntentFamilyResult) {
        context.intent = value
    }

    public func setDeviceType(_ value: HomeDeviceTypeResult) {
        context.deviceType = value
    }

    public func setSlots(_ value: HomeSlotExtractionResult) {
        context.slots = value
    }

    public func setRisk(_ value: HomeRiskClassificationResult) {
        context.risk = value
    }

    public func setResolutionState(_ value: HomeResolutionState) {
        context.resolutionState = value
    }

    public func setRetrievedCandidates(_ value: [HomeCandidateRecord]) {
        context.retrievedCandidates = value
    }

    public func setSelectedCandidateIDs(_ value: [String]) {
        context.selectedCandidateIDs = value
    }

    public func setAggregation(_ value: HomeCandidateAggregationResult) {
        context.aggregation = value
    }

    public func setHydratedCandidates(_ value: [HomeCandidateRecord]) {
        context.hydratedCandidates = value
    }

    public func setDraft(_ value: HomeCommandDraft) {
        context.draft = value
    }

    public func setInstructionPackage(_ value: HomeModelInstructionPackage) {
        context.instructionPackage = value
    }

    public func setExecutionPlan(_ value: HomeAutomationExecutionPlan) {
        context.executionPlan = value
    }

    public func setScopedValue<Value: Sendable>(
        _ value: Value,
        for key: ScopedContextKey<Value>
    ) {
        logger.debug("Setting scoped context value \(key.name, privacy: .public) in \(key.scope.description, privacy: .public).")
        context.setScopedValue(value, for: key)
    }

    public func scopedValue<Value: Sendable>(
        for key: ScopedContextKey<Value>
    ) -> Value? {
        context.scopedValue(for: key)
    }

    /// Sets the command resolution outcome.
    public func setResolution(_ value: HomeCommandResolution) {
        logger.debug("Setting final resolution.")
        context.resolution = value
    }

    /// Appends RAG knowledge snippets to the context.
    public func appendKnowledge(_ snippets: [KnowledgeSnippet]) {
        logger.debug("Appending \(snippets.count, privacy: .public) knowledge snippets.")
        context.knowledgeSnippets.append(contentsOf: snippets)
    }

    public func appendRetrievalReports(_ reports: [KnowledgeRetrievalReport]) {
        context.retrievalReports.append(contentsOf: reports)
    }

    /// Appends a conversational memory hint.
    public func appendMemoryHint(_ hint: MemoryHint) {
        context.memoryHints.append(hint)
    }

    /// Appends an agent execution trace.
    public func appendTrace(_ entry: AgentTraceEntry) {
        context.trace.append(entry)
    }

    /// Appends an agent failure record.
    public func appendError(_ error: AgentFailure) {
        logger.warning("Appending error from agent \(error.agentID.rawValue, privacy: .public): \(error.reason, privacy: .public)")
        context.errors.append(error)
    }

    private func refreshResolutionStateIfPossible() {
        guard let language = context.language,
              let domain = context.domain,
              let intent = context.intent,
              let deviceType = context.deviceType,
              let slots = context.slots,
              let risk = context.risk else {
            return
        }
        context.resolutionState = HomeResolutionState(
            rawText: context.request.text,
            language: language,
            domain: domain,
            intent: intent,
            deviceType: deviceType,
            slots: slots,
            risk: risk
        )
    }
}
