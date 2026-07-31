import SwiftUI

struct HomeAutomationView: View {
    @State private var viewModel = HomeAutomationViewModel()
    @State private var catalogText = ""
    @State private var isShowingCatalog = false
    @State private var isShowingResultDetails = false
    @State private var isShowingRuntimeDetails = false
    @State private var isShowingAutomationJSON = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    commandInput
                    sampleCommands
                    quickControls
                    resolveButton
                    agentBoard
                    resultSummary
                    commandHistory
                }
                .padding()
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Home Automation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        isShowingCatalog = true
                    } label: {
                        Label("Catalog & Registry", systemImage: "list.bullet.rectangle")
                    }

                    Button {
                        isShowingRuntimeDetails = true
                    } label: {
                        Label("Runtime", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $isShowingCatalog) {
                CatalogRegistrySheet(catalogText: catalogText, devices: viewModel.deviceItems)
            }
            .sheet(isPresented: $isShowingResultDetails) {
                ResultDetailsSheet(
                    sections: viewModel.resultDetailSections,
                    metricsText: viewModel.metricsText,
                    pipelineEvents: viewModel.pipelineEvents,
                    agentDashboard: viewModel.agentDashboard,
                    portfolioEvidence: viewModel.portfolioEvidence
                )
            }
            .sheet(isPresented: $isShowingRuntimeDetails) {
                RuntimeDetailsSheet(
                    architectureCards: viewModel.architectureCards,
                    pipelineEvents: viewModel.pipelineEvents,
                    agentDashboard: viewModel.agentDashboard,
                    portfolioEvidence: viewModel.portfolioEvidence,
                    metricsText: viewModel.metricsText
                )
            }
            .sheet(isPresented: $isShowingAutomationJSON) {
                JSONSheet(title: "SmartThings JSON", json: viewModel.automationResult?.json ?? "No JSON available.")
            }
        }
        .task {
            catalogText = await viewModel.deviceCatalogText()
            await viewModel.loadDeviceDashboard()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Home Automation", systemImage: "house.and.flag")
                .font(.largeTitle.weight(.semibold))

            Text("Type a smart-home command. The app will resolve it through the selected architecture and show a clean result first; deeper traces stay one tap away.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var commandInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Command")
                .font(.headline)

            TextField("Turn on the living room light", text: $viewModel.command, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
        }
    }

    private var sampleCommands: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Samples")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                ForEach(viewModel.sampleCommands, id: \.self) { sample in
                    Button {
                        viewModel.useSample(sample)
                    } label: {
                        Text(sample)
                            .font(.callout)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 12)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var quickControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Architecture")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Architecture", selection: $viewModel.orchestratorChoice) {
                        ForEach(OrchestratorChoice.allCases) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(viewModel.isRunning)
                    Text(viewModel.orchestratorChoice.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Compiler")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Graph compiler", selection: $viewModel.graphCompilerChoice) {
                        ForEach(GraphCompilerChoice.allCases) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(viewModel.isRunning)
                    Text(viewModel.graphCompilerChoice.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Toggle(isOn: $viewModel.executeLowRiskCommands) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Execute low-risk mock commands")
                        .font(.callout.weight(.semibold))
                    Text("Risky actions still ask for confirmation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
    }

    private var resolveButton: some View {
        Button {
            viewModel.resolveCommand()
        } label: {
            Label(viewModel.isRunning ? "Resolving..." : "Resolve Command", systemImage: "wand.and.sparkles")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(viewModel.isRunning || viewModel.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @ViewBuilder
    private var agentBoard: some View {
        if !viewModel.agentDashboard.isEmpty {
            AgentBoard(items: viewModel.agentDashboard, isRunActive: viewModel.isRunning)
        }
    }

    @ViewBuilder
    private var resultSummary: some View {
        if viewModel.isRunning || viewModel.resultCore != nil || viewModel.errorMessage != nil {
            VStack(alignment: .leading, spacing: 14) {
                if viewModel.isRunning {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(viewModel.currentPipelineStage ?? "Resolving command")
                                .font(.headline)
                            Text("Running the selected orchestration path.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let core = viewModel.resultCore {
                    ResultCoreCard(core: core) {
                        isShowingResultDetails = true
                    }
                }

                if let automationResult = viewModel.automationResult {
                    AutomationResultCard(display: automationResult) {
                        isShowingAutomationJSON = true
                    }
                }

                if let deviceCommandResult = viewModel.deviceCommandResult {
                    DeviceCommandResultCard(display: deviceCommandResult)
                }
            }
        }
    }

    @ViewBuilder
    private var commandHistory: some View {
        if !viewModel.commandHistory.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("History", systemImage: "clock.arrow.circlepath")
                    .font(.headline)

                VStack(spacing: 8) {
                    ForEach(viewModel.commandHistory.prefix(6)) { item in
                        Button {
                            viewModel.rerun(item)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.succeeded ? "checkmark.circle" : "xmark.circle")
                                    .foregroundStyle(item.succeeded ? .green : .red)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.command)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                    Text("\(item.engine) · \(item.summary)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }
}

private struct ResultCoreCard: View {
    let core: ResultCoreDisplay
    let showDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: core.statusSystemImage)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 5) {
                    Text(core.title)
                        .font(.headline)
                    Text(core.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(core.engine)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }

            Button {
                showDetails()
            } label: {
                Label("Show full result", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct AgentBoard: View {
    let items: [AgentDashboardItem]
    var isRunActive = false
    @State private var isExpanded = false

    private var finished: [AgentDashboardItem] {
        items.filter { !$0.isQueued && !$0.isRunning && !$0.isFailed }
    }

    private var failed: [AgentDashboardItem] {
        items.filter(\.isFailed)
    }

    private var running: [AgentDashboardItem] {
        items.filter(\.isRunning)
    }

    private var queued: [AgentDashboardItem] {
        items.filter(\.isQueued)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                AgentBoardLane(title: "Running", systemImage: "bolt.fill", tint: .blue, items: running)
                AgentBoardLane(title: "Queued", systemImage: "clock.fill", tint: .orange, items: queued)
                AgentBoardLane(title: "Finished", systemImage: "checkmark.circle.fill", tint: .green, items: finished)
                AgentBoardLane(title: "Failed", systemImage: "xmark.octagon.fill", tint: .red, items: failed)
            }
            .padding(.top, 14)
        } label: {
            HStack {
                Label("Agent board", systemImage: "rectangle.3.group")
                    .font(.headline)
                Spacer()
                if isRunActive {
                    Label("Live", systemImage: "circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                } else {
                    Text("Run complete")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text("\(items.count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 18))
        .onAppear {
            isExpanded = isRunActive
        }
        .onChange(of: isRunActive) { _, active in
            withAnimation(.easeInOut(duration: 0.22)) {
                isExpanded = active
            }
        }
    }
}

private struct AgentBoardLane: View {
    let title: String
    let systemImage: String
    let tint: Color
    let items: [AgentDashboardItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("\(items.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.13), in: Capsule())
            }

            if items.isEmpty {
                Text("No agents")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
            } else {
                ForEach(items) { item in
                    AgentBoardCard(item: item, tint: tint)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        }
    }
}

private struct AgentBoardCard: View {
    let item: AgentDashboardItem
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                Image(systemName: item.isRunning ? "waveform.path.ecg" : item.statusIcon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(item.statusLabel)
                    if let duration = item.duration {
                        Text("· \(String(format: "%.0fms", duration * 1000))")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(tint.opacity(0.20), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(0.42), lineWidth: 1)
        }
    }
}

private extension AgentDashboardItem {
    var normalizedStatus: String { status.lowercased() }
    var isRunning: Bool { normalizedStatus == "running" }
    var isQueued: Bool { normalizedStatus == "pending" || normalizedStatus == "queued" }
    var isFailed: Bool {
        ["failed", "retryablefailure", "terminalfailure", "timeout"].contains(normalizedStatus)
    }

    var displayName: String {
        name
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    var statusLabel: String {
        switch normalizedStatus {
        case "success", "completed": return "Completed"
        case "retryablefailure": return "Retry failed"
        case "terminalfailure": return "Failed"
        default: return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var statusIcon: String {
        switch normalizedStatus {
        case "failed", "retryablefailure", "terminalfailure", "timeout": return "xmark"
        case "skipped", "unsupported": return "forward.fill"
        case "pending", "queued": return "clock.fill"
        default: return "checkmark"
        }
    }
}

private struct AutomationResultCard: View {
    let display: AutomationResultDisplay
    let showJSON: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.quaternary.opacity(0.7))
                        .frame(width: 76, height: 76)
                    Image(systemName: display.iconSystemName)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.yellow)
                }

                Text(display.name)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(.quaternary.opacity(0.42), in: Capsule())

                Text(display.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                Text("If")
                    .font(.title.weight(.bold))

                AutomationEventRow(
                    systemImage: "clock.fill",
                    title: display.triggerTitle,
                    subtitle: display.triggerSubtitle,
                    detail: nil
                )

                if let conditionTree = display.conditionTree {
                    AutomationConditionNodeView(node: conditionTree, depth: 0)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Then")
                    .font(.title.weight(.bold))

                VStack(spacing: 10) {
                    ForEach(display.actionItems) { item in
                        AutomationEventRow(
                            systemImage: item.systemImage,
                            title: item.title,
                            subtitle: item.subtitle,
                            detail: item.detail
                        )
                    }
                }
            }

            HStack {
                Label(display.smartThingsStatus, systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if display.json != nil {
                    Button {
                        showJSON()
                    } label: {
                        Label("Show JSON", systemImage: "curlybraces")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(18)
        .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 28))
        .foregroundStyle(.white)
    }
}

private struct DeviceCommandResultCard: View {
    let display: DeviceCommandResultDisplay

    private var accentColor: Color {
        switch display.status {
        case .executed: return .green
        case .ready: return .blue
        case .confirmationRequired: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.16))
                    Image(systemName: display.statusSystemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(accentColor)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 5) {
                    Text(display.title)
                        .font(.title3.weight(.bold))
                    Text(display.summary)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Command")
                    .font(.title2.weight(.bold))

                ForEach(display.steps) { step in
                    DeviceCommandStepRow(step: step, accentColor: accentColor)
                }
            }

            if !display.stateItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Current state")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                        ForEach(display.stateItems) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.58))
                                    .lineLimit(1)
                                Text(item.value)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                        }
                    }
                }
            }

            Label(display.statusLabel, systemImage: display.statusSystemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accentColor)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(accentColor.opacity(0.14), in: Capsule())
        }
        .padding(18)
        .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 28))
        .foregroundStyle(.white)
    }
}

private struct DeviceCommandStepRow: View {
    let step: DeviceCommandStepDisplay
    let accentColor: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: step.systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accentColor)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(step.deviceName)
                    .font(.headline)
                Text(step.action)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(accentColor)
                Text("\(step.room) · \(step.capability)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct AutomationConditionNodeView: View {
    let node: AutomationConditionDisplayNode
    let depth: Int

    private var isGroup: Bool { !node.children.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: node.systemImage)
                    .font(.headline)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accentColor)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(node.title)
                            .font(.headline)
                        if isGroup {
                            Text(node.subtitle)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(accentColor.opacity(0.18), in: Capsule())
                                .foregroundStyle(accentColor)
                        }
                    }
                    if !isGroup {
                        Text(node.subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    Text(node.detail)
                        .font(.callout)
                        .foregroundStyle(isGroup ? .white.opacity(0.62) : .blue)
                }
                Spacer(minLength: 0)
            }

            if isGroup {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(node.children) { child in
                        AutomationConditionNodeView(node: child, depth: depth + 1)
                    }
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accentColor.opacity(0.55))
                        .frame(width: 3)
                }
            }
        }
        .padding(depth == 0 ? 16 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: depth == 0 ? 22 : 15))
    }

    private var accentColor: Color {
        switch node.kind {
        case .all: return .green
        case .any: return .orange
        case .negated: return .red
        case .changes: return .purple
        case .condition: return .cyan
        }
    }

    private var backgroundColor: Color {
        depth == 0 ? .white.opacity(0.09) : .white.opacity(0.055)
    }
}

private struct AutomationEventRow: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let detail: String?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.cyan)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.68))
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.blue)
                }
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct CatalogRegistrySheet: View {
    let catalogText: String
    let devices: [HomeDeviceDashboardItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Registry Devices") {
                    ForEach(devices) { device in
                        DeviceTile(device: device)
                    }
                }

                Section("Catalogue Text") {
                    Text(catalogText.isEmpty ? "Loading..." : catalogText)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Catalog & Registry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ResultDetailsSheet: View {
    let sections: [ResultDetailSection]
    let metricsText: String
    let pipelineEvents: [HomePipelineEventItem]
    let agentDashboard: [AgentDashboardItem]
    let portfolioEvidence: [PortfolioEvidenceItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Result") {
                    ForEach(sections) { section in
                        DisclosureGroup(section.title) {
                            Text(section.content)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(.vertical, 6)
                        }
                    }
                }

                RuntimeDisclosureSections(
                    metricsText: metricsText,
                    pipelineEvents: pipelineEvents,
                    agentDashboard: agentDashboard,
                    portfolioEvidence: portfolioEvidence
                )
            }
            .navigationTitle("Result Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct RuntimeDetailsSheet: View {
    let architectureCards: [ArchitectureCardItem]
    let pipelineEvents: [HomePipelineEventItem]
    let agentDashboard: [AgentDashboardItem]
    let portfolioEvidence: [PortfolioEvidenceItem]
    let metricsText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Architecture") {
                    ForEach(architectureCards) { card in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(card.value)
                                .font(.callout.weight(.semibold))
                            Text(card.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                RuntimeDisclosureSections(
                    metricsText: metricsText,
                    pipelineEvents: pipelineEvents,
                    agentDashboard: agentDashboard,
                    portfolioEvidence: portfolioEvidence
                )
            }
            .navigationTitle("Runtime Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct RuntimeDisclosureSections: View {
    let metricsText: String
    let pipelineEvents: [HomePipelineEventItem]
    let agentDashboard: [AgentDashboardItem]
    let portfolioEvidence: [PortfolioEvidenceItem]

    var body: some View {
        if !pipelineEvents.isEmpty {
            Section("Pipeline") {
                ForEach(pipelineEvents) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(.callout.weight(.semibold))
                        Text(event.detail.isEmpty ? event.status.rawValue : event.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        if !agentDashboard.isEmpty {
            Section("Agents") {
                AgentBoard(items: agentDashboard)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }

        if !portfolioEvidence.isEmpty {
            Section("Adaptive Rollout Evidence") {
                ForEach(portfolioEvidence) { item in
                    LabeledContent(item.title, value: item.value)
                }
            }
        }

        if !metricsText.isEmpty {
            Section("Metrics JSON") {
                DisclosureGroup("Show metrics") {
                    Text(metricsText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct JSONSheet: View {
    let title: String
    let json: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(json)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct DeviceTile: View {
    let device: HomeDeviceDashboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(device.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(device.risk)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(riskColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(riskColor)
            }

            Text("\(device.room) · \(device.deviceType)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(device.stateSummary.isEmpty ? "ready" : device.stateSummary)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 6)
    }

    private var riskColor: Color {
        switch device.risk {
        case "high", "critical":
            return .red
        case "medium":
            return .orange
        default:
            return .green
        }
    }
}

#Preview {
    HomeAutomationView()
}
