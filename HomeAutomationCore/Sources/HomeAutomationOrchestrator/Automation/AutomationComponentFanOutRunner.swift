import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import OSLog

public struct AutomationComponentFanOutRunner: Sendable {
    private let triggerAgent: AutomationTriggerResolutionAgent
    private let conditionAgent: AutomationConditionClauseResolutionAgent
    private let actionResolver: AutomationActionResolver
    private let registry: any DeviceRegistryProtocol
    private let logger = Logger(subsystem: "HomeAutomation", category: "Automation.ComponentFanOut")

    public init(
        triggerAgent: AutomationTriggerResolutionAgent,
        conditionAgent: AutomationConditionClauseResolutionAgent,
        actionResolver: AutomationActionResolver,
        registry: any DeviceRegistryProtocol
    ) {
        self.triggerAgent = triggerAgent
        self.conditionAgent = conditionAgent
        self.actionResolver = actionResolver
        self.registry = registry
    }

    public func resolve(
        plan: AutomationComponentPlan,
        context: ResolutionContext
    ) async -> AutomationResolvedComponentSet {
        let bridge = context.scopedValue(for: AutomationRuntimeContextKeys.pipelineEventBridge)
        let eventBus = bridge?.eventBus ?? AgentEventBus()
        let runID = bridge?.runID ?? UUID()
        let devices = await registry.allDevices()
        let startedAt = Date()
        let conditionTriggerPolicy: HomeAutomationConditionTriggerPolicy =
            plan.trigger?.kindHint == .device ? .always : .never

        let outcomes = await withTaskGroup(of: AutomationComponentOutcome.self) { group in
            if let trigger = plan.trigger {
                group.addTask {
                    await self.resolveTrigger(
                        trigger,
                        context: context,
                        eventBus: eventBus,
                        runID: runID
                    )
                }
            }

            for action in plan.actions {
                group.addTask {
                    await self.resolveAction(
                        action,
                        context: context,
                        eventBus: eventBus,
                        runID: runID
                    )
                }
            }

            for condition in plan.conditions {
                group.addTask {
                    await self.resolveCondition(
                        condition,
                        devices: devices,
                        triggerPolicy: conditionTriggerPolicy,
                        context: context,
                        eventBus: eventBus,
                        runID: runID
                    )
                }
            }

            var outcomes: [AutomationComponentOutcome] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes
        }

        let aggregationStartedAt = Date()
        let trigger = outcomes.compactMap(\.trigger).first?.trigger
        let actionResults = outcomes.compactMap(\.action)
            .sorted { $0.component.order < $1.component.order }
            .map(\.result)
        let conditionResults = outcomes.compactMap(\.condition)
            .sorted { $0.component.order < $1.component.order }
            .map(\.result)
        let unsupportedFragments = plan.unsupportedFragments + outcomes.flatMap(\.unsupportedFragments)

        await HomeAutomationTelemetry.shared.log(
            "automation.componentFanOut.completed",
            context: HomeAutomationTelemetryScope.current,
            status: "completed",
            durationMs: Date().timeIntervalSince(startedAt) * 1_000,
            payload: [
                "componentCount": String((plan.trigger == nil ? 0 : 1) + plan.actions.count + plan.conditions.count),
                "triggerCount": plan.trigger == nil ? "0" : "1",
                "actionCount": String(plan.actions.count),
                "conditionCount": String(plan.conditions.count),
                "maxConcurrentComponents": String(Self.maxConcurrentComponents(outcomes.map(\.timing))),
                "maxConcurrentComponentsStarted": String(Self.maxConcurrentComponents(outcomes.map(\.timing))),
                "componentStartSpreadMs": String(Self.startSpreadMs(outcomes.map(\.timing))),
                "componentFanOutDurationMs": String(Date().timeIntervalSince(startedAt) * 1_000),
                "componentAggregationDurationMs": String(Date().timeIntervalSince(aggregationStartedAt) * 1_000),
                "failedComponentIDs": outcomes.filter { $0.timing.status != .completed }.map(\.timing.id).joined(separator: ",")
            ]
        )

        logger.info("Resolved automation components: trigger=\(trigger != nil), actions=\(actionResults.count), conditions=\(conditionResults.count)")
        return AutomationResolvedComponentSet(
            trigger: trigger,
            actionResults: actionResults,
            conditionResults: conditionResults,
            conditionTree: plan.conditionTree,
            unsupportedFragments: stableUnique(unsupportedFragments)
        )
    }

    private func resolveTrigger(
        _ component: AutomationTriggerComponent,
        context: ResolutionContext,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> AutomationComponentOutcome {
        let startedAt = Date()
        await publishComponentEvent(componentID: component.id, kind: "trigger", status: .running, eventBus: eventBus, runID: runID)
        let telemetryContext = componentTelemetryContext(
            componentID: component.id,
            kind: "trigger",
            runID: runID,
            agentID: triggerAgent.id
        )
        let output = await DetachedAgentExecutor().runDetachedValue(
            telemetryContext: telemetryContext,
            priority: .userInitiated
        ) {
            do {
                return try await triggerAgent.run(
                    AutomationTriggerResolutionInput(
                        component: component,
                        fullUserText: context.request.text
                    ),
                    context: context
                )
            } catch {
                return AutomationTriggerResolutionOutput(
                    id: component.id,
                    trigger: nil,
                    confidence: 0,
                    unsupportedFragments: [error.localizedDescription]
                )
            }
        }
        let status: OrchestratorPipelineEvent.EventStatus = output.trigger == nil ? .failed : .completed
        await publishComponentEvent(componentID: component.id, kind: "trigger", status: status, eventBus: eventBus, runID: runID)
        let completedAt = Date()
        await logComponentCompletion(
            telemetryContext: telemetryContext,
            startedAt: startedAt,
            completedAt: completedAt,
            status: status,
            payload: ["resolved": .bool(output.trigger != nil)]
        )
        return .trigger(
            component: component,
            result: output,
            timing: AutomationComponentTiming(id: component.id, kind: "trigger", startedAt: startedAt, completedAt: completedAt, status: status)
        )
    }

    private func resolveAction(
        _ component: AutomationActionComponent,
        context: ResolutionContext,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> AutomationComponentOutcome {
        let startedAt = Date()
        await publishComponentEvent(componentID: component.id, kind: "action", status: .running, eventBus: eventBus, runID: runID)
        let telemetryContext = componentTelemetryContext(
            componentID: component.id,
            kind: "action",
            runID: runID,
            agentID: .automationActionResolution,
            actionID: component.id
        )
        let result = await DetachedAgentExecutor().runDetachedValue(
            telemetryContext: telemetryContext,
            priority: .userInitiated
        ) {
            await HomeAutomationTelemetryScope.$current.withValue(telemetryContext) {
                await actionResolver.resolve(
                    component.rawText,
                    eventBus: eventBus,
                    runID: runID
                )
            }
        }
        await publishComponentEvent(
            componentID: component.id,
            kind: "action",
            status: result.isResolved ? .completed : .failed,
            eventBus: eventBus,
            runID: runID
        )
        let completedAt = Date()
        let status: OrchestratorPipelineEvent.EventStatus = result.isResolved ? .completed : .failed
        await logComponentCompletion(
            telemetryContext: telemetryContext,
            startedAt: startedAt,
            completedAt: completedAt,
            status: status,
            payload: [
                "resolved": .bool(result.isResolved),
                "selectedCandidateIDs": .string(result.selectedCandidateIDs.joined(separator: ","))
            ]
        )
        return .action(
            component: component,
            result: result,
            timing: AutomationComponentTiming(id: component.id, kind: "action", startedAt: startedAt, completedAt: completedAt, status: status)
        )
    }

    private func resolveCondition(
        _ component: AutomationConditionComponent,
        devices: [HomeCandidateRecord],
        triggerPolicy: HomeAutomationConditionTriggerPolicy,
        context: ResolutionContext,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> AutomationComponentOutcome {
        let startedAt = Date()
        await publishComponentEvent(componentID: component.id, kind: "condition", status: .running, eventBus: eventBus, runID: runID)
        let telemetryContext = componentTelemetryContext(
            componentID: component.id,
            kind: "condition",
            runID: runID,
            agentID: conditionAgent.id,
            conditionID: component.id
        )
        let result = await DetachedAgentExecutor().runDetachedValue(
            telemetryContext: telemetryContext,
            priority: .userInitiated
        ) {
            do {
                return try await conditionAgent.run(
                    AutomationConditionClauseResolutionInput(
                        component: component,
                        fullUserText: context.request.text,
                        availableDevices: devices,
                        triggerPolicy: triggerPolicy
                    ),
                    context: context
                )
            } catch {
                return AutomationConditionClauseResolutionResult(
                    id: component.id,
                    rawText: component.rawText,
                    condition: nil,
                    records: [],
                    confidence: 0
                )
            }
        }
        await publishComponentEvent(
            componentID: component.id,
            kind: "condition",
            status: result.condition == nil ? .failed : .completed,
            eventBus: eventBus,
            runID: runID
        )
        let completedAt = Date()
        let status: OrchestratorPipelineEvent.EventStatus = result.condition == nil ? .failed : .completed
        await logComponentCompletion(
            telemetryContext: telemetryContext,
            startedAt: startedAt,
            completedAt: completedAt,
            status: status,
            payload: [
                "resolved": .bool(result.condition != nil),
                "confidence": .double(result.confidence)
            ]
        )
        return .condition(
            component: component,
            result: result,
            timing: AutomationComponentTiming(id: component.id, kind: "condition", startedAt: startedAt, completedAt: completedAt, status: status)
        )
    }

    private func componentTelemetryContext(
        componentID: String,
        kind: String,
        runID: UUID,
        agentID: AgentID,
        actionID: String? = nil,
        conditionID: String? = nil
    ) -> HomeAutomationTelemetryContext {
        (HomeAutomationTelemetryScope.current ?? HomeAutomationTelemetryContext())
            .merging(
                spanID: TelemetryTraceContext.makeSpanID(),
                parentSpanID: HomeAutomationTelemetryScope.current?.spanID,
                spanKind: .automationComponent,
                runID: runID.uuidString,
                operation: HomeAutomationOperationKind.automationCreation.rawValue,
                graphID: "automation-component-fan-out",
                stage: "automationComponentFanOut/\(kind):\(componentID)",
                graphNodeID: AgentID.automationComponentFanOut.rawValue,
                agentID: agentID.rawValue,
                agentInvocationID: "\(String(runID.uuidString.prefix(8)))-\(kind)-\(componentID)-\(agentID.rawValue)",
                componentKind: kind,
                componentID: componentID,
                actionID: actionID,
                conditionID: conditionID,
                runtimeMode: "graph"
            )
    }

    private func logComponentCompletion(
        telemetryContext: HomeAutomationTelemetryContext,
        startedAt: Date,
        completedAt: Date,
        status: OrchestratorPipelineEvent.EventStatus,
        payload: [String: TelemetryValue]
    ) async {
        await HomeAutomationTelemetry.shared.log(
            "automation.component.completed",
            context: telemetryContext,
            status: status == .completed ? .completed : .failed,
            spanKind: .automationComponent,
            startedAt: startedAt,
            completedAt: completedAt,
            durationMs: completedAt.timeIntervalSince(startedAt) * 1_000,
            payload: TelemetryPayload(values: payload)
        )
    }

    private func publishComponentEvent(
        componentID: String,
        kind: String,
        status: OrchestratorPipelineEvent.EventStatus,
        eventBus: AgentEventBus,
        runID: UUID
    ) async {
        await eventBus.publish(
            OrchestratorPipelineEvent(
                runID: runID,
                stage: "automationComponentFanOut/\(kind):\(componentID)",
                agentID: AgentID.automationComponentFanOut.rawValue,
                status: status
            )
        )
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed.lowercased()) else { continue }
            seen.insert(trimmed.lowercased())
            result.append(trimmed)
        }
        return result
    }

    private static func maxConcurrentComponents(_ timings: [AutomationComponentTiming]) -> Int {
        let events = timings.flatMap { timing in
            [
                (date: timing.startedAt, delta: 1),
                (date: timing.completedAt, delta: -1)
            ]
        }
        .sorted {
            if $0.date == $1.date { return $0.delta > $1.delta }
            return $0.date < $1.date
        }
        var current = 0
        var maximum = 0
        for event in events {
            current += event.delta
            maximum = max(maximum, current)
        }
        return maximum
    }

    private static func startSpreadMs(_ timings: [AutomationComponentTiming]) -> Double {
        guard let first = timings.map(\.startedAt).min(),
              let last = timings.map(\.startedAt).max() else {
            return 0
        }
        return last.timeIntervalSince(first) * 1_000
    }
}

private enum AutomationComponentOutcome: Sendable {
    case trigger(component: AutomationTriggerComponent, result: AutomationTriggerResolutionOutput, timing: AutomationComponentTiming)
    case action(component: AutomationActionComponent, result: AutomationActionResolutionResult, timing: AutomationComponentTiming)
    case condition(component: AutomationConditionComponent, result: AutomationConditionClauseResolutionResult, timing: AutomationComponentTiming)

    var trigger: (component: AutomationTriggerComponent, trigger: HomeAutomationTrigger?)? {
        if case .trigger(let component, let result, _) = self { return (component, result.trigger) }
        return nil
    }

    var action: (component: AutomationActionComponent, result: AutomationActionResolutionResult)? {
        if case .action(let component, let result, _) = self { return (component, result) }
        return nil
    }

    var condition: (component: AutomationConditionComponent, result: AutomationConditionClauseResolutionResult)? {
        if case .condition(let component, let result, _) = self { return (component, result) }
        return nil
    }

    var timing: AutomationComponentTiming {
        switch self {
        case .trigger(_, _, let timing), .action(_, _, let timing), .condition(_, _, let timing):
            return timing
        }
    }

    var unsupportedFragments: [String] {
        switch self {
        case .trigger(_, let result, _):
            return result.unsupportedFragments
        case .condition(_, let result, _) where result.condition == nil:
            return ["unresolved condition: \(result.rawText)"]
        case .action(_, let result, _) where !result.isResolved:
            return [result.resolution.displaySummary]
        case .action, .condition:
            return []
        }
    }
}

private struct AutomationComponentTiming: Sendable {
    let id: String
    let kind: String
    let startedAt: Date
    let completedAt: Date
    let status: OrchestratorPipelineEvent.EventStatus
}
