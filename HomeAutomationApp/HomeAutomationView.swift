import SwiftUI

struct HomeAutomationView: View {
    @State private var viewModel = HomeAutomationViewModel()
    @State private var catalogText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    commandInput
                    sampleCommands
                    executionToggle
                    resolveButton
                    output
                    pipelineTimeline
                    agentPerformanceDashboard
                    metricsOutput
                    deviceDashboard
                    commandHistory
                    catalogPreview
                }
                .padding()
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Home Automation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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

            Text("Resolve smart-home commands with the graph-based multi-agent pipeline, map them to capability-based commands, and execute low-risk actions locally.")
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

    private var executionToggle: some View {
        Toggle(isOn: $viewModel.executeLowRiskCommands) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Execute low-risk mock commands")
                    .font(.headline)
                Text("Risky actions still return a confirmation requirement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .padding(14)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
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
    private var output: some View {
        if let errorMessage = viewModel.errorMessage {
            OutputPanel(title: "Error", text: errorMessage, systemImage: "exclamationmark.triangle")
        } else if !viewModel.resultText.isEmpty {
            OutputPanel(title: "Result", text: viewModel.resultText, systemImage: "checkmark.circle")
        }
    }

    @ViewBuilder
    private var metricsOutput: some View {
        if !viewModel.metricsText.isEmpty {
            OutputPanel(title: "Orchestrator Metrics", text: viewModel.metricsText, systemImage: "chart.xyaxis.line")
        }
    }

    @ViewBuilder
    private var pipelineTimeline: some View {
        if !viewModel.pipelineEvents.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Pipeline", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                    if let currentPipelineStage = viewModel.currentPipelineStage {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(currentPipelineStage)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 76, alignment: .center)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }

                    ForEach(viewModel.pipelineEvents) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: iconName(for: event.status))
                                    .foregroundStyle(iconColor(for: event.status))
                                Text(event.title)
                                    .font(.callout.weight(.semibold))
                                    .lineLimit(1)
                            }

                            Text(event.detail.isEmpty ? event.status.rawValue : event.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var agentPerformanceDashboard: some View {
        if !viewModel.agentDashboard.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Agent Performance", systemImage: "speedometer")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                    ForEach(viewModel.agentDashboard) { item in
                        HStack(spacing: 9) {
                            Circle()
                                .fill(circuitColor(item.circuitState))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                    .font(.caption.monospaced())
                                    .lineLimit(1)
                                Text("\(item.status) - \(item.circuitState)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if let duration = item.duration {
                                Text(String(format: "%.0fms", duration * 1000))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func iconName(for status: HomePipelineEventStatus) -> String {
        switch status {
        case .pending:
            return "circle"
        case .running:
            return "play.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .skipped:
            return "minus.circle.fill"
        }
    }

    private func iconColor(for status: HomePipelineEventStatus) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .skipped:
            return .orange
        }
    }

    private func circuitColor(_ state: String) -> Color {
        switch state {
        case "closed":
            return .green
        case "halfOpen":
            return .yellow
        default:
            return .red
        }
    }

    private var deviceDashboard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Devices", systemImage: "square.grid.2x2")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                ForEach(viewModel.deviceItems) { device in
                    DeviceTile(device: device)
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
                    ForEach(viewModel.commandHistory.prefix(8)) { item in
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
                                    Text("\(item.engine) - \(item.summary)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var catalogPreview: some View {
        OutputPanel(title: "Mock Registry", text: catalogText, systemImage: "list.bullet.rectangle")
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

            Text("\(device.room) - \(device.deviceType)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(device.stateSummary.isEmpty ? "ready" : device.stateSummary)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
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

private struct OutputPanel: View {
    let title: String
    let text: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            Text(text.isEmpty ? "Loading..." : text)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    HomeAutomationView()
}
