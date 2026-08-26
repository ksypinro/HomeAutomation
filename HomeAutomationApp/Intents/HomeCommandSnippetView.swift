import AppIntents
import HomeAutomationCore
import SwiftUI

/// The snippet body for a `ResolveHomeCommandIntent` run.
///
/// This reuses the app's display models (`DeviceCommandResultDisplay` and
/// friends) and their mapping functions, but not the app's cards: those hardcode
/// `.background(.black.opacity(0.92))` and `.foregroundStyle(.white)`, whereas a
/// snippet is drawn on a system-supplied background that follows the viewer's
/// light/dark setting. So the layout is rebuilt here in semantic colors, and
/// kept tighter — a snippet is a glance, not a dashboard.
struct HomeCommandSnippetView: View {
    let runID: String
    let phase: HomeCommandRunStore.Phase?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch phase {
            case .running(let stage, let fraction):
                RunningSection(stage: stage, fraction: fraction)

            case .finished(let result):
                FinishedSection(result: result)

            case .failed(let message):
                StatusSection(
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .red,
                    title: "Couldn't finish",
                    detail: message
                )

            case .cancelled(let reason):
                StatusSection(
                    systemImage: "stop.circle.fill",
                    tint: .orange,
                    title: reason == .timeout ? "Timed out" : "Stopped",
                    detail: reason == .timeout
                        ? "The pipeline ran out of time before finishing."
                        : "You stopped this run."
                )

            case nil:
                StatusSection(
                    systemImage: "questionmark.circle.fill",
                    tint: .secondary,
                    title: "Result unavailable",
                    detail: "This run is no longer in memory."
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Phases

private struct RunningSection: View {
    let stage: String
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Working on it", systemImage: "gearshape.2.fill")
                .font(.headline)
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
            Text(stage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FinishedSection: View {
    let result: HomeAutomationResolverResult

    var body: some View {
        if let device = HomeAutomationViewModel.makeDeviceCommandResult(result) {
            DeviceCommandSnippetSection(display: device, resolution: result.resolution)
        } else if let automation = HomeAutomationViewModel.makeAutomationResult(result) {
            AutomationSnippetSection(display: automation)
        } else {
            ClarificationSection(resolution: result.resolution)
        }
    }
}

private struct DeviceCommandSnippetSection: View {
    let display: DeviceCommandResultDisplay
    let resolution: HomeCommandResolution

    private var tint: Color {
        switch display.status {
        case .executed: .green
        case .ready: .blue
        case .confirmationRequired: .orange
        }
    }

    private var needsConfirmation: Bool {
        display.status == .confirmationRequired
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SnippetHeader(
                systemImage: display.statusSystemImage,
                tint: tint,
                title: display.title,
                summary: display.summary
            )

            if !display.steps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(display.steps) { step in
                        StepRow(step: step, tint: tint)
                    }
                }
            }

            // Only the first few state values — a snippet is a glance.
            if !display.stateItems.isEmpty {
                HStack(spacing: 8) {
                    ForEach(display.stateItems.prefix(3)) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(item.value)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 11))
                    }
                }
            }

            if needsConfirmation {
                Button(intent: OpenHomeAutomationIntent()) {
                    Label("Review in Home Automation", systemImage: "arrow.up.forward.app.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            } else {
                Label(display.statusLabel, systemImage: display.statusSystemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
    }
}

private struct StepRow: View {
    let step: DeviceCommandStepDisplay
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: step.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(step.deviceName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(step.room) · \(step.action)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The drafted-automation view: the same If / Then structure the app shows in
/// `AutomationResultCard`, including the **full recursive condition tree**.
///
/// Deliberately mirrors the app's layout rather than summarising it — the whole
/// point of this snippet is to see which conditions and actions were drafted.
/// Two differences from the app's card, both forced by the surface: the app's
/// hardcoded black/white is replaced with semantic colors so it reads in either
/// theme, and the "Show JSON" button is dropped because a snippet can only act
/// through `Button(intent:)`, not a closure.
private struct AutomationSnippetSection: View {
    let display: AutomationResultDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 9) {
                Image(systemName: display.iconSystemName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .frame(width: 56, height: 56)
                    .background(.quaternary, in: Circle())

                Text(display.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .background(.quaternary.opacity(0.5), in: Capsule())

                Text(display.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 9) {
                Text("If").font(.title3.weight(.bold))

                AutomationEventRow(
                    systemImage: "clock.fill",
                    title: display.triggerTitle,
                    subtitle: display.triggerSubtitle,
                    detail: nil
                )

                if let conditionTree = display.conditionTree {
                    ConditionNodeView(node: conditionTree, depth: 0)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("Then").font(.title3.weight(.bold))

                ForEach(display.actionItems) { item in
                    AutomationEventRow(
                        systemImage: item.systemImage,
                        title: item.title,
                        subtitle: item.subtitle,
                        detail: item.detail
                    )
                }
            }

            Label(display.smartThingsStatus, systemImage: "checkmark.seal")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Recursive AND / OR / NOT / changes / condition tree, matching
/// `AutomationConditionNodeView` in the app. The nesting rail and the per-kind
/// accent are what make a compound condition readable, so both are kept.
private struct ConditionNodeView: View {
    let node: AutomationConditionDisplayNode
    let depth: Int

    private var isGroup: Bool { !node.children.isEmpty }

    private var accentColor: Color {
        switch node.kind {
        case .all: return .green
        case .any: return .orange
        case .negated: return .red
        case .changes: return .purple
        case .condition: return .cyan
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: node.systemImage)
                    .font(.subheadline)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accentColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(node.title)
                            .font(.subheadline.weight(.semibold))
                        if isGroup {
                            Text(node.subtitle)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accentColor.opacity(0.18), in: Capsule())
                                .foregroundStyle(accentColor)
                        }
                    }
                    if !isGroup {
                        Text(node.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(node.detail)
                        .font(.footnote)
                        .foregroundStyle(isGroup ? AnyShapeStyle(.secondary) : AnyShapeStyle(accentColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if isGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(node.children) { child in
                        ConditionNodeView(node: child, depth: depth + 1)
                    }
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accentColor.opacity(0.55))
                        .frame(width: 3)
                }
            }
        }
        .padding(depth == 0 ? 13 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(depth == 0 ? 0.07 : 0.045),
            in: RoundedRectangle(cornerRadius: depth == 0 ? 17 : 12)
        )
    }
}

private struct AutomationEventRow: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let detail: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.cyan)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.cyan)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 17))
    }
}

private struct ClarificationSection: View {
    let resolution: HomeCommandResolution

    private var isUnsupported: Bool {
        if case .unsupported = resolution { return true }
        return false
    }

    var body: some View {
        StatusSection(
            systemImage: isUnsupported ? "xmark.octagon.fill" : "questionmark.circle.fill",
            tint: isUnsupported ? .red : .yellow,
            title: isUnsupported ? "Unsupported command" : "Need a little more detail",
            detail: resolution.displaySummary
        )
    }
}

// MARK: - Shared pieces

private struct SnippetHeader: View {
    let systemImage: String
    let tint: Color
    let title: String
    let summary: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct StatusSection: View {
    let systemImage: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        SnippetHeader(systemImage: systemImage, tint: tint, title: title, summary: detail)
    }
}
