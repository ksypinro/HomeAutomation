import Foundation
import HomeAutomationCore
import HomeAutomationOrchestrator
import HomeAutomationAgents
import Observation

enum HomePipelineEventStatus: String, Hashable {
    case pending
    case running
    case completed
    case failed
    case skipped
}

struct HomePipelineEventItem: Identifiable, Hashable {
    let id: String
    let title: String
    var status: HomePipelineEventStatus
    var detail: String
}

struct HomeDeviceDashboardItem: Identifiable, Hashable {
    let id: String
    let name: String
    let room: String
    let deviceType: String
    let risk: String
    let stateSummary: String
}

struct HomeCommandHistoryItem: Identifiable, Hashable {
    let id = UUID()
    let command: String
    let engine: String
    let summary: String
    let timestamp: Date
    let succeeded: Bool
}

struct AgentDashboardItem: Identifiable, Hashable {
    let id: String
    let name: String
    let duration: Double?
    let status: String
    let circuitState: String
}

struct PortfolioEvidenceItem: Identifiable, Hashable {
    let id: String
    let title: String
    let value: String
}

struct ResultCoreDisplay: Hashable {
    let title: String
    let summary: String
    let engine: String
    let statusSystemImage: String
}

struct ResultDetailSection: Identifiable, Hashable {
    let id: String
    let title: String
    let content: String
}

struct AutomationResultDisplay: Hashable {
    let name: String
    let summary: String
    let iconSystemName: String
    let triggerTitle: String
    let triggerSubtitle: String
    let conditionTree: AutomationConditionDisplayNode?
    let actionItems: [AutomationCardItem]
    let smartThingsStatus: String
    let json: String?
}

struct AutomationConditionDisplayNode: Identifiable, Hashable {
    enum Kind: Hashable {
        case all
        case any
        case negated
        case changes
        case condition
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let detail: String
    let systemImage: String
    let children: [AutomationConditionDisplayNode]
}

struct AutomationCardItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let detail: String
    let systemImage: String
}

struct DeviceCommandResultDisplay: Hashable {
    enum Status: Hashable {
        case executed
        case ready
        case confirmationRequired
    }

    let status: Status
    let title: String
    let summary: String
    let statusLabel: String
    let statusSystemImage: String
    let steps: [DeviceCommandStepDisplay]
    let stateItems: [DeviceCommandStateItem]
}

struct DeviceCommandStepDisplay: Identifiable, Hashable {
    let id: String
    let deviceName: String
    let room: String
    let action: String
    let capability: String
    let systemImage: String
}

struct DeviceCommandStateItem: Identifiable, Hashable {
    let id: String
    let name: String
    let value: String
}

struct ArchitectureCardItem: Identifiable, Hashable {
    let id: String
    let title: String
    let value: String
    let detail: String
}

/// User-facing orchestrator strategies. Mirrors the three arms in
/// `OrchestrationArm` — the mode is baked into the runtime dependencies at
/// construction, so switching rebuilds the orchestrator from the retained
/// coordinator (the RAG index is built once and shared across rebuilds).
enum OrchestratorChoice: String, CaseIterable, Identifiable {
    case graph
    case graphTier1
    case verifierLoop
    case adaptiveStatic
    case adaptiveShadow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .graph: return "Graph"
        case .graphTier1: return "Graph + Tier 1"
        case .verifierLoop: return "Verifier Loop"
        case .adaptiveStatic: return "Adaptive Static"
        case .adaptiveShadow: return "Adaptive Shadow"
        }
    }

    var summary: String {
        switch self {
        case .graph:
            return "Full multi-agent graph — the reference pipeline."
        case .graphTier1:
            return "Graph runtime with the deterministic Tier 1 mini-pipeline for automation actions (0–1 FM calls per action)."
        case .verifierLoop:
            return "Deterministic draft → FM verifier → targeted repairs (max 3 iterations); escalates to the graph on failure."
        case .adaptiveStatic:
            return "Static portfolio router actively chooses Graph, Graph + Tier 1, or Verifier Loop inside one shared run."
        case .adaptiveShadow:
            return "Computes the static portfolio decision and rollout evidence, but executes the graph as a safe holdback path."
        }
    }

    var engineName: String {
        switch self {
        case .graph: return "Multi-Agent Orchestrator (Graph)"
        case .graphTier1: return "Multi-Agent Orchestrator (Graph + Tier 1)"
        case .verifierLoop: return "Verifier-Loop Orchestrator"
        case .adaptiveStatic: return "Adaptive Portfolio Orchestrator (Active Static)"
        case .adaptiveShadow: return "Adaptive Portfolio Orchestrator (Shadow Static)"
        }
    }

    var architectureLabel: String {
        switch self {
        case .graph:
            return "Reference graph"
        case .graphTier1:
            return "Graph with Tier‑1 action strategy"
        case .verifierLoop:
            return "Verifier-loop first"
        case .adaptiveStatic:
            return "Portfolio-selected arm"
        case .adaptiveShadow:
            return "Graph execution + shadow decision"
        }
    }

    var rolloutMode: PortfolioRolloutMode {
        switch self {
        case .adaptiveStatic:
            return .activeStatic
        case .adaptiveShadow:
            return .shadowStatic
        case .graph, .graphTier1, .verifierLoop:
            return .disabled
        }
    }

    var orchestrationMode: OrchestrationMode {
        switch self {
        case .verifierLoop:
            return .verifierLoop
        case .adaptiveStatic, .adaptiveShadow:
            return .adaptivePortfolio
        case .graph, .graphTier1:
            return .graph
        }
    }

    var usesMiniPipeline: Bool {
        self == .graphTier1
    }

    var portfolioEligibilityPolicy: PortfolioEligibilityPolicy {
        switch self {
        case .adaptiveStatic, .adaptiveShadow:
            return PortfolioEligibilityPolicy(conditionalTier1Enabled: true)
        case .graph, .graphTier1, .verifierLoop:
            return PortfolioEligibilityPolicy()
        }
    }
}

enum GraphCompilerChoice: String, CaseIterable, Identifiable {
    case disabled
    case shadow
    case active

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .disabled: return "Compiler Off"
        case .shadow: return "Compiler Shadow"
        case .active: return "Compiler Active"
        }
    }

    var summary: String {
        switch self {
        case .disabled:
            return "Use approved static graph templates exactly as authored."
        case .shadow:
            return "Build dependency-minimal graph plans for telemetry while executing static plans."
        case .active:
            return "Execute dependency-minimal graph plans when validation succeeds; fall back safely otherwise."
        }
    }

    var mode: GraphCompilationMode {
        switch self {
        case .disabled: return .disabled
        case .shadow: return .shadow
        case .active: return .active
        }
    }
}

@MainActor
@Observable
final class HomeAutomationViewModel {
    var command = "Set the bedroom lamp to 40 percent"
    var executeLowRiskCommands = true
    var orchestratorChoice: OrchestratorChoice = .graph {
        didSet {
            guard orchestratorChoice != oldValue else { return }
            rebuildOrchestrator()
        }
    }
    var graphCompilerChoice: GraphCompilerChoice = .disabled {
        didSet {
            guard graphCompilerChoice != oldValue else { return }
            rebuildOrchestrator()
        }
    }
    var isRunning = false
    var resultText = ""
    var metricsText = ""
    var errorMessage: String?
    var resultCore: ResultCoreDisplay?
    var resultDetailSections: [ResultDetailSection] = []
    var automationResult: AutomationResultDisplay?
    var deviceCommandResult: DeviceCommandResultDisplay?
    var deviceItems: [HomeDeviceDashboardItem] = []
    var agentDashboard: [AgentDashboardItem] = []
    var commandHistory: [HomeCommandHistoryItem] = []
    var pipelineEvents: [HomePipelineEventItem] = []
    var portfolioEvidence: [PortfolioEvidenceItem] = []
    var architectureCards: [ArchitectureCardItem] = []
    var currentPipelineStage: String?

    private let registry = MockHomeDeviceRegistry()
    private var coordinator: HomeAutomationCoordinator
    private var orchestrator: HomeCommandOrchestrator

    let sampleCommands = [
        "Turn on the living room ceiling light",
        "Turn on bedroom AC everyday at 7 AM",
        "Turn on bedroom AC and turn off the bedroom lamp every day at 7 AM",
        "Turn on bedroom AC everyday at 7 AM if the entry contact sensor is closed",
        "Set the bedroom lamp to 40 percent",
        "Set the bedroom AC fan mode to auto",
        "Make the bedroom AC cooler by 2 degrees",
        "Unlock the front door",
        "Run movie time"
    ]

    init() {
        let initialCoordinator = HomeAutomationCoordinator(deviceRegistry: registry)
        coordinator = initialCoordinator
        orchestrator = initialCoordinator.makeOrchestrator()

        Task {
            await initializeRAG()
        }

        Task.detached {
            HomeFoundationModelPrewarmer.prewarmDefaultSession()
        }

        refreshArchitectureCards()
    }

    func initializeRAG() async {
        coordinator = await HomeCommandOrchestrator.makeRAGEnabledCoordinator(deviceRegistry: registry)
        rebuildOrchestrator()
    }

    /// Mints a fresh orchestrator from the retained coordinator for the
    /// selected mode. The RAG index and device registry are reused; only the
    /// runtime dependencies (agent registry, loop orchestrator) are rebuilt.
    private func rebuildOrchestrator() {
        let dependencies = coordinator.makeRuntimeDependencies(
            orchestrationMode: orchestratorChoice.orchestrationMode,
            useMiniPipeline: orchestratorChoice.usesMiniPipeline,
            portfolioRolloutMode: orchestratorChoice.rolloutMode,
            portfolioEligibilityPolicy: orchestratorChoice.portfolioEligibilityPolicy,
            graphCompilationMode: graphCompilerChoice.mode
        )
        orchestrator = HomeCommandOrchestrator(dependencies: dependencies)
        refreshArchitectureCards()
    }

    func resolveCommand() {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return }

        isRunning = true
        errorMessage = nil
        resultText = ""
        metricsText = ""
        resultCore = nil
        resultDetailSections = []
        automationResult = nil
        deviceCommandResult = nil
        pipelineEvents = []
        agentDashboard = []
        portfolioEvidence = []
        refreshArchitectureCards()
        currentPipelineStage = nil

        Task {
            do {
                var output: HomeAutomationResolverResult?
                let stream = orchestrator.resolveStream(
                    trimmedCommand,
                    executeLowRiskCommands: executeLowRiskCommands
                )
                for try await update in stream {
                    switch update {
                    case .event(let event):
                        upsertPipelineEvent(event)
                        upsertAgentDashboard(event)
                    case .result(let result):
                        output = result
                    }
                }
                guard let output else {
                    throw FoundationLabCoreError.invalidRequest("Orchestrator stream ended without a result")
                }

                let engineName = orchestratorChoice.engineName
                resultText = Self.format(output, engineName: engineName)
                resultCore = Self.makeResultCore(output, engineName: engineName)
                resultDetailSections = Self.makeResultDetailSections(from: resultText)
                automationResult = Self.makeAutomationResult(output)
                deviceCommandResult = Self.makeDeviceCommandResult(output)
                await loadDeviceDashboard()
                metricsText = await orchestrator.lastMetricsJSON() ?? ""
                await refreshAgentDashboardFromMetrics()
                await refreshPortfolioEvidenceFromMetrics()
                await refreshArchitectureCardsFromMetrics()
                currentPipelineStage = nil
                commandHistory.insert(
                    HomeCommandHistoryItem(
                        command: trimmedCommand,
                        engine: orchestratorChoice.displayName,
                        summary: output.resolution.displaySummary,
                        timestamp: Date(),
                        succeeded: output.draft != nil || {
                            if case .executed = output.resolution { return true }
                            if case .readyToExecute = output.resolution { return true }
                            if case .requiresConfirmation = output.resolution { return true }
                            if case .automationDrafted = output.resolution { return true }
                            if case .automationRequiresConfirmation = output.resolution { return true }
                            return false
                        }()
                    ),
                    at: 0
                )
            } catch {
                errorMessage = error.localizedDescription
                resultCore = ResultCoreDisplay(
                    title: "Could not resolve command",
                    summary: error.localizedDescription,
                    engine: orchestratorChoice.engineName,
                    statusSystemImage: "exclamationmark.triangle.fill"
                )
                resultDetailSections = [
                    ResultDetailSection(id: "error", title: "Error", content: error.localizedDescription)
                ]
                automationResult = nil
                deviceCommandResult = nil
                currentPipelineStage = nil
                commandHistory.insert(
                    HomeCommandHistoryItem(
                        command: trimmedCommand,
                        engine: orchestratorChoice.displayName,
                        summary: error.localizedDescription,
                        timestamp: Date(),
                        succeeded: false
                    ),
                    at: 0
                )
            }

            isRunning = false
        }
    }

    func useSample(_ sample: String) {
        command = sample
    }

    func rerun(_ item: HomeCommandHistoryItem) {
        command = item.command
        resolveCommand()
    }

    private func upsertPipelineEvent(_ event: OrchestratorPipelineEvent) {
        let title = Self.pipelineTitle(for: event)
        let item = HomePipelineEventItem(
            id: event.stage,
            title: title,
            status: Self.status(from: event.status),
            detail: event.detail
        )
        if item.status == .running {
            currentPipelineStage = item.title
        } else if currentPipelineStage == item.title {
            currentPipelineStage = nil
        }

        if let index = pipelineEvents.firstIndex(where: { $0.id == item.id }) {
            pipelineEvents[index] = item
        } else {
            pipelineEvents.append(item)
        }
    }

    private func upsertAgentDashboard(_ event: OrchestratorPipelineEvent) {
        guard let agentID = event.agentID else { return }
        let item = AgentDashboardItem(
            id: agentID,
            name: agentID,
            duration: nil,
            status: Self.status(from: event.status).rawValue,
            circuitState: "closed"
        )
        if let index = agentDashboard.firstIndex(where: { $0.id == agentID }) {
            agentDashboard[index] = item
        } else {
            agentDashboard.append(item)
        }
    }

    private func refreshAgentDashboardFromMetrics() async {
        let statuses = await orchestrator.circuitBreakerStatuses()
        let traces = await orchestrator.lastMetrics()?.agentTraces ?? []
        let traceIDs = traces.map { $0.agentID.rawValue }
        let currentIDs = agentDashboard.map(\.id)
        let statusIDs = Array(statuses.keys)
        let ids = stableUnique(traceIDs + currentIDs + statusIDs)

        agentDashboard = ids.map { id in
            let trace = traces.last { $0.agentID.rawValue == id }
            let existing = agentDashboard.first { $0.id == id }
            return AgentDashboardItem(
                id: id,
                name: id,
                duration: trace?.durationSeconds,
                status: trace?.result.rawValue ?? existing?.status ?? "pending",
                circuitState: statuses[id] ?? existing?.circuitState ?? "closed"
            )
        }
    }

    private func refreshPortfolioEvidenceFromMetrics() async {
        guard let evidence = await orchestrator.lastMetrics()?.portfolioRolloutEvidence else {
            portfolioEvidence = []
            return
        }
        portfolioEvidence = [
            PortfolioEvidenceItem(id: "mode", title: "Rollout", value: evidence.rolloutMode.rawValue),
            PortfolioEvidenceItem(id: "selected", title: "Selected", value: evidence.selectedArm?.rawValue ?? "none"),
            PortfolioEvidenceItem(id: "executing", title: "Executing", value: evidence.executingArm.rawValue),
            PortfolioEvidenceItem(id: "fallback", title: "Fallback", value: evidence.fallbackReason.rawValue),
            PortfolioEvidenceItem(id: "canary", title: "Canary", value: evidence.canary.included ? "included" : "graph holdback"),
            PortfolioEvidenceItem(id: "config", title: "Config", value: evidence.configVersion),
            PortfolioEvidenceItem(id: "rollback", title: "Rollback", value: evidence.rollbackReasons.map(\.rawValue).joined(separator: ", ").ifEmpty("none"))
        ]
    }

    private func refreshArchitectureCards() {
        architectureCards = [
            ArchitectureCardItem(
                id: "strategy",
                title: "Execution Strategy",
                value: orchestratorChoice.architectureLabel,
                detail: orchestratorChoice.summary
            ),
            ArchitectureCardItem(
                id: "runContext",
                title: "Run Context",
                value: "One run / event bus / ledger",
                detail: "Input, arm execution, metrics, and terminal outcome share a single orchestration run."
            ),
            ArchitectureCardItem(
                id: "automationAction",
                title: "Automation Actions",
                value: actionStrategyLabel,
                detail: "Action resolution is selected from typed run context, with explicit Tier‑1 rollback preserved."
            ),
            ArchitectureCardItem(
                id: "compiler",
                title: "Graph Compiler",
                value: graphCompilerChoice.displayName,
                detail: graphCompilerChoice.summary
            )
        ]
    }

    private func refreshArchitectureCardsFromMetrics() async {
        guard let metrics = await orchestrator.lastMetrics() else {
            refreshArchitectureCards()
            return
        }
        let executingArm = metrics.portfolioExecutionPlan?.executingArm.rawValue ??
            metrics.portfolioRolloutEvidence?.executingArm.rawValue ??
            orchestratorChoice.orchestrationMode.foundationModelArm.rawValue
        let selectedArm = metrics.portfolioExecutionPlan?.selectedArm.rawValue ??
            metrics.portfolioRolloutEvidence?.selectedArm?.rawValue ??
            executingArm
        let fallbackReason = metrics.portfolioExecutionPlan?.fallbackReason.rawValue ??
            metrics.portfolioRolloutEvidence?.fallbackReason.rawValue ??
            "none"
        let compilerFallback = metrics.graphRun?.compilationReport?.fallbackReason.rawValue ?? "none"
        architectureCards = [
            ArchitectureCardItem(
                id: "strategy",
                title: "Execution Strategy",
                value: "\(selectedArm) → \(executingArm)",
                detail: "Fallback: \(fallbackReason)"
            ),
            ArchitectureCardItem(
                id: "runContext",
                title: "Run Context",
                value: "Completed once",
                detail: "Outcome: \(metrics.outcome); metrics stored after ledger capture."
            ),
            ArchitectureCardItem(
                id: "automationAction",
                title: "Automation Actions",
                value: actionStrategyLabel(for: executingArm),
                detail: "Selected by the active arm and scoped to this run."
            ),
            ArchitectureCardItem(
                id: "compiler",
                title: "Graph Compiler",
                value: graphCompilerChoice.displayName,
                detail: "Fallback: \(compilerFallback)"
            )
        ]
    }

    private var actionStrategyLabel: String {
        actionStrategyLabel(for: orchestratorChoice == .graphTier1 ? "graphWithTier1" : orchestratorChoice.orchestrationMode.foundationModelArm.rawValue)
    }

    private func actionStrategyLabel(for arm: String) -> String {
        arm == "graphWithTier1" ? "Tier‑1 mini-pipeline" : "Graph action subgraphs"
    }

    private static func status(from status: OrchestratorPipelineEvent.EventStatus) -> HomePipelineEventStatus {
        switch status {
        case .pending:
            return .pending
        case .running:
            return .running
        case .completed:
            return .completed
        case .failed:
            return .failed
        case .skipped:
            return .skipped
        }
    }

    private static func pipelineTitle(for event: OrchestratorPipelineEvent) -> String {
        guard let agentID = event.agentID, agentID != event.stage else {
            return event.stage
        }
        return "\(event.stage) (\(agentID))"
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    func deviceCatalogText() async -> String {
        let devices = await registry.allDevices()
        return devices.map { device in
            let room = device.room.map { " in \($0)" } ?? ""
            return "\(device.displayName)\(room): \(device.capabilities.joined(separator: ", "))"
        }
        .joined(separator: "\n")
    }

    func loadDeviceDashboard() async {
        let devices = await registry.allDevices()
        deviceItems = devices.prefix(30).map { device in
            HomeDeviceDashboardItem(
                id: device.id,
                name: device.displayName,
                room: device.room ?? "none",
                deviceType: device.deviceType,
                risk: String(describing: device.riskLevel),
                stateSummary: device.currentState
                    .sorted { $0.key < $1.key }
                    .prefix(3)
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ", ")
            )
        }
    }

    private static func format(_ result: HomeAutomationResolverResult, engineName: String) -> String {
        var sections: [String] = []

        sections.append("""
        Engine:
        \(engineName)
        """)

        sections.append("""
        Resolution:
        \(result.resolution.displaySummary)
        """)

        sections.append("""
        Worker Signals:
        Language: \(result.state.language.languageCode)
        Domain: \(result.state.domain.domain)
        Intent Families: \(result.state.intent.topFamilies)
        Device Types: \(result.state.deviceType.deviceTypes)
        Rooms: \(result.state.slots.rooms)
        Values: \(result.state.slots.values.map { "\($0.name)=\($0.rawValue)" })
        Risk: \(result.state.risk.riskLevel) - \(result.state.risk.reason)
        """)

        sections.append("""
        Candidates:
        Retrieved: \(result.retrievedCandidates.map(\.displayName).joined(separator: ", "))
        Selected IDs: \(result.aggregation.finalCandidateIDs.joined(separator: ", "))
        """)

        if let draft = result.draft {
            sections.append("""
            Draft:
            Intent: \(draft.intent)
            Target: \(draft.targetDeviceID ?? "none")
            Capability: \(draft.capability ?? "none")
            Command: \(draft.command ?? "none")
            Parameters: \(draft.parameters)
            Needs Clarification: \(draft.needsClarification)
            Requires Confirmation: \(draft.requiresConfirmation)
            Confidence: \(draft.confidence)
            """)
        }

        switch result.resolution {
        case .readyToExecute(let plan), .executed(let plan, _):
            sections.append("""
            Execution Plan:
            \(plan.steps.map(Self.describeExecutionStep).joined(separator: "\n"))
            """)
        case .requiresConfirmation(let draft):
            sections.append("Confirmation required for \(draft.intent).")
        case .automationDrafted(let plan), .automationRequiresConfirmation(let plan):
            sections.append(Self.describeAutomationPlan(plan))
        case .needsClarification(let question):
            sections.append("Clarification: \(question)")
        case .unsupported(let reason):
            sections.append("Unsupported: \(reason)")
        }

        return sections.joined(separator: "\n\n")
    }

    private static func makeResultCore(_ result: HomeAutomationResolverResult, engineName: String) -> ResultCoreDisplay {
        let title: String
        let icon: String
        switch result.resolution {
        case .readyToExecute:
            title = "Command ready"
            icon = "checkmark.circle.fill"
        case .executed:
            title = "Command executed"
            icon = "checkmark.circle.fill"
        case .requiresConfirmation, .automationRequiresConfirmation:
            title = "Confirmation needed"
            icon = "exclamationmark.shield.fill"
        case .automationDrafted:
            title = "Automation drafted"
            icon = "calendar.badge.clock"
        case .needsClarification:
            title = "Need a little more detail"
            icon = "questionmark.circle.fill"
        case .unsupported:
            title = "Unsupported command"
            icon = "xmark.octagon.fill"
        }

        return ResultCoreDisplay(
            title: title,
            summary: result.resolution.displaySummary,
            engine: engineName,
            statusSystemImage: icon
        )
    }

    private static func makeResultDetailSections(from text: String) -> [ResultDetailSection] {
        text.components(separatedBy: "\n\n")
            .enumerated()
            .compactMap { index, rawSection in
                let section = rawSection.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !section.isEmpty else { return nil }
                let lines = section.components(separatedBy: .newlines)
                let firstLine = lines.first ?? "Details"
                let title = firstLine.replacingOccurrences(of: ":", with: "")
                let content = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                return ResultDetailSection(
                    id: "\(index)-\(title)",
                    title: title.isEmpty ? "Details" : title,
                    content: content.isEmpty ? section : content
                )
            }
    }

    private static func makeAutomationResult(_ result: HomeAutomationResolverResult) -> AutomationResultDisplay? {
        let plan: HomeAutomationCreationPlan
        switch result.resolution {
        case .automationDrafted(let draftPlan), .automationRequiresConfirmation(let draftPlan):
            plan = draftPlan
        default:
            return nil
        }

        let deviceNames = Dictionary(
            (result.hydratedCandidates + result.retrievedCandidates + plan.resolvedActions.compactMap(\.device))
                .map { ($0.id, $0.displayName) },
            uniquingKeysWith: { first, _ in first }
        )

        let trigger = automationTriggerDisplay(plan.ruleDraft.trigger)
        let conditionTree = plan.ruleDraft.condition.map {
            automationConditionTree($0, path: "condition", deviceNames: deviceNames)
        }
        let actionItems = plan.resolvedActions.enumerated().map { index, action in
            AutomationCardItem(
                id: "action-\(index)-\(action.device?.id ?? action.draft.targetDeviceID ?? UUID().uuidString)",
                title: action.device?.displayName ?? action.draft.targetDeviceID ?? "Unresolved device",
                subtitle: action.device?.room ?? "No room",
                detail: actionDisplayText(action),
                systemImage: iconName(forDeviceType: action.device?.deviceType)
            )
        }

        return AutomationResultDisplay(
            name: plan.name,
            summary: result.resolution.displaySummary,
            iconSystemName: "sun.max.fill",
            triggerTitle: trigger.title,
            triggerSubtitle: trigger.subtitle,
            conditionTree: conditionTree,
            actionItems: actionItems,
            smartThingsStatus: smartThingsStatus(plan),
            json: plan.smartThingsRuleJSON
        )
    }

    private static func makeDeviceCommandResult(_ result: HomeAutomationResolverResult) -> DeviceCommandResultDisplay? {
        let candidates = Dictionary(
            (result.hydratedCandidates + result.retrievedCandidates)
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        switch result.resolution {
        case .executed(let plan, let updatedDevice):
            return DeviceCommandResultDisplay(
                status: .executed,
                title: plan.steps.allSatisfy { $0.type == "query" } ? "Device status retrieved" : "Device command executed",
                summary: result.resolution.displaySummary,
                statusLabel: plan.steps.allSatisfy { $0.type == "query" } ? "Status retrieved" : "Executed on mock devices",
                statusSystemImage: "checkmark.circle.fill",
                steps: commandStepDisplays(plan.steps, candidates: candidates),
                stateItems: stateDisplays(updatedDevice.currentState)
            )

        case .readyToExecute(let plan):
            return DeviceCommandResultDisplay(
                status: .ready,
                title: plan.steps.allSatisfy { $0.type == "query" } ? "Status query ready" : "Device command ready",
                summary: result.resolution.displaySummary,
                statusLabel: plan.steps.allSatisfy { $0.type == "query" } ? "Ready to query" : "Execution is turned off",
                statusSystemImage: "pause.circle.fill",
                steps: commandStepDisplays(plan.steps, candidates: candidates),
                stateItems: []
            )

        case .requiresConfirmation(let draft):
            let target = draft.targetDeviceID.flatMap { candidates[$0] }
            let parameter = parameterDisplay(draft.parameters)
            let action = [draft.command.map(humanize), parameter]
                .compactMap { $0 }
                .joined(separator: " · ")
                .ifEmpty(humanize(String(describing: draft.intent)))
            let step = DeviceCommandStepDisplay(
                id: "confirmation-\(draft.targetDeviceID ?? "unresolved")",
                deviceName: target?.displayName ?? draft.targetDeviceID ?? "Unresolved device",
                room: target?.room ?? "No room",
                action: action,
                capability: draft.capability.map(humanize) ?? "Capability unresolved",
                systemImage: iconName(forDeviceType: target?.deviceType)
            )
            return DeviceCommandResultDisplay(
                status: .confirmationRequired,
                title: "Confirm device command",
                summary: result.resolution.displaySummary,
                statusLabel: "Not executed",
                statusSystemImage: "exclamationmark.shield.fill",
                steps: [step],
                stateItems: []
            )

        case .automationDrafted, .automationRequiresConfirmation, .needsClarification, .unsupported:
            return nil
        }
    }

    private static func commandStepDisplays(
        _ steps: [HomeAutomationExecutionStep],
        candidates: [String: HomeCandidateRecord]
    ) -> [DeviceCommandStepDisplay] {
        steps.enumerated().map { index, step in
            let candidate = candidates[step.deviceID]
            return DeviceCommandStepDisplay(
                id: "step-\(index)-\(step.id.uuidString)",
                deviceName: candidate?.displayName ?? step.deviceName,
                room: candidate?.room ?? "No room",
                action: executionActionDisplay(step),
                capability: humanize(step.capability),
                systemImage: iconName(forDeviceType: candidate?.deviceType)
            )
        }
    }

    private static func executionActionDisplay(_ step: HomeAutomationExecutionStep) -> String {
        let command = humanize(step.command)
        let value = step.valueFormula ?? step.value
        guard let value, !value.isEmpty else { return command }
        return "\(command) · \(value)"
    }

    private static func parameterDisplay(_ parameters: [HomeResolvedParameter]) -> String? {
        let values = parameters.compactMap { parameter -> String? in
            let rawValue: String?
            if let value = parameter.value, !value.isEmpty {
                rawValue = value
            } else if let number = parameter.numericValue {
                rawValue = number.rounded() == number ? String(Int(number)) : String(number)
            } else {
                rawValue = nil
            }
            guard let rawValue else { return nil }
            return [rawValue, parameter.unit].compactMap { $0 }.joined(separator: " ")
        }
        return values.isEmpty ? nil : values.joined(separator: ", ")
    }

    private static func stateDisplays(_ state: [String: String]) -> [DeviceCommandStateItem] {
        state.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { key, value in
                DeviceCommandStateItem(id: key, name: humanize(key), value: value)
            }
    }

    private static func humanize(_ value: String) -> String {
        let spaced = value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
        return spaced
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.lowercased() }
            .joined(separator: " ")
            .capitalized
    }

    private static func automationTriggerDisplay(_ trigger: HomeAutomationTrigger?) -> (title: String, subtitle: String) {
        guard let trigger else { return ("No trigger", "Manual or unresolved trigger") }
        switch trigger {
        case .schedule(let schedule):
            return (
                schedule.timeOfDay?.displayString ?? "Unspecified time",
                schedule.repeatRule.displayString.capitalized
            )
        case .device(let deviceTrigger):
            return (deviceTrigger.description, "Device trigger")
        }
    }

    private static func automationConditionTree(
        _ condition: HomeAutomationCondition,
        path: String,
        deviceNames: [String: String]
    ) -> AutomationConditionDisplayNode {
        switch condition {
        case .and(let children):
            return AutomationConditionDisplayNode(
                id: path,
                kind: .all,
                title: "All of these",
                subtitle: "AND group",
                detail: "Every condition in this group must be met.",
                systemImage: "checkmark.circle.badge.questionmark",
                children: children.enumerated().map {
                    automationConditionTree($0.element, path: "\(path)-\($0.offset)", deviceNames: deviceNames)
                }
            )
        case .or(let children):
            return AutomationConditionDisplayNode(
                id: path,
                kind: .any,
                title: "Any of these",
                subtitle: "OR group",
                detail: "At least one condition in this group must be met.",
                systemImage: "arrow.triangle.branch",
                children: children.enumerated().map {
                    automationConditionTree($0.element, path: "\(path)-\($0.offset)", deviceNames: deviceNames)
                }
            )
        case .not(let child):
            return AutomationConditionDisplayNode(
                id: path,
                kind: .negated,
                title: "Not",
                subtitle: "Negated condition",
                detail: "This condition must not be met.",
                systemImage: "exclamationmark.circle",
                children: [automationConditionTree(child, path: "\(path)-not", deviceNames: deviceNames)]
            )
        case .changes(let child):
            return AutomationConditionDisplayNode(
                id: path,
                kind: .changes,
                title: "When this changes",
                subtitle: "Change trigger",
                detail: "The condition is evaluated when this value changes.",
                systemImage: "arrow.triangle.2.circlepath",
                children: [automationConditionTree(child, path: "\(path)-changes", deviceNames: deviceNames)]
            )
        case .comparison(let comparison):
            return AutomationConditionDisplayNode(
                id: path,
                kind: .condition,
                title: conditionDeviceTitle(comparison.left, deviceNames: deviceNames),
                subtitle: conditionDeviceSubtitle(comparison.left),
                detail: comparison.readableDescription(deviceNames: deviceNames),
                systemImage: iconName(forConditionOperand: comparison.left),
                children: []
            )
        }
    }

    private static func conditionDeviceTitle(
        _ operand: HomeAutomationConditionOperand,
        deviceNames: [String: String]
    ) -> String {
        if case .deviceAttribute(let description, let deviceID, _, _) = operand {
            if let deviceID, let name = deviceNames[deviceID] { return name }
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Condition" : trimmed
        }
        return "Condition"
    }

    private static func conditionDeviceSubtitle(_ operand: HomeAutomationConditionOperand) -> String {
        guard case .deviceAttribute(_, _, let capability, let attribute) = operand else {
            return "Rule condition"
        }
        return [capability, attribute].compactMap { $0 }.joined(separator: " · ").ifEmpty("Device state")
    }

    private static func actionDisplayText(_ action: HomeAutomationResolvedAction) -> String {
        let command = action.draft.command ?? action.originalText
        if let capability = action.draft.capability {
            return "\(capability): \(command)"
        }
        return command
    }

    private static func smartThingsStatus(_ plan: HomeAutomationCreationPlan) -> String {
        if let reason = plan.unsupportedCompilationReason {
            return "Unsupported: \(reason)"
        }
        if plan.backendResponse?.status == .created {
            return "Created in SmartThings"
        }
        if plan.smartThingsRuleJSON != nil {
            return "SmartThings JSON compiled"
        }
        return "Not compiled yet"
    }

    private static func iconName(forConditionOperand operand: HomeAutomationConditionOperand) -> String {
        guard case .deviceAttribute(_, _, let capability, let attribute) = operand else {
            return "checkmark.circle.fill"
        }
        let text = [capability, attribute].compactMap { $0 }.joined(separator: " ").lowercased()
        if text.contains("motion") { return "figure.walk.motion" }
        if text.contains("contact") || text.contains("lock") { return "lock.fill" }
        if text.contains("switch") { return "lightbulb.fill" }
        if text.contains("temperature") || text.contains("thermostat") { return "thermometer.medium" }
        return "sensor.tag.radiowaves.forward.fill"
    }

    private static func iconName(forDeviceType deviceType: String?) -> String {
        let value = (deviceType ?? "").lowercased()
        if value.contains("television") || value.contains("tv") { return "tv.fill" }
        if value.contains("light") || value.contains("lamp") { return "lightbulb.fill" }
        if value.contains("camera") { return "video.fill" }
        if value.contains("lock") { return "lock.fill" }
        if value.contains("thermostat") || value.contains("ac") { return "thermometer.medium" }
        if value.contains("shade") || value.contains("blind") { return "blinds.horizontal.closed" }
        return "switch.2"
    }

    private static func describeExecutionStep(_ step: HomeAutomationExecutionStep) -> String {
        let value = step.valueFormula ?? step.value ?? ""
        let attribute = step.attribute.map { " [\($0)]" } ?? ""
        return "\(step.type): \(step.deviceName) -> \(step.capability).\(step.command)(\(value))\(attribute)"
    }

    private static func describeAutomationPlan(_ plan: HomeAutomationCreationPlan) -> String {
        var sections: [String] = []
        sections.append("""
        Automation:
        Operation: automationCreation
        Name: \(plan.name)
        Trigger: \(plan.ruleDraft.trigger?.displayString ?? "none")
        Conditions:
        \(plan.ruleDraft.condition.map(describeAutomationCondition) ?? "- none")
        Actions:
        \(plan.resolvedActions.map(describeAutomationAction).joined(separator: "\n"))
        Requires Confirmation: \(plan.requiresConfirmation)
        """)
        if let reason = plan.unsupportedCompilationReason {
            sections.append("""
            SmartThings:
            Unsupported: \(reason)
            """)
        } else if let json = plan.smartThingsRuleJSON {
            sections.append("""
            SmartThings:
            compiled

            SmartThings JSON:
            \(json)
            """)
        } else {
            sections.append("""
            SmartThings:
            not compiled
            """)
        }
        return sections.joined(separator: "\n\n")
    }

    private static func describeAutomationAction(_ action: HomeAutomationResolvedAction) -> String {
        let device = action.device?.displayName ?? action.draft.targetDeviceID ?? "unresolved"
        return "- \(action.originalText): \(device) -> \(action.draft.capability ?? "none").\(action.draft.command ?? "none")"
    }

    private static func describeAutomationCondition(_ condition: HomeAutomationCondition) -> String {
        describeAutomationCondition(condition, depth: 0)
    }

    private static func describeAutomationCondition(_ condition: HomeAutomationCondition, depth: Int) -> String {
        let prefix = String(repeating: "  ", count: depth) + "- "
        switch condition {
        case .and(let children):
            return ([prefix + "all"] + children.map { describeAutomationCondition($0, depth: depth + 1) }).joined(separator: "\n")
        case .or(let children):
            return ([prefix + "any"] + children.map { describeAutomationCondition($0, depth: depth + 1) }).joined(separator: "\n")
        case .not(let child):
            return ([prefix + "not"] + [describeAutomationCondition(child, depth: depth + 1)]).joined(separator: "\n")
        case .comparison(let comparison):
            return "\(prefix)\(describeOperand(comparison.left)) \(comparison.operatorName.rawValue) \(describeOperand(comparison.right))"
		case .changes(let child):
			return ([prefix + "any change"] + [describeAutomationCondition(child, depth: depth + 1)]).joined(separator: "\n") //mark need check
		}
    }

    private static func describeOperand(_ operand: HomeAutomationConditionOperand) -> String {
        switch operand {
        case .deviceAttribute(let description, let deviceID, let capability, let attribute):
            let resolved = [deviceID, capability, attribute].compactMap { $0 }.joined(separator: ".")
            return resolved.isEmpty ? description : "\(description) (\(resolved))"
        case .literalString(let value):
            return value
        case .literalNumber(let value, let unit):
            let number = value.rounded() == value ? String(Int(value)) : String(value)
            return [number, unit].compactMap { $0 }.joined(separator: " ")
        case .locationMode(let value):
            return "location \(value)"
        case .unsupported(let rawValue):
            return rawValue
		case .literalRange(let start, let end, let unit):
			return "value is between \(start) \(unit ?? "")and \(end) \(unit ?? "")"  //Mark need check
		}
    }

}

private extension String {
    func ifEmpty(_ replacement: String) -> String {
        isEmpty ? replacement : self
    }
}
