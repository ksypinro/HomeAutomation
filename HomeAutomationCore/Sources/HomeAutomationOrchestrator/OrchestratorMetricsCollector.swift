import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import os

public struct OrchestratorContextMetrics: Sendable, Codable, Equatable {
    public var commandCharacterCount: Int
    public var knowledgeSnippetCount: Int
    public var memoryHintCount: Int
    public var errorCount: Int
    public var hasInstructionPackage: Bool
    public var hasDraft: Bool
    public var executionStepCount: Int

    public init(
        commandCharacterCount: Int = 0,
        knowledgeSnippetCount: Int = 0,
        memoryHintCount: Int = 0,
        errorCount: Int = 0,
        hasInstructionPackage: Bool = false,
        hasDraft: Bool = false,
        executionStepCount: Int = 0
    ) {
        self.commandCharacterCount = commandCharacterCount
        self.knowledgeSnippetCount = knowledgeSnippetCount
        self.memoryHintCount = memoryHintCount
        self.errorCount = errorCount
        self.hasInstructionPackage = hasInstructionPackage
        self.hasDraft = hasDraft
        self.executionStepCount = executionStepCount
    }
}

public struct OrchestratorSafetyMetrics: Sendable, Codable, Equatable {
    public var safetyValidationRan: Bool
    public var parameterValidationRan: Bool
    public var confirmationPolicyRan: Bool
    public var executionPlanningRan: Bool
    public var requiresConfirmation: Bool
    public var readyOrExecuted: Bool
    public var unsupported: Bool
    public var riskLevel: String?
    public var memoryContributedTarget: Bool

    public init(
        safetyValidationRan: Bool = false,
        parameterValidationRan: Bool = false,
        confirmationPolicyRan: Bool = false,
        executionPlanningRan: Bool = false,
        requiresConfirmation: Bool = false,
        readyOrExecuted: Bool = false,
        unsupported: Bool = false,
        riskLevel: String? = nil,
        memoryContributedTarget: Bool = false
    ) {
        self.safetyValidationRan = safetyValidationRan
        self.parameterValidationRan = parameterValidationRan
        self.confirmationPolicyRan = confirmationPolicyRan
        self.executionPlanningRan = executionPlanningRan
        self.requiresConfirmation = requiresConfirmation
        self.readyOrExecuted = readyOrExecuted
        self.unsupported = unsupported
        self.riskLevel = riskLevel
        self.memoryContributedTarget = memoryContributedTarget
    }
}

public struct OrchestratorCandidateMetrics: Sendable, Codable, Equatable {
    public var retrievedCandidateCount: Int
    public var hydratedCandidateCount: Int
    public var selectedCandidateCount: Int
    public var selectedCandidateIDs: [String]
    public var needsClarification: Bool
    public var aggregationConfidence: Double?
    public var memoryHintCount: Int

    public init(
        retrievedCandidateCount: Int = 0,
        hydratedCandidateCount: Int = 0,
        selectedCandidateCount: Int = 0,
        selectedCandidateIDs: [String] = [],
        needsClarification: Bool = false,
        aggregationConfidence: Double? = nil,
        memoryHintCount: Int = 0
    ) {
        self.retrievedCandidateCount = retrievedCandidateCount
        self.hydratedCandidateCount = hydratedCandidateCount
        self.selectedCandidateCount = selectedCandidateCount
        self.selectedCandidateIDs = selectedCandidateIDs
        self.needsClarification = needsClarification
        self.aggregationConfidence = aggregationConfidence
        self.memoryHintCount = memoryHintCount
    }
}

public struct FoundationModelUsageMetrics: Sendable, Codable, Equatable {
    public var modelAvailabilityStatus: String
    public var modelCallCount: Int
    public var skippedModelCallCount: Int
    public var contextWindowFailures: Int
    public var guardrailFailures: Int
    public var selectedDraftAttempt: String?
    public var adapterAttemptOutcome: String?
    public var perStageModelUsage: [String: String]
    public var selectedToolNames: [String]
    public var toolCount: Int
    public var estimatedToolOutputCharacterCount: Int
    public var contextBudgetReport: HomeModelContextBudgetReport?

    public init(
        modelAvailabilityStatus: String = "unknown",
        modelCallCount: Int = 0,
        skippedModelCallCount: Int = 0,
        contextWindowFailures: Int = 0,
        guardrailFailures: Int = 0,
        selectedDraftAttempt: String? = nil,
        adapterAttemptOutcome: String? = nil,
        perStageModelUsage: [String: String] = [:],
        selectedToolNames: [String] = [],
        toolCount: Int = 0,
        estimatedToolOutputCharacterCount: Int = 0,
        contextBudgetReport: HomeModelContextBudgetReport? = nil
    ) {
        self.modelAvailabilityStatus = modelAvailabilityStatus
        self.modelCallCount = modelCallCount
        self.skippedModelCallCount = skippedModelCallCount
        self.contextWindowFailures = contextWindowFailures
        self.guardrailFailures = guardrailFailures
        self.selectedDraftAttempt = selectedDraftAttempt
        self.adapterAttemptOutcome = adapterAttemptOutcome
        self.perStageModelUsage = perStageModelUsage
        self.selectedToolNames = selectedToolNames
        self.toolCount = toolCount
        self.estimatedToolOutputCharacterCount = estimatedToolOutputCharacterCount
        self.contextBudgetReport = contextBudgetReport
    }
}

public struct OrchestratorMetrics: Sendable, Codable {
    public var command: String
    public var startedAt: Date
    public var finishedAt: Date?
    public var agentTraces: [AgentTraceEntry]
    public var outcome: String
    public var fallbackUsed: Bool
    public var totalDuration: Double?
    public var circuitStates: [String: String]
    public var stageDurations: [String: Double]
    public var agentStatuses: [String: String]
    public var agentConfidence: [String: Double]
    public var contextMetrics: OrchestratorContextMetrics
    public var safetyMetrics: OrchestratorSafetyMetrics
    public var candidateMetrics: OrchestratorCandidateMetrics
    public var foundationModelUsage: FoundationModelUsageMetrics

    public init(command: String) {
        self.command = command
        self.startedAt = Date()
        self.agentTraces = []
        self.outcome = "started"
        self.fallbackUsed = false
        self.circuitStates = [:]
        self.stageDurations = [:]
        self.agentStatuses = [:]
        self.agentConfidence = [:]
        self.contextMetrics = OrchestratorContextMetrics()
        self.safetyMetrics = OrchestratorSafetyMetrics()
        self.candidateMetrics = OrchestratorCandidateMetrics()
        self.foundationModelUsage = FoundationModelUsageMetrics()
    }

    public mutating func captureEvaluationFields(
        context: ResolutionContext,
        result: HomeAutomationResolverResult
    ) {
        stageDurations = agentTraces.reduce(into: [:]) { partial, trace in
            partial[trace.agentID.rawValue] = trace.durationSeconds
        }
        agentStatuses = agentTraces.reduce(into: [:]) { partial, trace in
            partial[trace.agentID.rawValue] = trace.result.rawValue
        }
        agentConfidence = Self.confidenceByAgent(context: context)
        contextMetrics = OrchestratorContextMetrics(
            commandCharacterCount: context.request.text.count,
            knowledgeSnippetCount: context.knowledgeSnippets.count,
            memoryHintCount: context.memoryHints.count,
            errorCount: context.errors.count,
            hasInstructionPackage: context.instructionPackage != nil,
            hasDraft: context.draft != nil,
            executionStepCount: context.executionPlan?.steps.count ?? 0
        )
        candidateMetrics = OrchestratorCandidateMetrics(
            retrievedCandidateCount: context.retrievedCandidates.count,
            hydratedCandidateCount: context.hydratedCandidates.count,
            selectedCandidateCount: result.aggregation.finalCandidateIDs.count,
            selectedCandidateIDs: result.aggregation.finalCandidateIDs,
            needsClarification: result.aggregation.needsClarification,
            aggregationConfidence: result.aggregation.confidence,
            memoryHintCount: context.memoryHints.count
        )
        safetyMetrics = OrchestratorSafetyMetrics(
            safetyValidationRan: agentStatuses[AgentID.safetyValidation.rawValue] != nil,
            parameterValidationRan: agentStatuses[AgentID.parameterValidation.rawValue] != nil,
            confirmationPolicyRan: agentStatuses[AgentID.confirmationPolicy.rawValue] != nil,
            executionPlanningRan: agentStatuses[AgentID.executionPlanning.rawValue] != nil,
            requiresConfirmation: {
                if case .requiresConfirmation = result.resolution { return true }
                return false
            }(),
            readyOrExecuted: {
                if case .readyToExecute = result.resolution { return true }
                if case .executed = result.resolution { return true }
                return false
            }(),
            unsupported: {
                if case .unsupported = result.resolution { return true }
                return false
            }(),
            riskLevel: String(describing: context.resolutionState?.risk.riskLevel ?? context.risk?.riskLevel ?? result.state.risk.riskLevel),
            memoryContributedTarget: context.draft?.targetDeviceID.map { targetID in
                context.memoryHints.contains { $0.deviceID == targetID }
            } ?? false
        )
        captureFoundationModelFields(context: context)
    }

    private static func confidenceByAgent(context: ResolutionContext) -> [String: Double] {
        var values: [String: Double] = [:]
        if let language = context.language ?? context.resolutionState?.language {
            values[AgentID.language.rawValue] = language.confidence
        }
        if let domain = context.domain ?? context.resolutionState?.domain {
            values[AgentID.domain.rawValue] = domain.confidence
        }
        if let intent = context.intent ?? context.resolutionState?.intent {
            values[AgentID.intentFamily.rawValue] = intent.confidence
        }
        if let deviceType = context.deviceType ?? context.resolutionState?.deviceType {
            values[AgentID.deviceType.rawValue] = deviceType.confidence
        }
        if let slots = context.slots ?? context.resolutionState?.slots {
            values[AgentID.slotExtraction.rawValue] = slots.confidence
        }
        if let risk = context.risk ?? context.resolutionState?.risk {
            values[AgentID.riskClassification.rawValue] = risk.confidence
        }
        if let aggregation = context.aggregation {
            values[AgentID.candidateRanking.rawValue] = aggregation.confidence
        }
        if let draft = context.draft {
            values[AgentID.draftGeneration.rawValue] = draft.confidence
        }
        return values
    }

    private mutating func captureFoundationModelFields(context: ResolutionContext) {
        let modelStages: [AgentID] = [
            .language,
            .domain,
            .intentFamily,
            .deviceType,
            .slotExtraction,
            .riskClassification,
            .candidateRanking,
            .candidateShard,
            .draftGeneration,
            .draftRepair
        ]
        let statuses = Set(agentStatuses.keys)
        let executedModelStages = modelStages.filter { statuses.contains($0.rawValue) }
        var stageUsage = foundationModelUsage.perStageModelUsage
        for stage in modelStages {
            if fallbackUsed {
                stageUsage[stage.rawValue] = "skippedUnavailable"
            } else if statuses.contains(stage.rawValue) {
                stageUsage[stage.rawValue] = "eligible"
            }
        }

        let errorKinds = context.errors.map { FoundationModelDiagnostics.failureKind(forDescription: $0.reason) }
        let budgetReport = context.instructionPackage?.contextBudgetReport
        let selectedToolNames = budgetReport?.selectedToolNames ?? context.instructionPackage?.tools.map(\.name) ?? []

        foundationModelUsage.perStageModelUsage = stageUsage
        foundationModelUsage.modelCallCount = fallbackUsed ? 0 : executedModelStages.count
        foundationModelUsage.skippedModelCallCount = fallbackUsed
            ? modelStages.count
            : Self.estimatedSkippedNLUCount(context: context)
        foundationModelUsage.contextWindowFailures = errorKinds.filter { $0 == .contextWindowExceeded }.count
        foundationModelUsage.guardrailFailures = errorKinds.filter { $0 == .guardrailRefusal }.count
        foundationModelUsage.selectedToolNames = selectedToolNames
        foundationModelUsage.toolCount = selectedToolNames.count
        foundationModelUsage.estimatedToolOutputCharacterCount = budgetReport?.estimatedToolOutputCharacterCount ?? 0
        foundationModelUsage.contextBudgetReport = budgetReport
    }

    private static func estimatedSkippedNLUCount(context: ResolutionContext) -> Int {
        let confidence = confidenceByAgent(context: context)
        let thresholds: [String: Double] = [
            AgentID.language.rawValue: 0.90,
            AgentID.domain.rawValue: 0.80,
            AgentID.intentFamily.rawValue: 0.78,
            AgentID.deviceType.rawValue: 0.78,
            AgentID.slotExtraction.rawValue: 0.78,
            AgentID.riskClassification.rawValue: 0.85
        ]
        return thresholds.filter { agentID, threshold in
            confidence[agentID].map { $0 >= threshold } ?? false
        }.count
    }
}

public actor OrchestratorMetricsCollector {
    private let logger = Logger(subsystem: "HomeAutomation", category: "Orchestrator")
    private var last: OrchestratorMetrics?

    public init() {}

    public func store(_ metrics: OrchestratorMetrics) {
        last = metrics
        logger.info("Outcome: \(metrics.outcome)")
    }

    public func lastJSON() -> String? {
        guard let metrics = last,
              let data = try? JSONEncoder().encode(metrics) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func lastMetrics() -> OrchestratorMetrics? {
        last
    }
}
