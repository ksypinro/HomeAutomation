import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import OSLog

public struct AutomationComponentFanOutRunner: Sendable {
    /// Bounds CPU-side concurrency in the fan-out task group. The FM gate
    /// throttles model calls, but unbounded task-group concurrency still
    /// creates N concurrent subgraph stacks (context stores, event buses,
    /// agent wrappers). This cap keeps memory and CPU predictable.
    public static let defaultMaxConcurrentComponents = 6

    private let triggerAgent: AutomationTriggerResolutionAgent
    private let conditionAgent: AutomationConditionClauseResolutionAgent
    private let actionResolver: AutomationActionResolver
    private let registry: any DeviceRegistryProtocol
    private let batchedConditionResolver: BatchedConditionClauseResolver?
    private let segmentationWorker: AutomationComponentSegmentationWorkerSession?
    private let speculativeCompiler: SpeculativeAssemblyCompiler?
    private let speculativeSegmentationThreshold: Double
    private let maxConcurrentComponents: Int
    private let logger = Logger(subsystem: "HomeAutomation", category: "Automation.ComponentFanOut")

    public init(
        triggerAgent: AutomationTriggerResolutionAgent,
        conditionAgent: AutomationConditionClauseResolutionAgent,
        actionResolver: AutomationActionResolver,
        registry: any DeviceRegistryProtocol,
        batchedConditionResolver: BatchedConditionClauseResolver? = nil,
        segmentationWorker: AutomationComponentSegmentationWorkerSession? = nil,
        speculativeCompiler: SpeculativeAssemblyCompiler? = SpeculativeAssemblyCompiler(),
        speculativeSegmentationThreshold: Double = 0.88,
        maxConcurrentComponents: Int = Self.defaultMaxConcurrentComponents
    ) {
        self.triggerAgent = triggerAgent
        self.conditionAgent = conditionAgent
        self.actionResolver = actionResolver
        self.registry = registry
        self.batchedConditionResolver = batchedConditionResolver
        self.segmentationWorker = segmentationWorker
        self.speculativeCompiler = speculativeCompiler
        self.speculativeSegmentationThreshold = speculativeSegmentationThreshold
        self.maxConcurrentComponents = max(1, maxConcurrentComponents)
    }

    public func resolve(
        plan: AutomationComponentPlan,
        context: ResolutionContext
    ) async -> AutomationResolvedComponentSet {
        let useSpeculativeSegmentation = segmentationWorker != nil
            && plan.confidence < speculativeSegmentationThreshold

        if useSpeculativeSegmentation {
            return await resolveWithSpeculativeSegmentation(
                deterministicPlan: plan,
                context: context
            )
        }

        return await resolveComponents(plan: plan, context: context, speculativeLabel: nil)
    }

    private func resolveWithSpeculativeSegmentation(
        deterministicPlan: AutomationComponentPlan,
        context: ResolutionContext
    ) async -> AutomationResolvedComponentSet {
        logger.info("[speculative] Starting Wave 1 on deterministic plan (confidence \(deterministicPlan.confidence)) while FM segmentation runs concurrently.")

        let wave1Result: AutomationResolvedComponentSet
        let fmPlan: AutomationComponentPlan?

        (wave1Result, fmPlan) = await withTaskGroup(
            of: SpeculativeSegmentationOutcome.self
        ) { group in
            group.addTask {
                let result = await self.resolveComponents(
                    plan: deterministicPlan,
                    context: context,
                    speculativeLabel: "wave1"
                )
                return .wave1(result)
            }

            group.addTask {
                guard let worker = self.segmentationWorker else {
                    return .segmentation(nil)
                }
                do {
                    let refined = try await worker.segment(context.request.text)
                    return .segmentation(refined)
                } catch {
                    self.logger.error("[speculative] FM segmentation failed: \(error.localizedDescription, privacy: .public)")
                    return .segmentation(nil)
                }
            }

            var resolvedWave1: AutomationResolvedComponentSet?
            var resolvedFMPlan: AutomationComponentPlan?

            for await outcome in group {
                switch outcome {
                case .wave1(let result):
                    resolvedWave1 = result
                case .segmentation(let plan):
                    resolvedFMPlan = plan
                }
            }

            return (
                resolvedWave1 ?? AutomationResolvedComponentSet(
                    trigger: nil, actionResults: [], conditionResults: [],
                    conditionTree: deterministicPlan.conditionTree, unsupportedFragments: []
                ),
                resolvedFMPlan
            )
        }

        let speculativeResult = await speculativeCompiler?.compile(
            plan: deterministicPlan,
            resolvedComponents: wave1Result,
            context: context
        )

        guard let fmPlan else {
            logger.info("[speculative] FM segmentation failed or unavailable; using Wave 1 results as-is.")
            return attachSpeculativeCompilation(wave1Result, compilation: speculativeResult)
        }

        let diff = Self.diffPlans(deterministic: deterministicPlan, refined: fmPlan)

        if diff.isEmpty {
            logger.info("[speculative] FM plan matches deterministic plan — Wave 1 results are final.")
            await HomeAutomationTelemetry.shared.log(
                "automation.speculativeSegmentation.hit",
                context: HomeAutomationTelemetryScope.current,
                status: "completed",
                payload: [
                    "componentCount": String(deterministicPlan.actions.count + deterministicPlan.conditions.count),
                    "speculativeCompilation": String(speculativeResult != nil)
                ]
            )
            return attachSpeculativeCompilation(wave1Result, compilation: speculativeResult)
        }

        logger.info("[speculative] FM plan differs in \(diff.count) component(s); re-resolving changed components.")
        await HomeAutomationTelemetry.shared.log(
            "automation.speculativeSegmentation.miss",
            context: HomeAutomationTelemetryScope.current,
            status: "completed",
            payload: [
                "changedComponents": diff.map(\.id).joined(separator: ","),
                "changedCount": String(diff.count)
            ]
        )

        let patchedResult = await resolveComponents(
            plan: fmPlan,
            context: context,
            speculativeLabel: "redo"
        )
        return patchedResult
    }

    private func resolveComponents(
        plan: AutomationComponentPlan,
        context: ResolutionContext,
        speculativeLabel: String?
    ) async -> AutomationResolvedComponentSet {
        let bridge = context.scopedValue(for: AutomationRuntimeContextKeys.pipelineEventBridge)
        let eventBus = bridge?.eventBus ?? AgentEventBus()
        let runID = bridge?.runID ?? UUID()
        let devices = await registry.allDevices()
        let startedAt = Date()
        let conditionTriggerPolicy: HomeAutomationConditionTriggerPolicy =
            plan.trigger?.kindHint == .device ? .always : .never

        let useBatchedConditions = batchedConditionResolver != nil && plan.conditions.count >= 2

        enum ComponentWork: Sendable {
            case trigger(AutomationTriggerComponent)
            case action(AutomationActionComponent)
            case condition(AutomationConditionComponent)
            case batchedConditions([AutomationConditionComponent])
        }
        var workQueue: [ComponentWork] = []
        if let trigger = plan.trigger {
            workQueue.append(.trigger(trigger))
        }
        for action in plan.actions {
            workQueue.append(.action(action))
        }
        if useBatchedConditions {
            workQueue.append(.batchedConditions(plan.conditions))
        } else {
            for condition in plan.conditions {
                workQueue.append(.condition(condition))
            }
        }

        let outcomes = await withTaskGroup(of: [AutomationComponentOutcome].self) { group in
            var nextIndex = 0

            func enqueueNext() -> Bool {
                guard nextIndex < workQueue.count else { return false }
                let work = workQueue[nextIndex]
                nextIndex += 1
                switch work {
                case .trigger(let component):
                    group.addTask {
                        [await self.resolveTrigger(
                            component,
                            context: context,
                            eventBus: eventBus,
                            runID: runID
                        )]
                    }
                case .action(let component):
                    group.addTask {
                        [await self.resolveAction(
                            component,
                            context: context,
                            eventBus: eventBus,
                            runID: runID
                        )]
                    }
                case .condition(let component):
                    group.addTask {
                        [await self.resolveCondition(
                            component,
                            devices: devices,
                            triggerPolicy: conditionTriggerPolicy,
                            context: context,
                            eventBus: eventBus,
                            runID: runID
                        )]
                    }
                case .batchedConditions(let components):
                    group.addTask {
                        await self.resolveBatchedConditions(
                            components,
                            devices: devices,
                            triggerPolicy: conditionTriggerPolicy,
                            context: context,
                            eventBus: eventBus,
                            runID: runID
                        )
                    }
                }
                return true
            }

            for _ in 0..<min(maxConcurrentComponents, workQueue.count) {
                _ = enqueueNext()
            }

            var outcomes: [AutomationComponentOutcome] = []
            var clarificationDetected = false
            for await batch in group {
                outcomes.append(contentsOf: batch)
                if batch.contains(where: \.needsClarification) && !clarificationDetected {
                    clarificationDetected = true
                    group.cancelAll()
                }
                if !clarificationDetected {
                    _ = enqueueNext()
                }
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

        var payload: [String: String] = [
            "componentCount": String((plan.trigger == nil ? 0 : 1) + plan.actions.count + plan.conditions.count),
            "triggerCount": plan.trigger == nil ? "0" : "1",
            "actionCount": String(plan.actions.count),
            "conditionCount": String(plan.conditions.count),
            "maxConcurrentComponents": String(Self.maxConcurrentComponents(outcomes.map(\.timing))),
            "maxConcurrentComponentsStarted": String(Self.maxConcurrentComponents(outcomes.map(\.timing))),
            "componentStartSpreadMs": String(Self.startSpreadMs(outcomes.map(\.timing))),
            "componentFanOutDurationMs": String(Date().timeIntervalSince(startedAt) * 1_000),
            "componentAggregationDurationMs": String(Date().timeIntervalSince(aggregationStartedAt) * 1_000),
            "failedComponentIDs": outcomes.filter { $0.timing.status != .completed }.map(\.timing.id).joined(separator: ","),
            "clarificationShortCircuit": String(outcomes.contains { $0.needsClarification }),
            "resolvedComponentCount": String(outcomes.count),
            "cancelledComponentCount": String(max(0, (plan.trigger == nil ? 0 : 1) + plan.actions.count + plan.conditions.count - outcomes.count)),
            "batchedConditions": String(useBatchedConditions)
        ]
        if let speculativeLabel {
            payload["speculativePhase"] = speculativeLabel
        }

        await HomeAutomationTelemetry.shared.log(
            "automation.componentFanOut.completed",
            context: HomeAutomationTelemetryScope.current,
            status: "completed",
            durationMs: Date().timeIntervalSince(startedAt) * 1_000,
            payload: payload
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

    private func resolveBatchedConditions(
        _ components: [AutomationConditionComponent],
        devices: [HomeCandidateRecord],
        triggerPolicy: HomeAutomationConditionTriggerPolicy,
        context: ResolutionContext,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> [AutomationComponentOutcome] {
        guard let resolver = batchedConditionResolver else { return [] }
        let startedAt = Date()

        for component in components {
            await publishComponentEvent(componentID: component.id, kind: "condition.batched", status: .running, eventBus: eventBus, runID: runID)
        }

        let inputs = components.map { component in
            AutomationConditionClauseResolutionInput(
                component: component,
                fullUserText: context.request.text,
                availableDevices: devices,
                triggerPolicy: triggerPolicy
            )
        }

        let results = await resolver.resolveAll(inputs)
        let completedAt = Date()

        return zip(components, results).map { component, result in
            let status: OrchestratorPipelineEvent.EventStatus = result.condition == nil ? .failed : .completed
            return .condition(
                component: component,
                result: result,
                timing: AutomationComponentTiming(
                    id: component.id,
                    kind: "condition.batched",
                    startedAt: startedAt,
                    completedAt: completedAt,
                    status: status
                )
            )
        }
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

    private func attachSpeculativeCompilation(
        _ result: AutomationResolvedComponentSet,
        compilation: SpeculativeCompilationResult?
    ) -> AutomationResolvedComponentSet {
        guard let compilation else { return result }
        return AutomationResolvedComponentSet(
            trigger: result.trigger,
            actionResults: result.actionResults,
            conditionResults: result.conditionResults,
            conditionTree: result.conditionTree,
            unsupportedFragments: result.unsupportedFragments,
            speculativeCompilation: compilation
        )
    }

    private static func startSpreadMs(_ timings: [AutomationComponentTiming]) -> Double {
        guard let first = timings.map(\.startedAt).min(),
              let last = timings.map(\.startedAt).max() else {
            return 0
        }
        return last.timeIntervalSince(first) * 1_000
    }

    public struct ComponentDiff: Sendable {
        public let id: String
        public let kind: String
    }

    public static func diffPlans(
        deterministic: AutomationComponentPlan,
        refined: AutomationComponentPlan
    ) -> [ComponentDiff] {
        var diffs: [ComponentDiff] = []

        if deterministic.trigger?.rawText != refined.trigger?.rawText
            || deterministic.trigger?.kindHint != refined.trigger?.kindHint {
            diffs.append(ComponentDiff(id: refined.trigger?.id ?? "t1", kind: "trigger"))
        }

        let detActions = Dictionary(uniqueKeysWithValues: deterministic.actions.map { ($0.id, $0.rawText) })
        for action in refined.actions {
            if detActions[action.id] != action.rawText {
                diffs.append(ComponentDiff(id: action.id, kind: "action"))
            }
        }
        for action in deterministic.actions where !refined.actions.contains(where: { $0.id == action.id }) {
            diffs.append(ComponentDiff(id: action.id, kind: "action.removed"))
        }

        let detConditions = Dictionary(uniqueKeysWithValues: deterministic.conditions.map { ($0.id, $0.rawText) })
        for condition in refined.conditions {
            if detConditions[condition.id] != condition.rawText {
                diffs.append(ComponentDiff(id: condition.id, kind: "condition"))
            }
        }
        for condition in deterministic.conditions where !refined.conditions.contains(where: { $0.id == condition.id }) {
            diffs.append(ComponentDiff(id: condition.id, kind: "condition.removed"))
        }

        if deterministic.conditionTree != refined.conditionTree {
            let alreadyHasConditionDiff = diffs.contains { $0.kind.hasPrefix("condition") }
            if !alreadyHasConditionDiff {
                diffs.append(ComponentDiff(id: "conditionTree", kind: "conditionTree"))
            }
        }

        return diffs
    }
}

private enum SpeculativeSegmentationOutcome: Sendable {
    case wave1(AutomationResolvedComponentSet)
    case segmentation(AutomationComponentPlan?)
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

    var needsClarification: Bool {
        switch self {
        case .action(_, let result, _):
            return result.needsClarification
        case .trigger, .condition:
            return false
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
