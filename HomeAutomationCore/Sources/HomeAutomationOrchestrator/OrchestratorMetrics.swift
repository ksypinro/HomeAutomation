import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import OSLog

/// Tracks contextual footprint metrics such as payload sizes and errors.
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

/// Tracks which safety gates were executed and what risk/confirmation levels were determined.
public struct OrchestratorSafetyMetrics: Sendable, Codable, Equatable {
    public var safetyValidationRan: Bool
    public var parameterValidationRan: Bool
    public var confirmationPolicyRan: Bool
    public var executionPlanningRan: Bool
    public var finalizationReceipt: ResolutionFinalizationReceipt?
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
        finalizationReceipt: ResolutionFinalizationReceipt? = nil,
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
        self.finalizationReceipt = finalizationReceipt
        self.requiresConfirmation = requiresConfirmation
        self.readyOrExecuted = readyOrExecuted
        self.unsupported = unsupported
        self.riskLevel = riskLevel
        self.memoryContributedTarget = memoryContributedTarget
    }
}

/// Tracks the volume of candidates retrieved, hydrated, and selected.
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

public struct OrchestratorAutomationMetrics: Sendable, Codable, Equatable {
    public var operation: String?
    public var runtimeMode: String?
    public var graphID: String?
    public var automationActionCount: Int
    public var automationConditionCount: Int
    public var automationCompilerTarget: String?
    public var automationCompilationSupported: Bool
    public var automationRequiresConfirmation: Bool
    public var automationBackendStatus: String?
    public var automationBackendRuleID: String?
    public var automationBackendLocationID: String?
    public var graphNodeStatuses: [String: String]
    public var selectedAgents: [String: String]

    public init(
        operation: String? = nil,
        runtimeMode: String? = nil,
        graphID: String? = nil,
        automationActionCount: Int = 0,
        automationConditionCount: Int = 0,
        automationCompilerTarget: String? = nil,
        automationCompilationSupported: Bool = false,
        automationRequiresConfirmation: Bool = false,
        automationBackendStatus: String? = nil,
        automationBackendRuleID: String? = nil,
        automationBackendLocationID: String? = nil,
        graphNodeStatuses: [String: String] = [:],
        selectedAgents: [String: String] = [:]
    ) {
        self.operation = operation
        self.runtimeMode = runtimeMode
        self.graphID = graphID
        self.automationActionCount = automationActionCount
        self.automationConditionCount = automationConditionCount
        self.automationCompilerTarget = automationCompilerTarget
        self.automationCompilationSupported = automationCompilationSupported
        self.automationRequiresConfirmation = automationRequiresConfirmation
        self.automationBackendStatus = automationBackendStatus
        self.automationBackendRuleID = automationBackendRuleID
        self.automationBackendLocationID = automationBackendLocationID
        self.graphNodeStatuses = graphNodeStatuses
        self.selectedAgents = selectedAgents
    }
}

public struct RetrievalSourceQualityMetrics: Sendable, Codable, Equatable {
    public var returnedCount: Int
    public var acceptedCount: Int
    public var averageScore: Double
    public var maxScore: Double
    public var lowConfidenceCount: Int

    public init(
        returnedCount: Int = 0,
        acceptedCount: Int = 0,
        averageScore: Double = 0,
        maxScore: Double = 0,
        lowConfidenceCount: Int = 0
    ) {
        self.returnedCount = returnedCount
        self.acceptedCount = acceptedCount
        self.averageScore = averageScore
        self.maxScore = maxScore
        self.lowConfidenceCount = lowConfidenceCount
    }
}

public struct RetrievalQualityMetrics: Sendable, Codable, Equatable {
    public var strategyNames: [String]
    public var averageScore: Double
    public var maxScore: Double
    public var lowScoreSourceCount: Int
    public var sourceMetrics: [String: RetrievalSourceQualityMetrics]
    public var judgeInvoked: Bool
    public var judgeSkipped: Bool
    public var retryCount: Int
    public var reformulatedQueryCount: Int

    public init(
        strategyNames: [String] = [],
        averageScore: Double = 0,
        maxScore: Double = 0,
        lowScoreSourceCount: Int = 0,
        sourceMetrics: [String: RetrievalSourceQualityMetrics] = [:],
        judgeInvoked: Bool = false,
        judgeSkipped: Bool = false,
        retryCount: Int = 0,
        reformulatedQueryCount: Int = 0
    ) {
        self.strategyNames = strategyNames
        self.averageScore = averageScore
        self.maxScore = maxScore
        self.lowScoreSourceCount = lowScoreSourceCount
        self.sourceMetrics = sourceMetrics
        self.judgeInvoked = judgeInvoked
        self.judgeSkipped = judgeSkipped
        self.retryCount = retryCount
        self.reformulatedQueryCount = reformulatedQueryCount
    }
}

/// Tracks language model availability, usage, tool execution, and prompt budget consumption.
public struct FoundationModelUsageMetrics: Sendable, Codable, Equatable {
    public var modelAvailabilityStatus: String
    public var modelCallCount: Int
    public var skippedModelCallCount: Int
    public var completedModelCallCount: Int
    public var failedModelCallCount: Int
    public var cancelledModelCallCount: Int
    public var cancelledBeforeInferenceCount: Int
    public var queueWaitTotalMs: Double
    public var serviceTotalMs: Double
    public var promptCharacterCount: Int
    public var outputCharacterCount: Int
    public var telemetryOverheadMs: Double
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
        completedModelCallCount: Int = 0,
        failedModelCallCount: Int = 0,
        cancelledModelCallCount: Int = 0,
        cancelledBeforeInferenceCount: Int = 0,
        queueWaitTotalMs: Double = 0,
        serviceTotalMs: Double = 0,
        promptCharacterCount: Int = 0,
        outputCharacterCount: Int = 0,
        telemetryOverheadMs: Double = 0,
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
        self.completedModelCallCount = completedModelCallCount
        self.failedModelCallCount = failedModelCallCount
        self.cancelledModelCallCount = cancelledModelCallCount
        self.cancelledBeforeInferenceCount = cancelledBeforeInferenceCount
        self.queueWaitTotalMs = queueWaitTotalMs
        self.serviceTotalMs = serviceTotalMs
        self.promptCharacterCount = promptCharacterCount
        self.outputCharacterCount = outputCharacterCount
        self.telemetryOverheadMs = telemetryOverheadMs
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

/// A comprehensive snapshot of telemetry data for a single orchestrator run.
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
    public var graphRun: GraphRunMetrics?
    public var contextMetrics: OrchestratorContextMetrics
    public var safetyMetrics: OrchestratorSafetyMetrics
    public var candidateMetrics: OrchestratorCandidateMetrics
    public var automationMetrics: OrchestratorAutomationMetrics
    public var foundationModelUsage: FoundationModelUsageMetrics
    public var foundationModelUsageSnapshot: FoundationModelUsageSnapshot?
    public var retrievalQuality: RetrievalQualityMetrics
    public var metricsV2: RunMetricsV2?
    public var loop: LoopRunMetrics?
    public var portfolioMetrics: PortfolioMetrics?
    public var portfolioDecision: PortfolioDecision?
    public var portfolioExecutionPlan: PortfolioArmExecutionPlan?
    public var portfolioRolloutEvidence: PortfolioRolloutEvidence?

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
        self.graphRun = nil
        self.contextMetrics = OrchestratorContextMetrics()
        self.safetyMetrics = OrchestratorSafetyMetrics()
        self.candidateMetrics = OrchestratorCandidateMetrics()
        self.automationMetrics = OrchestratorAutomationMetrics()
        self.foundationModelUsage = FoundationModelUsageMetrics()
        self.foundationModelUsageSnapshot = nil
        self.retrievalQuality = RetrievalQualityMetrics()
        self.metricsV2 = nil
        self.loop = nil
        self.portfolioMetrics = nil
        self.portfolioDecision = nil
        self.portfolioExecutionPlan = nil
        self.portfolioRolloutEvidence = nil
    }

    public mutating func captureEvaluationFields(
        context: ResolutionContext,
        result: HomeAutomationResolverResult
    ) {
        let adaptiveStageDurations = stageDurations.filter { key, _ in
            key == "adaptivePreparation" || key == "portfolioRouter"
        }
        stageDurations = agentTraces.reduce(into: adaptiveStageDurations) { partial, trace in
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
            finalizationReceipt: ResolutionFinalizationReceipt.directCommand(
                graphRun: graphRun,
                resolution: result.resolution
            ),
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
        retrievalQuality = Self.retrievalQualityMetrics(context: context, agentStatuses: agentStatuses)
        captureFoundationModelEligibilityFields(context: context)
        metricsV2 = RunMetricsV2.derive(from: self)
    }

    public mutating func captureAutomationFields(
        operation: HomeOperationDetectionResult,
        graph: OrchestrationGraph,
        result: HomeAutomationResolverResult,
        graphRun: GraphRunMetrics? = nil
    ) {
        let plan = Self.automationPlan(from: result.resolution)
        let statuses = graphRun?.nodeStatuses ?? Self.automationGraphStatuses(graph: graph, result: result)
        let selectedAgents = graphRun?.selectedAgents ?? graph.nodes.reduce(into: [String: String]()) { partial, node in
            partial[node.id] = node.id
        }

        automationMetrics = OrchestratorAutomationMetrics(
            operation: operation.operation.rawValue,
            runtimeMode: "graph",
            graphID: graph.id,
            automationActionCount: plan?.resolvedActions.count ?? 0,
            automationConditionCount: plan?.ruleDraft.condition.map(Self.conditionCount) ?? 0,
            automationCompilerTarget: "SmartThingsRulesV1",
            automationCompilationSupported: plan?.smartThingsRuleJSON != nil,
            automationRequiresConfirmation: plan?.requiresConfirmation ?? {
                if case .automationRequiresConfirmation = result.resolution { return true }
                return false
            }(),
            automationBackendStatus: plan?.backendResponse?.status.rawValue,
            automationBackendRuleID: plan?.backendResponse?.ruleID,
            automationBackendLocationID: plan?.backendResponse?.locationID,
            graphNodeStatuses: statuses.mapValues(\.rawValue),
            selectedAgents: selectedAgents
        )
        self.graphRun = graphRun ?? GraphRunMetrics(
            graphID: graph.id,
            goal: graph.goal,
            finishedAt: finishedAt ?? Date(),
            nodeStatuses: statuses,
            selectedAgents: selectedAgents,
            skippedNodeIDs: statuses.filter { $0.value == .skipped }.map(\.key).sorted(),
            nodeDurations: [:]
        )
        safetyMetrics.finalizationReceipt = ResolutionFinalizationReceipt.automationCreation(
            graphRun: self.graphRun,
            resolution: result.resolution
        )
        metricsV2 = RunMetricsV2.derive(from: self)
    }

    public mutating func captureFoundationModelUsage(
        snapshot: FoundationModelUsageSnapshot,
        selectedArm: FoundationModelCallArm = .unknown
    ) {
        foundationModelUsageSnapshot = snapshot
        foundationModelUsage.modelCallCount = snapshot.summary.actualCallCount
        foundationModelUsage.completedModelCallCount = snapshot.summary.completedCallCount
        foundationModelUsage.failedModelCallCount = snapshot.summary.failedCallCount
        foundationModelUsage.cancelledModelCallCount = snapshot.summary.cancelledCallCount
        foundationModelUsage.cancelledBeforeInferenceCount = snapshot.summary.cancelledBeforeInferenceCount
        foundationModelUsage.queueWaitTotalMs = snapshot.summary.queueWaitTotalMs
        foundationModelUsage.serviceTotalMs = snapshot.summary.serviceTotalMs
        foundationModelUsage.promptCharacterCount = snapshot.summary.promptCharacterCount
        foundationModelUsage.outputCharacterCount = snapshot.summary.outputCharacterCount
        foundationModelUsage.telemetryOverheadMs = snapshot.summary.telemetryOverheadMs
        foundationModelUsage.selectedToolNames = Array(Set(snapshot.entries.flatMap(\.request.selectedToolNames))).sorted()
        foundationModelUsage.toolCount = foundationModelUsage.selectedToolNames.count
        let observedArm = selectedArm == .unknown
            ? snapshot.entries.first?.request.arm ?? .unknown
            : selectedArm
        let selectedUtility = portfolioDecision?.eligibleArms.first {
            $0.arm == portfolioDecision?.selectedArm
        }?.utility.total
        portfolioMetrics = PortfolioMetrics(
            snapshot: snapshot,
            selectedArm: observedArm,
            preparationMs: stageDurations["adaptivePreparation"].map { $0 * 1_000 },
            routerMs: stageDurations["portfolioRouter"].map { $0 * 1_000 },
            eligibleArms: portfolioDecision?.eligibleArms.map(\.arm),
            predictedUtility: selectedUtility
        )
        let failures = snapshot.entries.compactMap(\.failureKind)
        foundationModelUsage.contextWindowFailures = failures.filter { $0 == .contextWindowExceeded }.count
        foundationModelUsage.guardrailFailures = failures.filter { $0 == .guardrailRefusal }.count
        metricsV2 = RunMetricsV2.derive(from: self)
    }

    private static func automationPlan(from resolution: HomeCommandResolution) -> HomeAutomationCreationPlan? {
        switch resolution {
        case .automationDrafted(let plan), .automationRequiresConfirmation(let plan):
            return plan
        case .readyToExecute, .executed, .requiresConfirmation, .needsClarification, .unsupported:
            return nil
        }
    }

    private static func automationGraphStatuses(
        graph: OrchestrationGraph,
        result: HomeAutomationResolverResult
    ) -> [String: GraphNodeRunStatus] {
        var statuses = graph.nodes.reduce(into: [String: GraphNodeRunStatus]()) { partial, node in
            partial[node.id] = .skipped
        }
        statuses[AgentID.operationDetection.rawValue] = .completed

        switch result.resolution {
        case .automationDrafted(let plan), .automationRequiresConfirmation(let plan):
            statuses[AgentID.automationDraft.rawValue] = .completed
            statuses[AgentID.automationConditionOperandResolution.rawValue] = .completed
            statuses[AgentID.automationActionResolution.rawValue] = .completed
            statuses[AgentID.automationValidation.rawValue] = .completed
            statuses[AgentID.smartThingsCompilation.rawValue] = plan.smartThingsRuleJSON == nil ? .skipped : .completed
            statuses[AgentID.smartThingsRuleCreation.rawValue] = plan.backendResponse?.status == .created ? .completed : .skipped
            statuses[AgentID.automationResultAssembly.rawValue] = .completed
        case .needsClarification:
            statuses[AgentID.automationDraft.rawValue] = .completed
            statuses[AgentID.automationConditionOperandResolution.rawValue] = .completed
            statuses[AgentID.automationActionResolution.rawValue] = result.aggregation.needsClarification ? .failed : .completed
            statuses[AgentID.automationValidation.rawValue] = .failed
        case .unsupported:
            statuses[AgentID.automationDraft.rawValue] = .failed
        case .readyToExecute, .executed, .requiresConfirmation:
            break
        }

        return statuses
    }

    private static func conditionCount(_ condition: HomeAutomationCondition) -> Int {
        switch condition {
        case .and(let children), .or(let children):
            return children.map(conditionCount).reduce(1, +)
        case .not(let child):
            return 1 + conditionCount(child)
        case .changes(let child):
            return 1 + conditionCount(child)
        case .comparison:
            return 1
        }
    }

    private static func confidenceByAgent(context: ResolutionContext) -> [String: Double] {
        var values: [String: Double] = [:]
        if let language = context.language ?? context.resolutionState?.language {
            values["operationDetection.language"] = language.confidence
        }
        if let domain = context.domain ?? context.resolutionState?.domain {
            values["operationDetection.domain"] = domain.confidence
        }
        let intent = context.intent ?? context.resolutionState?.intent
        let deviceType = context.deviceType ?? context.resolutionState?.deviceType
        if let intent {
            values["semanticNLU.intent"] = intent.confidence
        }
        if let deviceType {
            values["semanticNLU.deviceType"] = deviceType.confidence
        }
        if let intent, let deviceType {
            values[AgentID.semanticNLU.rawValue] = min(intent.confidence, deviceType.confidence)
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

    private static func retrievalQualityMetrics(
        context: ResolutionContext,
        agentStatuses: [String: String]
    ) -> RetrievalQualityMetrics {
        let reports = context.retrievalReports
        let averages = reports.map(\.averageScore)
        let average = averages.isEmpty ? 0 : averages.reduce(0, +) / Double(averages.count)
        let strategies = reports.map(\.strategy).reduce(into: [String]()) { partial, strategy in
            if !partial.contains(strategy) {
                partial.append(strategy)
            }
        }
        let sourceMetrics = Dictionary(grouping: reports, by: \.source).mapValues { sourceReports in
            let returnedCount = sourceReports.map(\.returnedCount).reduce(0, +)
            let acceptedCount = sourceReports.map(\.acceptedCount).reduce(0, +)
            let weightedScoreTotal = sourceReports.reduce(0) { total, report in
                total + (report.averageScore * Double(report.returnedCount))
            }
            let averageScore = returnedCount == 0 ? 0 : weightedScoreTotal / Double(returnedCount)
            return RetrievalSourceQualityMetrics(
                returnedCount: returnedCount,
                acceptedCount: acceptedCount,
                averageScore: averageScore,
                maxScore: sourceReports.map(\.maxScore).max() ?? 0,
                lowConfidenceCount: sourceReports.filter {
                    $0.returnedCount == 0 || $0.maxScore < $0.minScore || $0.averageScore < 0.01
                }.count
            )
        }
        return RetrievalQualityMetrics(
            strategyNames: strategies,
            averageScore: average,
            maxScore: reports.map(\.maxScore).max() ?? 0,
            lowScoreSourceCount: reports.filter { $0.returnedCount == 0 || $0.maxScore < $0.minScore || $0.averageScore < 0.01 }.count,
            sourceMetrics: sourceMetrics,
            judgeInvoked: agentStatuses[AgentID.retrievalJudge.rawValue] != nil,
            judgeSkipped: reports.contains { $0.agentID == AgentID.retrievalJudge.rawValue && $0.strategy.contains("skipped") },
            retryCount: reports.map(\.retryCount).reduce(0, +),
            reformulatedQueryCount: reports.filter { $0.reformulatedQuery != nil }.count
        )
    }

    private mutating func captureFoundationModelEligibilityFields(context: ResolutionContext) {
        let modelStages: [AgentID] = [
            .operationDetection,
            .semanticNLU,
            .slotExtraction,
            .riskClassification,
            .retrievalJudge,
            .candidateRanking,
            .candidateShard,
            .draftGeneration,
            .draftRepair
        ]
        let statuses = Set(agentStatuses.keys)
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
        foundationModelUsage.skippedModelCallCount = fallbackUsed
            ? modelStages.count
            : Self.estimatedSkippedNLUCount(context: context)
        if foundationModelUsageSnapshot == nil {
            foundationModelUsage.contextWindowFailures = errorKinds.filter { $0 == .contextWindowExceeded }.count
            foundationModelUsage.guardrailFailures = errorKinds.filter { $0 == .guardrailRefusal }.count
        }
        foundationModelUsage.selectedToolNames = selectedToolNames
        foundationModelUsage.toolCount = selectedToolNames.count
        foundationModelUsage.estimatedToolOutputCharacterCount = budgetReport?.estimatedToolOutputCharacterCount ?? 0
        foundationModelUsage.contextBudgetReport = budgetReport
    }

    private static func estimatedSkippedNLUCount(context: ResolutionContext) -> Int {
        let confidence = confidenceByAgent(context: context)
        let thresholds: [String: Double] = [
            AgentID.semanticNLU.rawValue: 0.78,
            AgentID.slotExtraction.rawValue: 0.78,
            AgentID.riskClassification.rawValue: 0.85
        ]
        return thresholds.filter { agentID, threshold in
            confidence[agentID].map { $0 >= threshold } ?? false
        }.count
    }
}

/// A thread-safe repository that stores the most recent metrics payload.
