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
        if let result = patch.updates[ResolutionContextPatchKey.resolverResult]?.get(HomeAutomationResolverResult.self) {
            context.resolutionState = result.state
            context.retrievedCandidates = result.retrievedCandidates
            context.aggregation = result.aggregation
            context.selectedCandidateIDs = result.aggregation.finalCandidateIDs
            context.hydratedCandidates = result.hydratedCandidates
            context.draft = result.draft
            context.resolution = result.resolution
        }
        if let value = patch.updates[ResolutionContextPatchKey.language]?.get(HomeLanguageDetectionResult.self) {
            context.language = value
        }
        if let value = patch.updates[ResolutionContextPatchKey.domain]?.get(HomeDomainClassificationResult.self) {
            context.domain = value
        }
        if let value = patch.updates[ResolutionContextPatchKey.intent]?.get(HomeIntentFamilyResult.self) {
            context.intent = value
        }
        if let value = patch.updates[ResolutionContextPatchKey.deviceType]?.get(HomeDeviceTypeResult.self) {
            context.deviceType = value
        }
        if let value = patch.updates[ResolutionContextPatchKey.slots]?.get(HomeSlotExtractionResult.self) {
            context.slots = value
        }
        if let value = patch.updates[ResolutionContextPatchKey.risk]?.get(HomeRiskClassificationResult.self) {
            context.risk = value
        }
        if let value = patch.updates[ResolutionContextPatchKey.resolutionState]?.get(HomeResolutionState.self) {
            context.resolutionState = value
        }
        if let value = patch.updates[ResolutionContextPatchKey.retrievedCandidates]?.get([HomeCandidateRecord].self) {
            context.retrievedCandidates = value
        }
        if let value = patch.updates[ResolutionContextPatchKey.selectedCandidateIDs]?.get([String].self) {
            context.selectedCandidateIDs = value
        }
        if let value = patch.updates[ResolutionContextPatchKey.aggregation]?.get(HomeCandidateAggregationResult.self) {
            context.aggregation = value
            context.selectedCandidateIDs = value.finalCandidateIDs
        }
        if let value = patch.updates[ResolutionContextPatchKey.hydratedCandidates]?.get([HomeCandidateRecord].self) {
            context.hydratedCandidates = value
        }
        if let value = patch.updates[ResolutionContextPatchKey.knowledgeSnippets]?.get([KnowledgeSnippet].self) {
            context.knowledgeSnippets.append(contentsOf: value)
        }
        if let value = patch.updates[ResolutionContextPatchKey.instructionPackage]?.get(HomeModelInstructionPackage.self) {
            context.instructionPackage = value
        }
        if let value = patch.updates[ResolutionContextPatchKey.draft]?.get(HomeCommandDraft.self) {
            context.draft = value
        }
        if let value = patch.updates[ResolutionContextPatchKey.executionPlan]?.get(HomeAutomationExecutionPlan.self) {
            context.executionPlan = value
        }
        if let value = patch.updates[ResolutionContextPatchKey.resolution]?.get(HomeCommandResolution.self) {
            context.resolution = value
        }
        refreshResolutionStateIfPossible()
    }

    /// Sets the language detection result.
    public func setLanguage(_ value: HomeLanguageDetectionResult) {
        logger.debug("Setting language: \(value.languageCode, privacy: .public)")
        context.language = value
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
