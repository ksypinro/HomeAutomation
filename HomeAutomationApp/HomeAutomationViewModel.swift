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

/// User-facing orchestrator strategies. Mirrors the three arms in
/// `OrchestrationArm` — the mode is baked into the runtime dependencies at
/// construction, so switching rebuilds the orchestrator from the retained
/// coordinator (the RAG index is built once and shared across rebuilds).
enum OrchestratorChoice: String, CaseIterable, Identifiable {
    case graph
    case graphTier1
    case verifierLoop

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .graph: return "Graph"
        case .graphTier1: return "Graph + Tier 1"
        case .verifierLoop: return "Verifier Loop"
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
        }
    }

    var engineName: String {
        switch self {
        case .graph: return "Multi-Agent Orchestrator (Graph)"
        case .graphTier1: return "Multi-Agent Orchestrator (Graph + Tier 1)"
        case .verifierLoop: return "Verifier-Loop Orchestrator"
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
    var isRunning = false
    var resultText = ""
    var metricsText = ""
    var errorMessage: String?
    var deviceItems: [HomeDeviceDashboardItem] = []
    var agentDashboard: [AgentDashboardItem] = []
    var commandHistory: [HomeCommandHistoryItem] = []
    var pipelineEvents: [HomePipelineEventItem] = []
    var portfolioEvidence: [PortfolioEvidenceItem] = []
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
    }

    func initializeRAG() async {
        coordinator = await HomeCommandOrchestrator.makeRAGEnabledCoordinator(deviceRegistry: registry)
        rebuildOrchestrator()
    }

    /// Mints a fresh orchestrator from the retained coordinator for the
    /// selected mode. The RAG index and device registry are reused; only the
    /// runtime dependencies (agent registry, loop orchestrator) are rebuilt.
    private func rebuildOrchestrator() {
        let dependencies: HomeAutomationRuntimeDependencies
        switch orchestratorChoice {
        case .graph:
            dependencies = coordinator.makeRuntimeDependencies()
        case .graphTier1:
            dependencies = coordinator.makeRuntimeDependencies(useMiniPipeline: true)
        case .verifierLoop:
            dependencies = coordinator.makeRuntimeDependencies(orchestrationMode: .verifierLoop)
        }
        orchestrator = HomeCommandOrchestrator(dependencies: dependencies)
    }

    func resolveCommand() {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return }

        isRunning = true
        errorMessage = nil
        resultText = ""
        metricsText = ""
        pipelineEvents = []
        agentDashboard = []
        portfolioEvidence = []
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
                metricsText = await orchestrator.lastMetricsJSON() ?? ""
                await refreshAgentDashboardFromMetrics()
                await refreshPortfolioEvidenceFromMetrics()
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
