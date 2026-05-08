import Foundation
import HomeAutomationCore
import HomeAutomationOrchestrator
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

@MainActor
@Observable
final class HomeAutomationViewModel {
    var command = "Set the bedroom lamp to 40 percent"
    var executeLowRiskCommands = true
    var isRunning = false
    var resultText = ""
    var metricsText = ""
    var errorMessage: String?
    var deviceItems: [HomeDeviceDashboardItem] = []
    var agentDashboard: [AgentDashboardItem] = []
    var commandHistory: [HomeCommandHistoryItem] = []
    var pipelineEvents: [HomePipelineEventItem] = []
    var currentPipelineStage: String?

    private let registry = MockHomeDeviceRegistry()
    private var orchestrator: HomeCommandOrchestrator

    let sampleCommands = [
        "Turn on the living room ceiling light",
        "Set the bedroom lamp to 40 percent",
        "Set the bedroom AC fan mode to auto",
        "Make the bedroom AC cooler by 2 degrees",
        "Unlock the front door",
        "Run movie time"
    ]

    init() {
        orchestrator = HomeCommandOrchestrator(deviceRegistry: registry)
        Task {
            await initializeRAG()
        }
    }

    func initializeRAG() async {
        orchestrator = await HomeCommandOrchestrator.makeRAGEnabled(deviceRegistry: registry)
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

                let engineName = "Multi-Agent Orchestrator"
                resultText = Self.format(output, engineName: engineName)
                metricsText = await orchestrator.lastMetricsJSON() ?? ""
                await refreshAgentDashboardFromMetrics()
                currentPipelineStage = nil
                commandHistory.insert(
                    HomeCommandHistoryItem(
                        command: trimmedCommand,
                        engine: "Orchestrator",
                        summary: output.resolution.displaySummary,
                        timestamp: Date(),
                        succeeded: output.draft != nil || {
                            if case .executed = output.resolution { return true }
                            if case .readyToExecute = output.resolution { return true }
                            if case .requiresConfirmation = output.resolution { return true }
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
                        engine: "Orchestrator",
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
        let item = HomePipelineEventItem(
            id: event.agentID ?? event.stage,
            title: event.agentID ?? event.stage,
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

}
