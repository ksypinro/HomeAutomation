# FoundationModel Automation Component Agents And Parallel Execution Plan

## Summary

Refactor automation creation so trigger resolution, action resolution, and condition resolution are independent FoundationModel-backed agent branches that run concurrently after a lightweight component segmentation step.

The target behavior for:

```text
Turn on bedroom AC and turn off the bedroom lamp every day at 7 AM if living room ceiling light is off and living room tv is off
```

is:

```text
automationComponentSegmentation
  └─ parallel component task group
       ├─ trigger:t1        every day at 7 AM
       ├─ action:a1         Turn on bedroom AC
       ├─ action:a2         Turn off the bedroom lamp
       ├─ condition:c1      living room ceiling light is off
       └─ condition:c2      living room tv is off
  └─ automationDraftAssembly
  └─ automationValidation
  └─ smartThingsCompilation
  └─ smartThingsRuleCreation
  └─ automationResultAssembly
```

Each component branch must execute through a detached Swift task and its own per-invocation actor. Shared mutable state remains owned only by `ResolutionContextStore`.

## Current State

- `AutomationConditionParser` is deterministic parser code, not an agent.
- `AutomationTriggerExtractor` is deterministic parser code, not an agent.
- `AutomationConditionOperandResolver` uses FoundationModels, but it is an orchestrator helper wrapped by `AutomationConditionOperandResolutionAgent`.
- `GraphScheduler` already uses `withTaskGroup` and event-driven readiness for graph nodes, but node execution uses `group.addTask`, not `Task.detached`.
- `AutomationActionResolver` fans out actions with a task group, but action work is nested helper orchestration rather than a first-class component task tree.
- `ResolutionContextStore` is already an actor and should remain the only mutation owner.

## Key Type And API Additions

Add new agent IDs:

```swift
AgentID.automationComponentSegmentation
AgentID.automationTriggerResolution
AgentID.automationConditionClauseResolution
AgentID.automationDraftAssembly
AgentID.automationComponentFanOut
```

Add component models:

```swift
public struct AutomationComponentPlan: Sendable, Hashable, Codable {
    public let trigger: AutomationTriggerComponent?
    public let actions: [AutomationActionComponent]
    public let conditions: [AutomationConditionComponent]
    public let conditionTree: AutomationConditionTreeDescriptor?
    public let unsupportedFragments: [String]
    public let confidence: Double
}

public struct AutomationTriggerComponent: Sendable, Hashable, Codable {
    public let id: String       // "t1"
    public let rawText: String  // "every day at 7 AM"
    public let kindHint: AutomationTriggerKindHint // schedule/device/unknown
}

public struct AutomationActionComponent: Sendable, Hashable, Codable {
    public let id: String       // "a1", "a2"
    public let rawText: String
    public let order: Int
}

public struct AutomationConditionComponent: Sendable, Hashable, Codable {
    public let id: String       // "c1", "c2"
    public let rawText: String
    public let order: Int
}

public enum AutomationConditionTreeDescriptor: Sendable, Hashable, Codable {
    case leaf(String)
    case and([AutomationConditionTreeDescriptor])
    case or([AutomationConditionTreeDescriptor])
    case not(AutomationConditionTreeDescriptor)
}
```

Add resolved component aggregate:

```swift
public struct AutomationResolvedComponentSet: Sendable, Hashable {
    public let trigger: HomeAutomationTrigger?
    public let actionResults: [AutomationActionResolutionResult]
    public let conditionResults: [AutomationConditionClauseResolutionResult]
    public let conditionTree: AutomationConditionTreeDescriptor?
    public let unsupportedFragments: [String]
}
```

Add detached execution infrastructure:

```swift
public actor AgentInvocationActor {
    public let invocationID: String
    public func run(
        agent: any AnyHomeAgent,
        context: ResolutionContext,
        telemetryContext: HomeAutomationTelemetryContext
    ) async -> AgentRunResult
}

public struct DetachedAgentExecutor: Sendable {
    public func runDetached(
        agent: any AnyHomeAgent,
        context: ResolutionContext,
        telemetryContext: HomeAutomationTelemetryContext,
        priority: TaskPriority
    ) async -> AgentRunResult
}
```

`DetachedAgentExecutor` must use `Task.detached`, explicitly reapply task-local telemetry context, and cancel the detached task from a cancellation handler.

## Implementation Changes

### Phase 1 — Introduce Detached Per-Agent Execution

- Add `AgentInvocationActor`, one instance per agent invocation, not one global actor per agent type.
- Add `DetachedAgentExecutor` and route graph node execution through it.
- Replace direct `selection.agent.run(context:)` inside `GraphNodeExecutionLoop` with:
  - immutable context snapshot passed into detached task
  - per-invocation actor wrapping the actual run
  - explicit telemetry context propagation
  - explicit cancellation propagation
- Keep `ResolutionContextStore` as the only mutable context actor.
- Do not let detached agents call `contextStore.apply` directly. Agents return patches; scheduler commits patches.
- Preserve timeout, retry, circuit breaker, transition policy, and safety gate behavior.

Implementation rule:

```swift
Task.detached {
    await HomeAutomationTelemetryScope.$current.withValue(telemetryContext) {
        await invocationActor.run(agent: agent, context: context, telemetryContext: telemetryContext)
    }
}
```

Acceptance:

- Every graph node execution logs a unique `agentInvocationID`.
- No agent runs on `MainActor`.
- Cancelling a graph run cancels all detached agent tasks.
- Existing direct-command graph behavior remains unchanged.

### Phase 2 — Add Automation Component Segmentation Agent

Create:

```text
HomeAutomationAgents/Automation/ComponentSegmentation/
  AutomationComponentSegmentationAgent.swift
  AutomationComponentSegmentationWorkerSession.swift
  AutomationComponentSegmentationTypes.swift
  AutomationComponentSegmentationPromptBuilder.swift
  Tools/AutomationPatternParserHintTool.swift
```

Behavior:

- FoundationModel-backed.
- Uses current `AutomationPatternParser` only as a semantic hint/tool.
- Produces `AutomationComponentPlan`.
- Does not resolve device IDs, capabilities, attributes, commands, or SmartThings JSON.
- Extracts raw component spans and stable IDs.

For the example, output must be:

```text
trigger:
  t1 = "every day at 7 AM"

actions:
  a1 = "Turn on bedroom AC"
  a2 = "Turn off the bedroom lamp"

conditions:
  c1 = "living room ceiling light is off"
  c2 = "living room tv is off"

conditionTree:
  and([leaf("c1"), leaf("c2")])
```

Fallback:

- If FM is unavailable or fails, use current deterministic parser to produce the same component plan when possible.
- Deterministic output is fallback only, not primary when FM is available.

Acceptance:

- The segmentation agent replaces the structural duties of `AutomationTriggerExtractor` and `AutomationConditionParser` for active automation creation.
- Existing parser files remain as tools/fallback helpers during migration.

### Phase 3 — Convert Trigger Extraction Into A FoundationModel Agent

Create:

```text
HomeAutomationAgents/Automation/TriggerResolution/
  AutomationTriggerResolutionAgent.swift
  AutomationTriggerResolutionWorkerSession.swift
  AutomationTriggerResolutionTypes.swift
  AutomationTriggerResolutionPromptBuilder.swift
```

Input:

```swift
public struct AutomationTriggerResolutionInput: Sendable, Hashable {
    public let component: AutomationTriggerComponent
    public let fullUserText: String
    public let timezoneIdentifier: String?
}
```

Output:

```swift
public struct AutomationTriggerResolutionOutput: Sendable, Hashable {
    public let id: String
    public let trigger: HomeAutomationTrigger?
    public let confidence: Double
    public let unsupportedFragments: [String]
}
```

Behavior:

- FM decides schedule vs device trigger.
- For schedule trigger, FM extracts repeat rule, time, timezone if present.
- For device trigger, FM may reference a condition component ID if segmentation produced one.
- Current `AutomationTriggerExtractor` becomes hint/fallback logic.

For the example:

```text
t1 -> .schedule(repeatRule: .everyDay, timeOfDay: 07:00)
```

Acceptance:

- Schedule trigger resolution has its own event:
  `automationComponentFanOut/trigger:t1`.
- Trigger resolution can run concurrently with all action and condition branches.

### Phase 4 — Convert Condition Parsing And Operand Resolution Into Model-First Clause Agents

Create:

```text
HomeAutomationAgents/Automation/ConditionClauseResolution/
  AutomationConditionClauseResolutionAgent.swift
  AutomationConditionClauseResolutionWorkerSession.swift
  AutomationConditionClauseResolutionTypes.swift
  AutomationConditionClauseResolutionPromptBuilder.swift
  Tools/AvailableConditionDevicesTool.swift
  Tools/CapabilityAttributeCatalogTool.swift
```

Input:

```swift
public struct AutomationConditionClauseResolutionInput: Sendable, Hashable {
    public let component: AutomationConditionComponent
    public let fullUserText: String
    public let availableDevices: [HomeCandidateRecord]
}
```

Output:

```swift
public struct AutomationConditionClauseResolutionResult: Sendable, Hashable {
    public let id: String
    public let rawText: String
    public let condition: HomeAutomationCondition?
    public let records: [AutomationConditionOperandResolutionRecord]
    public let confidence: Double
}
```

Behavior:

- FM decides the condition operator and operands.
- FM chooses device ID, capability, and attribute using tools.
- Deterministic condition parser and deterministic operand scorer are hints/fallback only.
- The agent must be able to resolve a single leaf condition independently.

For the example, the two branches run independently:

```text
c1:
  "living room ceiling light is off"
  -> comparison(
       left: deviceAttribute(
         deviceID: "living_room_ceiling_light",
         capability: "switch",
         attribute: "switch"
       ),
       operator: equals,
       right: literalString("off"),
       triggerPolicy: never
     )

c2:
  "living room tv is off"
  -> comparison(
       left: deviceAttribute(
         deviceID: "living_room_tv",
         capability: "switch",
         attribute: "switch"
       ),
       operator: equals,
       right: literalString("off"),
       triggerPolicy: never
     )
```

Acceptance:

- `AutomationConditionOperandResolver` is removed from orchestrator or reduced to a compatibility wrapper.
- FM is primary when available.
- Deterministic matching never short-circuits FM availability.
- Each condition leaf gets its own scoped record: `condition("c1")`, `condition("c2")`.

### Phase 5 — Add Parallel Automation Component Fan-Out Runner

Create:

```text
HomeAutomationAgents/Automation/ComponentFanOut/
  AutomationComponentFanOutAgent.swift
  AutomationComponentFanOutRunner.swift
  AutomationComponentFanOutTypes.swift
```

`AutomationComponentFanOutRunner` owns a structured task-group tree:

```swift
await withTaskGroup(of: AutomationComponentOutcome.self) { group in
    if let trigger {
        group.addTask {
            await detachedExecutor.runDetached(triggerAgent, ...)
        }
    }

    for action in actions {
        group.addTask {
            await detachedExecutor.runDetached(actionSubgraphAgent, ...)
        }
    }

    for condition in conditions {
        group.addTask {
            await detachedExecutor.runDetached(conditionClauseAgent, ...)
        }
    }

    for await outcome in group {
        aggregate(outcome)
    }
}
```

Concurrency requirements:

- No hard-coded action limit.
- No hard-coded condition limit.
- Every trigger/action/condition component starts before waiting for any component result.
- Each component gets:
  - its own `Task.detached`
  - its own `AgentInvocationActor`
  - its own telemetry scope
  - its own namespaced pipeline events
- Results are aggregated by stable IDs, not completion order.

For the example, expected start events:

```text
automationComponentFanOut/trigger:t1 running
automationComponentFanOut/action:a1 running
automationComponentFanOut/action:a2 running
automationComponentFanOut/condition:c1 running
automationComponentFanOut/condition:c2 running
```

All five should appear before the first component completion, unless one completes too quickly to observe in logs.

Failure policy:

- One failed action does not cancel unrelated condition/trigger tasks immediately.
- Aggregate all component results first.
- Draft assembly or validation decides whether the overall automation is unsupported, needs clarification, or can proceed.
- Cancel remaining component tasks only if the graph receives external cancellation or a safety policy requires immediate stop.

Acceptance:

- Multi-action, multi-condition automations resolve components concurrently.
- Event logs prove all component branches are started.
- Output ordering remains stable: actions by `order`, conditions by `conditionTree`.

### Phase 6 — Add Automation Draft Assembly Agent

Create:

```text
HomeAutomationAgents/Automation/DraftAssembly/
  AutomationDraftAssemblyAgent.swift
  AutomationDraftAssemblyTypes.swift
```

Behavior:

- Deterministic assembly agent.
- Consumes `AutomationComponentPlan` and `AutomationResolvedComponentSet`.
- Produces final `HomeAutomationRuleDraft`.
- Reconstructs compound condition trees from `conditionTree`.
- Attaches resolved trigger and resolved condition.
- Keeps action descriptions in original order.

For the example, assembled draft:

```text
trigger:
  schedule everyDay 07:00

condition:
  and([c1.condition, c2.condition])

actionDescriptions:
  ["Turn on bedroom AC", "Turn off the bedroom lamp"]
```

Acceptance:

- Assembly does not call FoundationModels.
- Assembly fails clearly if `conditionTree` references a missing condition ID.
- Assembly keeps unresolved component diagnostics for validation.

### Phase 7 — Update Automation Graph

Replace active automation creation graph with:

```text
automationComponentSegmentation
  -> automationComponentFanOut
  -> automationDraftAssembly
  -> automationValidation
  -> smartThingsCompilation
  -> smartThingsRuleCreation
  -> automationResultAssembly
```

Graph notes:

- `automationComponentFanOut` internally runs trigger/action/condition branches in a task-group tree.
- `automationActionResolution` can remain as the action branch implementation, but it should be invoked per action component by the fan-out runner.
- `automationConditionOperandResolution` should be replaced by condition clause resolution in the active graph.
- Keep compatibility shims only if tests or external call sites still need the old IDs.

Acceptance:

- Active graph no longer depends on monolithic `automationDraft` to discover everything.
- Active graph no longer depends on orchestrator helper `AutomationConditionOperandResolver`.
- Pipeline remains graph-owned.

### Phase 8 — Telemetry And Logging

Add structured telemetry fields:

```text
componentID
componentKind
parentComponentPlanID
agentInvocationID
taskID
actorID
detachedTask: true
startedAt
completedAt
durationMs
waitBeforeStartMs
conditionTreePath
actionIndex
triggerIndex
```

Add aggregate telemetry:

```text
componentCount
triggerCount
actionCount
conditionCount
maxConcurrentComponentsStarted
componentStartSpreadMs
componentFanOutDurationMs
componentAggregationDurationMs
```

Acceptance:

- Logs can reconstruct the component task tree.
- Parallel starts are visible without reading thread dumps.
- JSONL output can group by `runID`, `componentID`, `agentID`, and `agentInvocationID`.

### Phase 9 — Safety, Cancellation, And Threading Rules

Threading rules:

- Agents receive immutable `ResolutionContext` or typed inputs only.
- Agents never mutate shared context directly.
- All context writes happen through patches committed by `ResolutionContextStore`.
- Detached tasks must not capture non-Sendable mutable state.
- Each detached task must create or receive a per-invocation actor.
- Task-local telemetry must be explicitly restored inside detached tasks.

Cancellation rules:

- Parent graph cancellation cancels all detached component tasks.
- Timeout cancels only the current agent invocation attempt.
- Retry creates a new detached task and a new actor.
- Component fan-out cancellation waits for child task cleanup before returning.

Safety rules:

- Safety gates are never bypassed by component parallelism.
- SmartThings rule creation still happens only after validation and compilation.
- Action resolution uses `executeLowRiskCommands: false` inside automation creation.
- Confirmation requirements from any action propagate to the final plan.

## Test Plan

### Unit Tests

- `AutomationComponentSegmentationAgent` extracts trigger, two actions, two condition components, and `and` condition tree from the example command.
- `AutomationTriggerResolutionAgent` resolves `every day at 7 AM` to `everyDay` and `07:00`.
- `AutomationConditionClauseResolutionAgent` resolves `living room ceiling light is off` using FM path when available.
- `AutomationConditionClauseResolutionAgent` resolves `living room tv is off` independently.
- Deterministic parser/scorer is used only when FM is unavailable or throws.
- `AutomationDraftAssemblyAgent` reconstructs `and([c1, c2])` in stable order.
- Missing condition ID in `conditionTree` fails assembly with a clear error.

### Concurrency Tests

- Component fan-out starts trigger, all actions, and all conditions before awaiting aggregate completion.
- No hard-coded action concurrency cap exists.
- No hard-coded condition concurrency cap exists.
- Ten actions and ten conditions produce twenty-one concurrent component starts including trigger.
- Each component branch has a unique `agentInvocationID`.
- Each component branch runs through `DetachedAgentExecutor`.
- Cancellation of parent fan-out cancels unfinished detached component tasks.
- Retry creates a new actor and new invocation ID.

### Integration Tests

Use these commands:

```text
Turn on bedroom AC everyday at 7 AM
Turn on bedroom AC everyday at 7 AM if the entry contact sensor is closed
Turn on bedroom AC and turn off the bedroom lamp every day at 7 AM if living room ceiling light is off and living room tv is off
Unlock the front door if bedroom ac is turned on
Today is quite hot... always turn on the Bedroom AC in similar situation
```

Expected for the main example:

- Segmentation finds one trigger, two actions, two condition leaves.
- Trigger, action `a1`, action `a2`, condition `c1`, and condition `c2` run concurrently.
- Final rule has schedule trigger, `and` condition, and two command actions.
- SmartThings JSON includes `every.specific`, nested `if`, and both command actions.

### Regression Tests

- `swift build`
- `swift test`
- Existing direct-command graph tests still pass.
- Existing safety gate tests still pass.
- Existing automation creation tests are updated to expect component-level telemetry.
- No source references to active helper-style `AutomationConditionOperandResolver` remain outside compatibility tests.

## Assumptions And Defaults

- “Unlimited concurrency” means no hard-coded action or condition cap in application logic.
- The Swift runtime may still schedule work according to system resources; the code must enqueue all component tasks immediately.
- `Task.detached` is required for agent execution, but cancellation and telemetry must be manually propagated.
- `ResolutionContextStore` remains the only shared mutable context actor.
- FoundationModel output is primary for trigger and condition resolution when available.
- Deterministic parsing remains only as hint/fallback for safety and model-unavailable cases.
- Existing public behavior should remain compatible at the `HomeCommandOrchestrator` API level.
