# Operation Routing and Automation Creation Requirements

## Purpose

This document describes the intended operation-routing and automation-creation architecture, reviewed against the current implementation.

The original system was built for immediate device-control commands such as:

```text
Turn on the TV
Set the bedroom lamp to 40 percent
Make the bedroom AC cooler by 2 degrees
```

The new capability is operation-level detection. Before running command-specific agents, the orchestrator must identify whether the user wants an immediate command or a persistent automation/rule.

Example user command:

```text
Turn on AC everyday at 7 AM
```

The target semantic interpretation is:

```json
{
  "domain": "homeAutomation",
  "operation": "automationCreation",
  "intent": ["createAutomation"],
  "actions": [
    {
      "intent": ["power"],
      "device": "AC",
      "deviceType": "airConditioner",
      "capability": "switch",
      "command": "on",
      "value": "on"
    }
  ],
  "trigger": {
    "type": "schedule",
    "time": "07:00",
    "displayTime": "7:00 AM",
    "repeat": "everyDay"
  },
  "condition": null
}
```

The public Swift result currently returns this information through `HomeAutomationResolverResult.resolution`, specifically `.automationDrafted(HomeAutomationCreationPlan)` or `.automationRequiresConfirmation(HomeAutomationCreationPlan)`. The requested JSON shape should be treated as a presentation/contract projection over `HomeAutomationCreationPlan`, not as the internal source of truth.

## Reference Material

SmartThings Rules are the primary backend model for the first automation compiler:

- SmartThings Rules documentation: <https://developer.smartthings.com/docs/automations/rules>
- SmartThings Rules API entry point: <https://developer.smartthings.com/docs/api/public#tag/Rules>
- SmartThings Automations overview: <https://developer.smartthings.com/docs/automations/getting-started-with-automations>

Important SmartThings concepts for this project:

- A Rule is a named JSON object with an `actions` tree.
- A Rule can contain multiple command actions.
- `if`, `every`, and `command` actions are enough for the first useful slice.
- Conditions can compose with `and`, `or`, and `not`.
- Comparison operators include `equals`, `greaterThan`, `lessThan`, `greaterThanOrEquals`, `lessThanOrEquals`, `between`, and `changes`.
- Device operands carry device IDs, component, capability, attribute, and trigger policy.
- Trigger policy matters because a device event can be a trigger, while another condition can be only a precondition.

These concepts mean the internal model should be a rule AST plus resolved action commands, not a flat single `action` and single `condition` object.

## Current Implementation Review

This review reflects the current code after the automation-creation graph, SmartThings rule-creation backend, and automation RAG optimization implementation.

### Package Structure

The package remains split into:

- `HomeAutomationCore`
- `HomeAutomationRAG`
- `HomeAutomationAgents`
- `HomeAutomationOrchestrator`

The app target depends on the core and orchestrator modules.

### Direct Command Baseline

Immediate device commands still use the existing direct-command agent family:

1. NLU agents detect language, domain, intent family, device type, slots, and risk.
2. Knowledge and candidate agents retrieve and rank relevant devices and command examples.
3. Draft generation creates a single `HomeCommandDraft`.
4. Safety, parameter, and confirmation agents validate the draft.
5. Execution planning produces a `HomeAutomationExecutionPlan`.
6. Low-risk execution can be mocked locally when requested.

Phase 11 changed the default direct-command runtime to the graph scheduler. The legacy phase scheduler is still available through `OrchestratorRuntimeMode.legacy` and the environment variable `HOME_AUTOMATION_ORCHESTRATOR_RUNTIME=legacy`.

### Operation Routing Baseline

The project now has a top-level operation model:

```swift
public enum HomeAutomationOperationKind: String, Sendable, Hashable, Codable {
    case executeDeviceCommand
    case automationCreation
    case automationUpdate
    case automationDeletion
    case automationQuery
    case sceneCreation
    case routineExecution
    case unsupported
}

public struct HomeOperationDetectionResult: Sendable, Hashable, Codable {
    public let domain: HomeAutomationCommandDomain
    public let operation: HomeAutomationOperationKind
    public let confidence: Double
    public let reason: String
}
```

`HomeCommandOrchestrator.resolveStream` runs `HomeOperationDetectionService` before selecting the rest of the flow. `OperationDetectionAgent` also exists as a graph node and is registered in the default registry; the automation creation graph uses it as its entry node so operation detection appears in automation graph traces and metrics.

Current routing behavior:

- `.executeDeviceCommand` runs the direct-command pipeline.
- `.automationCreation` runs `GraphPlanner.automationCreationGraph()` through `GraphScheduler` when the runtime mode is `.graph`.
- `.automationCreation` runs `AutomationCreationResolver` only in legacy runtime mode or as a defensive fallback when graph execution fails to produce a final result.
- `.automationUpdate`, `.automationDeletion`, `.automationQuery`, `.sceneCreation`, and `.routineExecution` are reserved enum cases only. They are out of scope for this plan and must return unsupported results.
- `.unsupported` returns unsupported.

Important review note: graph selection is still operation-first and deterministic at the orchestrator boundary. The graph-executed operation node records context inside the selected automation graph; it does not replace the top-level router yet.

### Automation Creation Baseline

Automation creation is functional as a graph-native path in graph runtime mode, with the legacy service path retained for rollback and parity checks.

Current flow:

```text
User command
  -> HomeOperationDetectionService
  -> GraphScheduler automationCreationGraph
     -> OperationDetectionAgent
     -> AutomationDraftExtractionAgent / AutomationPatternParser
     -> AutomationConditionOperandResolutionAgent
     -> AutomationActionResolutionAgent
     -> AutomationValidationAgent
     -> SmartThingsCompilationAgent
     -> SmartThingsRuleCreationAgent
     -> AutomationResultAssemblyAgent
```

Current models include:

- `HomeAutomationRuleDraft`
- `HomeAutomationTrigger`
- `HomeAutomationScheduleTrigger`
- `HomeAutomationDeviceTrigger`
- `HomeAutomationCondition`
- `HomeAutomationComparisonCondition`
- `HomeAutomationConditionOperand`
- `HomeAutomationResolvedAction`
- `HomeAutomationCreationPlan`
- `SmartThingsRuleDocument`

Current supported examples include:

- `Turn on bedroom AC everyday at 7 AM`
- `Turn on bedroom AC everyday at 7 AM if the entry contact sensor is closed`
- `Unlock front door every day at 7 AM` with confirmation required
- `When the front door opens, turn on hallway light`
- Multiple action descriptions split with `and`

Current parser/compiler limitations:

- Daily schedules compile to SmartThings `every.specific`.
- Interval schedules compile to SmartThings `every.interval`.
- Weekday/weekend/day-of-week schedules can be parsed, but SmartThings compilation is marked unsupported.
- `between` and `changes` are represented in the AST and compiled for supported device operands.
- `tomorrow`, absolute dates, sunrise/sunset, location mode, presence, and duration windows are not fully implemented.
- Ambiguous logical grouping is not yet clarified robustly.

### Action Reuse Baseline

`AutomationActionResolver` reuses the old direct-command pipeline for each action description, for example `Turn on AC`.

This is the correct architectural direction because automation actions must still use the same device resolution, command draft, parameter validation, and confirmation policy used by immediate commands.

Current implementation resolves action descriptions concurrently inside `AutomationActionResolver`, returns results in stable input order, and writes action-scoped outputs. Full dynamic graph expansion into one graph node per action remains a future hardening step.

### Condition Operand Baseline

`AutomationConditionOperandResolver` resolves simple condition operands by scoring known devices and selecting readable capabilities and attributes.

Current strengths:

- Handles nested `and`, `or`, and `not` trees.
- Resolves common conditions such as contact sensor open/closed, switch on/off, motion active/inactive, and temperature threshold.

Current limitations:

- It uses deterministic matching only.
- It does not yet run candidate retrieval/ranking agents for condition operands.
- Ambiguous condition-device matches return unresolved operands and become clarification or unsupported outcomes later.

### RAG Baseline

The RAG layer has been expanded for automation creation.

Current automation knowledge sources:

- `automationPattern`
- `automationRuleExample`
- `automationConditionOperator`
- `smartThingsRuleSchema`

Current structured retrieval fields:

- `operation`
- `automationConcepts`
- `conditionOperators`
- `repeatHints`

`AutomationRAGPolicy` gates retrieval so high-confidence deterministic daily schedules avoid unnecessary RAG, while complex device triggers, compound conditions, unsupported fragments, and schema-sensitive operators retrieve focused automation knowledge.

Current RAG gap: an automation RAG evaluation corpus exists for policy/source/subproblem coverage, but broader precision/recall benchmarking against a larger command set is still future work.

### Metrics Baseline

The orchestrator now records automation metrics including operation, runtime mode, graph ID, action count, condition count, validation issue count, SmartThings compilation support, SmartThings backend status, and graph node statuses.

Important review note: graph runtime metrics are actual `GraphScheduler` metrics for automation creation in graph mode. Per-action and per-condition node statuses are currently enriched from scoped subflow outputs rather than created by dynamic graph expansion.

## Capability Status Matrix

| Area | Current status | Review |
| --- | --- | --- |
| Operation enum/result | Implemented | Uses `HomeAutomationOperationKind`, not the older planned `HomeAutomationOperationType` name. |
| Deterministic operation detection | Implemented | Recognizes schedules, trigger words, automation keywords, and immediate command verbs. Non-creation automation operations are out of scope. |
| Operation-detection agent | Implemented | Registered in the default registry and executed by the automation creation graph; top-level deterministic routing still selects the graph. |
| Operation-based routing | Implemented | Orchestrator routes direct commands vs automation creation. Non-creation automation operations return unsupported. |
| Graph runtime default | Implemented | Direct command graph is default; legacy rollback remains available. |
| Automation creation flow | Implemented graph path | Graph runtime executes automation creation; legacy service resolver remains as rollback/parity baseline. |
| Multiple actions | Implemented baseline | Concurrent action resolution and scoped outputs exist; full dynamic graph expansion remains future hardening. |
| Composite conditions | Partial | AST and basic parsing exist; ambiguous grouping and broader grammar are pending. |
| Trigger vs precondition | Partial | Trigger policy exists and compiles to SmartThings `Always`/`Never` for supported operands. More trigger types are pending. |
| Schedule parsing | Partial | Daily, interval, and days-of-week parse. SmartThings compilation supports daily and interval only. |
| Condition operand resolution | Partial | Deterministic resolver exists; agent/RAG-backed candidate resolution is pending. |
| Action command reuse | Implemented | Embedded actions reuse the direct-command pipeline and do not execute device state changes. |
| SmartThings compiler/backend | Implemented baseline | Supports useful `every`, `if`, comparison, and command JSON. Create-only SmartThings Rule persistence is available behind dry-run, validation, location, and confirmation gates. |
| Automation safety | Partial | High-risk commands require confirmation and too-frequent intervals can be blocked. Broader unattended risk policy is pending. |
| Clarification | Partial | Unresolved actions/operands can ask questions. Ambiguous logical grouping needs explicit clarification support. |
| Automation RAG | Implemented baseline | Curated chunks, source/subproblem routing, gated retrieval, and policy corpus exist; larger benchmark evaluation remains pending. |
| Direct command regression | Implemented | Tests compare graph and legacy fallback behavior and preserve direct command results. |

## Requirements

### FR-001: Operation Detection

The system must detect the operation requested by the user before choosing the rest of the pipeline.

Required operations for this plan:

- `executeDeviceCommand`
- `automationCreation`
- `unsupported`

`automationUpdate`, `automationDeletion`, `automationQuery`, `sceneCreation`, and `routineExecution` may remain as reserved enum cases in code, but they are not implementation targets. If a user asks for them, the system should return an explicit unsupported result.

Current implementation uses `HomeOperationDetectionService`. The intended architecture should promote this into a graph-capable operation detection agent or a router node that can combine deterministic rules with model/RAG support for ambiguous automation-creation commands.

Examples:

| User command | Expected operation |
| --- | --- |
| `Turn on the TV` | `executeDeviceCommand` |
| `Turn on AC everyday at 7 AM` | `automationCreation` |
| `When the door opens, turn on the hallway light` | `automationCreation` |
| `Delete my morning AC automation` | `unsupported` |
| `Disable the night light rule` | `unsupported` |
| `What automations run at 7 AM?` | `unsupported` |

### FR-002: Operation-Based Agent Routing

The orchestrator must select operation-specific plans from `HomeOperationDetectionResult.operation`.

Required behavior:

- `executeDeviceCommand` uses the direct-command graph.
- `automationCreation` uses the automation creation graph.
- Every other operation returns an explicit unsupported result.

Current implementation routes correctly but automation creation is not graph-executed yet.

### FR-003: Multiple Actions

Automation creation must support more than one action.

Example:

```text
Everyday at 7 AM turn on the AC and turn off the bedroom lamp
```

Internal representation should keep action text as independently resolvable commands:

```swift
public let actionDescriptions: [String]
public let resolvedActions: [HomeAutomationResolvedAction]
```

The next architecture step should run these action descriptions as scoped subgraphs so each action can resolve independently without overwriting root direct-command context.

### FR-004: Composite Conditions

Automation creation must preserve logical condition trees.

Required operators:

- `and`
- `or`
- `not`
- `equals`
- `greaterThan`
- `lessThan`
- `greaterThanOrEquals`
- `lessThanOrEquals`
- `between`
- `changes`

Current implementation has an AST for all of these, but deterministic parsing and compilation do not yet support the full grammar.

### FR-005: Triggers vs Preconditions

The system must distinguish:

- Triggers: schedules or device events that start rule evaluation.
- Preconditions: conditions that must be true but should not independently trigger the rule.

Current implementation has `HomeAutomationConditionTriggerPolicy.always` and `.never`, and SmartThings compilation maps those to device operand trigger policy. This should remain core architecture.

### FR-006: Time and Schedule Triggers

Required schedule support:

- `everyday at 7 AM`
- `at 7 AM every day`
- `weekdays at 6:30 PM`
- `every Monday at 8 PM`
- `tomorrow at 9`
- `after 10 minutes`
- `every 30 minutes`

Current implementation supports daily, interval, weekdays/weekends/day names as parsed repeat rules. Compilation supports daily and interval. Absolute one-time date/time and relative delay expressions remain future work.

### FR-007: Device Condition Operands

Condition operands must resolve to backend-usable device attributes.

Example:

```text
If bedroom temperature is above 26, turn on the AC
```

Target operand:

```json
{
  "deviceId": "bedroom_temperature_sensor",
  "component": "main",
  "capability": "temperatureMeasurement",
  "attribute": "temperature"
}
```

Current deterministic operand resolution is useful but should be replaced or supplemented with candidate retrieval, ranking, and clarification for ambiguous condition devices.

### FR-008: Action Command Reuse

Each automation action must reuse the direct-command machinery:

- device type inference
- candidate retrieval
- candidate ranking
- hydration
- command draft generation or deterministic fallback
- capability validation
- parameter validation
- confirmation policy

Current implementation satisfies this with `AutomationActionResolver`.

### FR-009: SmartThings Rule Translation

The system should compile internal automation plans into SmartThings Rules JSON through a backend compiler.

Required design rule: SmartThings JSON must remain a target output, not the internal automation model.

Current implementation has `SmartThingsRuleCompiler` and `SmartThingsRuleDocument`. It compiles supported schedules, device triggers, conditions, and command actions into typed payloads and JSON strings. Create-only SmartThings API persistence is implemented separately through `SmartThingsRuleCreating` and remains behind dry-run, validation, location, and confirmation gates.

### FR-010: Persistent Automation Safety

Automations are higher risk than immediate commands because they execute later and may repeat.

Required policy:

- Require confirmation for unattended high-risk devices.
- Block or clarify too-frequent recurring automations.
- Require confirmation for unlock/open/security-sensitive commands.
- Validate both action devices and condition devices.
- Never let RAG or model output bypass deterministic validation.

Current implementation has a strong baseline through `AutomationValidationPolicy`, but should add richer policy for location/presence, critical devices, repeated state changes, and circular automation patterns.

### FR-011: Clarification

Automation creation must ask clarification questions when:

- action text is ambiguous
- target devices are ambiguous
- condition operands are unresolved
- trigger text is unsupported
- condition grouping is ambiguous
- unsupported schedule fragments are present and cannot be compiled

Current implementation asks clarification for unresolved actions and operands. Ambiguous logic grouping remains a key gap.

### FR-012: Preserve Direct Command Behavior

Existing direct commands must not regress.

Required guarantees:

- Direct commands should not run automation agents.
- Foundation-model-unavailable fallback must remain deterministic.
- Legacy rollback must keep direct commands working during graph migration.
- Existing safety confirmation behavior must remain stable.

Current implementation has regression tests for direct command graph/legacy parity.

## Architectural Gap Review

### Gap 1: Automation Graph Runtime Still Uses a Coarse Top-Level Router

`GraphPlanner.automationCreationGraph()` defines a graph:

```text
operationDetection
  -> automationDraft
  -> automationConditionOperandResolution
  -> automationActionResolution
  -> automationValidation
  -> smartThingsCompilation
  -> automationResultAssembly
```

`HomeCommandOrchestrator` now executes this graph for automation creation in graph runtime mode. The remaining gap is that graph selection still happens through a deterministic top-level router before scheduling starts. The graph entry `OperationDetectionAgent` records operation context inside the selected graph, but it does not yet choose between direct, automation, and unsupported graphs by itself.

Intended update: keep the current deterministic router, but eventually make operation routing a first-class runtime contract that can share trace, policy, and ambiguity handling across all supported graph paths.

### Gap 2: Dynamic Fan-Out Is Scoped, Not Fully Graph-Expanded

Automation service components have contextual agent wrappers and are registered. Multiple actions resolve concurrently and write action-scoped outputs, and condition operand records are scoped. The remaining gap is graph shape: action and condition work is not expanded into concrete per-action/per-condition graph nodes before scheduling.

Intended update: preserve the current scoped subflow implementation, then add dynamic graph expansion if the scheduler needs per-child retry/cancellation/policy at graph-node granularity.

### Gap 3: Condition Operand Resolution Is Still Deterministic

Scoped context exists and is used for automation outputs. Condition operand resolution, however, still relies on deterministic matching against known device/capability metadata.

Intended update: supplement deterministic matching with candidate retrieval/ranking and ambiguity-safe clarification for condition devices, while keeping the final selected device/capability/attribute deterministic.

### Gap 4: Operation-Neutral Outcomes Are Missing

The public result is still `HomeAutomationResolverResult`, and scheduler stop conditions inspect `HomeCommandResolution`.

Intended update: add internal operation-neutral outcomes while keeping the public API stable:

```swift
public enum OrchestrationOutcome: Sendable, Hashable {
    case command(HomeCommandResolution)
    case automation(HomeAutomationCreationPlan)
    case clarification(String)
    case unsupported(String)
}
```

### Gap 5: RAG Needs Larger Benchmark Evaluation

Automation RAG now has source-specific chunks, subproblem routing, per-source retrieval metrics, and a small evaluation corpus. The remaining gap is benchmark depth rather than architecture.

Intended update:

- Expand the automation command evaluation set.
- Track precision and recall for schedule, trigger, condition, SmartThings schema, and unsupported-fragment cases.
- Add benchmark fixtures for ambiguous and adversarial commands.
- Keep deterministic parsing for simple daily schedules to preserve latency.

## Proposed Updated Implementation Plan

### Phase A: Finalize Operation Contract

1. Treat `HomeAutomationOperationKind` as the canonical enum name.
2. Add operation context storage to `ResolutionContext` or typed scoped context.
3. Add an operation detection contextual agent that wraps `HomeOperationDetectionService`.
4. Register the operation detector in `DefaultAgentRegistryFactory`.
5. Add tests proving operation detection can run as a graph node.

### Phase B: Make Automation Creation Graph-Native

1. Add contextual adapters for automation draft, condition operand resolution, action resolution, validation, SmartThings compilation, and result assembly.
2. Make `GraphScheduler` execute `GraphPlanner.automationCreationGraph()` for `.automationCreation`.
3. Keep `AutomationCreationResolver` as a compatibility service during migration.
4. Compare service-path and graph-path outputs in tests.
5. Switch automation creation to graph runtime when parity is proven.

### Phase C: Add Scoped Context for Multi-Action Automations

1. Add `ContextKey<Value>`, `ContextScope`, and `ContextKeyDescriptor`.
2. Store scoped values inside `ResolutionContextStore`.
3. Add scoped reads/writes for action and condition subflows.
4. Update graph nodes so action subgraphs write to action-specific scopes.
5. Join scoped action outputs into `HomeAutomationResolvedAction` values.

### Phase D: Parallelize Action and Condition Subflows

1. Add support for dynamic graph fan-out based on `actionDescriptions`.
2. Resolve independent actions concurrently.
3. Resolve independent condition operands concurrently.
4. Add deterministic ordering when joining results.
5. Stop or clarify early only when a required child subflow fails.

### Phase E: Expand Automation Grammar and Compiler

1. Add parsing and compilation support for day-of-week schedules.
2. Add support for one-time absolute date/time where SmartThings can represent it.
3. Add support for relative delay expressions if backend-compatible.
4. Implement compiler support for `between` and `changes`.
5. Add location mode and presence operands only when validation can keep them safe.

### Phase F: SmartThings Rule Creation Backend

1. Keep `SmartThingsRuleCompiler` isolated behind `HomeAutomationRuleCompiling`.
2. Add a separate SmartThings Rules client protocol for creating a rule only.
3. Do not call the API from the parser or validation layers.
4. Add dry-run mode that returns JSON only.
5. Require explicit confirmation before creating high-risk persistent automations.

### Phase G: Explicitly De-Scope Other Automation Operations

Do not implement graph plans for:

- `automationUpdate`
- `automationDeletion`
- `automationQuery`
- `sceneCreation`
- `routineExecution`

The implementation should return clear unsupported results for these requests. This keeps the architecture focused on making automation creation correct, graph-native, and safe before expanding scope.

### Phase H: RAG Optimization

1. Build a curated automation evaluation corpus.
2. Add source-level retrieval metrics for automation RAG.
3. Split retrieval by subproblem.
4. Add hybrid retrieval weights per subproblem.
5. Add metadata filters for operation, pattern kind, condition operator, repeat hint, and schema key.
6. Keep final device IDs, capabilities, commands, and risk policy hydrated from core deterministic sources.

### Phase I: Metrics, UI, and Developer Review

1. Show operation, runtime, graph ID, action count, condition count, and compilation status in app diagnostics.
2. Show unsupported compilation reason for parsed-but-not-compiled rules.
3. Emit graph node statuses for automation creation after graph migration.
4. Add tests for direct command regression, automation creation, unsupported non-creation operations, and graph migration parity.

## Test Matrix

### Operation Detection

- `Turn on the TV` -> `executeDeviceCommand`
- `Turn on AC everyday at 7 AM` -> `automationCreation`
- `When the front door opens, turn on hallway light` -> `automationCreation`
- `Delete morning AC automation` -> `unsupported`
- `List automations` -> `unsupported`
- empty command -> `unsupported`

### Automation Drafting

- daily schedule with one action
- interval schedule with one action
- weekday schedule parsed but compilation unsupported until compiler expands
- device trigger with one action
- schedule with `and` conditions
- schedule with `or` conditions
- multiple actions

### Action Reuse

- action resolves same draft as direct command
- action does not execute immediately
- ambiguous action asks clarification
- high-risk action requires automation confirmation

### Condition Resolution

- contact sensor open/closed
- switch on/off
- motion active/inactive
- temperature greater/less than
- unresolved condition operand asks clarification
- ambiguous condition operand does not silently choose a device

### SmartThings Compilation

- daily schedule to `every.specific`
- interval schedule to `every.interval`
- device trigger to `if` with trigger policy `Always`
- precondition to trigger policy `Never`
- command action includes devices, capability, command, and arguments
- unsupported operator/schedule preserves `unsupportedCompilationReason`

### Regression

- graph runtime matches legacy fallback for direct commands
- high-risk direct command confirmation still works
- conversation memory still works
- model-unavailable fallback still resolves supported direct commands

## Acceptance Criteria

The automation routing architecture is complete when:

1. Operation detection is represented as a graph-capable agent or router node.
2. Direct commands remain graph-default and regression-safe.
3. Automation creation runs through the graph scheduler, not only through a side service.
4. Multiple action descriptions resolve through scoped subgraphs.
5. Conditions support nested `and`, `or`, and `not` without flattening.
6. Condition operands resolve through deterministic and candidate-based paths with clarification on ambiguity.
7. SmartThings JSON compilation is isolated behind a compiler protocol.
8. SmartThings API persistence is isolated behind a client protocol.
9. RAG is used only for the subproblems where it improves extraction or schema grounding.
10. Safety validation remains deterministic and cannot be bypassed by model or RAG output.
