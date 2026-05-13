# Orchestrator Extensibility Architecture Plan

## Summary

The current orchestrator is effective for one primary workflow: resolving a single immediate smart-home command into one validated command draft and execution plan. It is less ready for future workflows such as automation creation, automation update, multi-action rules, condition parsing, scenes, or operation-specific pipelines.

This plan proposes evolving the orchestrator into a capability-driven DAG runtime. The key change is to stop treating the pipeline as one fixed list of phases and instead let the orchestrator build an execution graph from the requested operation and the capabilities provided by registered agents.

Chosen direction:

- Introduce a new DAG runtime beside the current scheduler.
- Use agent capabilities as the main extension unit.
- Keep current direct command behavior stable while the DAG path reaches parity.
- Add operation routing as the first future-compatible capability.

## Current Architecture Findings

### What Works Well

- `HomeCommandOrchestrator` owns the high-level lifecycle: request creation, context store, memory injection, planning, scheduling, result assembly, metrics, and streamed events.
- `AgentRegistry` already supports lookup by `AgentCapability`, which is a useful extension point.
- `ContextualHomeAgent` adapts strongly typed agents into a common `AnyHomeAgent` runtime interface.
- `ResolutionContextStore` centralizes context mutation and keeps agents patch-based rather than directly mutating shared state.
- `AgentScheduler` supports sequential and parallel execution phases.
- Mandatory safety gates fail closed through `OrchestratorPolicyEngine`.
- Metrics and circuit breakers already give useful runtime visibility.

### Main Limitations

- `AgentPlanner` is static. It chooses either fallback-only or one hardcoded full command pipeline.
- `AgentScheduler` can only execute ordered phases. It cannot express arbitrary dependencies, conditional routing, operation-specific subgraphs, or repeated subflows.
- `AgentRegistry` indexes by capability, but the planner still uses concrete `AgentID`s.
- `ResolutionContextStore.apply` is hardcoded around known patch keys. Every future operation will require more store changes unless context writes become more typed and namespaced.
- `OrchestratorPolicyEngine` is ID-centric. Retry limits, mandatory gate detection, fail-closed handling, and terminal behavior are tied to current agent IDs.
- Scheduler stop conditions are coupled to current `HomeCommandResolution` cases.
- Metrics assume one command draft, one candidate set, and one execution plan.
- `DefaultAgentRegistryFactory` is a long monolithic registration block, making new operation-specific agent families harder to add cleanly.

## Target Architecture

### Operation-First Orchestration

The orchestrator should first determine what kind of operation the user requested.

Initial operation types:

```swift
public enum HomeAutomationOperationType: Sendable, Hashable, Codable {
    case executeDeviceCommand
    case automationCreation
    case automationUpdate
    case automationDeletion
    case automationQuery
    case unsupported
}
```

The operation result should be stored in context and used by the planner:

```swift
public struct HomeOperationDetectionResult: Sendable, Hashable, Codable {
    public let operation: HomeAutomationOperationType
    public let confidence: Double
    public let reason: String
}
```

Examples:

- `Turn on the TV` -> `executeDeviceCommand`
- `Turn on AC everyday at 7 AM` -> `automationCreation`
- `Delete my morning AC automation` -> `automationDeletion`
- `What rules run at 7 AM?` -> `automationQuery`

### Capability-Driven Agent Registration

Each agent should publish a manifest.

```swift
public struct AgentManifest: Sendable, Hashable {
    public let id: AgentID
    public let capabilities: Set<AgentCapability>
    public let consumes: Set<ContextKeyDescriptor>
    public let produces: Set<ContextKeyDescriptor>
    public let safetyRole: AgentSafetyRole
    public let retryPolicy: AgentRetryPolicy
    public let priority: Int
}

public enum AgentSafetyRole: Sendable, Hashable {
    case none
    case requiredGate
    case executionGate
}

public struct AgentRetryPolicy: Sendable, Hashable {
    public let maxAttempts: Int
    public let retryFailureKinds: Set<String>
}
```

The registry should support:

- lookup by concrete `AgentID`
- lookup by `AgentCapability`
- deterministic preferred-agent selection for a capability
- manifest lookup for policy and graph planning

This allows future operations to ask for "an agent that can extract automation conditions" without hardcoding a single agent ID in the planner.

### DAG Runtime

Introduce a new graph model beside `AgentExecutionPlan`.

```swift
public struct OrchestrationGraph: Sendable {
    public let id: String
    public let version: String
    public let goal: OrchestrationGoal
    public let nodes: [GraphNode]
    public let edges: [GraphEdge]
}

public enum OrchestrationGoal: Sendable, Hashable {
    case executeDeviceCommand
    case automationCreation
    case unsupported
}

public struct GraphNode: Sendable, Hashable {
    public let id: String
    public let requirement: AgentRequirement
    public let consumes: [ContextKeyDescriptor]
    public let produces: [ContextKeyDescriptor]
    public let guardCondition: GraphGuard?
    public let executionPolicy: NodeExecutionPolicy
}

public enum AgentRequirement: Sendable, Hashable {
    case agentID(AgentID)
    case capability(AgentCapability)
}

public struct GraphEdge: Sendable, Hashable {
    public let from: String
    public let to: String
}
```

The `GraphScheduler` should:

- run nodes when dependencies are satisfied
- execute independent ready nodes concurrently
- resolve capability requirements through `AgentRegistry`
- check circuit breakers before running selected agents
- apply patches after each node completes
- trace selected agents, skipped nodes, guard failures, and critical failures
- fail closed for required safety gates
- return an operation-neutral outcome

### Typed and Scoped Context

The current `ResolutionContext` is root-level and direct-command oriented. Future operation support needs scoped context so multiple actions and conditions do not overwrite each other.

Add typed context keys:

```swift
public struct ContextKey<Value: Sendable>: Sendable, Hashable {
    public let rawValue: String
    public let scope: ContextScope
}

public enum ContextScope: Sendable, Hashable {
    case root
    case operation(String)
    case action(String)
    case condition(String)
}

public struct ContextKeyDescriptor: Sendable, Hashable {
    public let rawValue: String
    public let scope: ContextScope
}
```

Use root scope for the existing direct command fields:

- language
- domain
- intent
- device type
- slots
- risk
- candidates
- draft
- execution plan
- resolution

Use action and condition scopes later for automation creation:

- action `a1` draft
- action `a2` draft
- condition `c1` operand
- condition `c2` operand

### Operation-Neutral Outcomes

The scheduler should not know only about `HomeCommandResolution`.

Add an internal outcome wrapper:

```swift
public enum OrchestrationOutcome: Sendable, Hashable {
    case command(HomeCommandResolution)
    case automation(HomeAutomationResolution)
    case clarification(String)
    case unsupported(String)
}
```

Direct command APIs can still return `HomeAutomationResolverResult`. The outcome wrapper exists so the runtime can support future result types without hardcoding stop behavior around command-only cases.

### Graph-Aware Policy

Move policy away from agent-ID switches and toward manifests and graph node metadata.

```swift
public struct OrchestrationPolicy: Sendable {
    public func shouldUseModels(for goal: OrchestrationGoal) -> Bool
    public func retryPolicy(for manifest: AgentManifest) -> AgentRetryPolicy
    public func isMandatory(_ manifest: AgentManifest) -> Bool
    public func failClosedOutcome(
        for node: GraphNode,
        manifest: AgentManifest?,
        context: ResolutionContext
    ) -> OrchestrationOutcome
}
```

The old `OrchestratorPolicyEngine` can remain as a compatibility wrapper during migration.

### Graph-Aware Metrics

Add graph runtime metrics without removing current fields.

```swift
public struct GraphRunMetrics: Sendable, Codable, Hashable {
    public let graphID: String
    public let graphVersion: String
    public let goal: String
    public let selectedAgents: [String: String]
    public let nodeStatuses: [String: String]
    public let skippedNodes: [String]
    public let criticalFailures: [String]
}
```

Current metrics should still populate for direct command runs. When using the DAG runtime, direct command metrics should be derived from graph traces.

## Proposed Implementation Plan

### Phase 1: Add Agent Manifests

Add `AgentManifest`, `AgentSafetyRole`, and `AgentRetryPolicy`.

Update `AgentRegistry` so it stores:

- agent instances by ID
- capability index
- manifests by ID
- priority ordering for capability providers

Keep existing `agent(for:)` and `agents(for:)` APIs.

Add tests for:

- manifest lookup
- deterministic preferred agent selection
- duplicate capability providers

### Phase 2: Split Registry Construction

Refactor `DefaultAgentRegistryFactory` into grouped registration helpers:

- NLU registrations
- knowledge registrations
- candidate registrations
- draft registrations
- safety registrations
- execution registrations
- fallback registrations
- response registrations

Do not change behavior. This phase should only make registration easier to extend.

### Phase 3: Add Typed Context Compatibility Layer

Add `ContextKey`, `ContextScope`, and `ContextKeyDescriptor`.

Add generic read/write helpers to `ResolutionContextStore` while preserving existing typed fields and patch keys.

Initial implementation can map typed root keys to existing fields. Scoped keys can be stored in a new dictionary:

```swift
private var scopedValues: [ContextKeyDescriptor: AnySendableValue]
```

Add tests for:

- root key read/write compatibility
- action-scoped values not overwriting root values
- condition-scoped values not overwriting action values

### Phase 4: Introduce DAG Graph Types

Add:

- `OrchestrationGraph`
- `GraphNode`
- `GraphEdge`
- `AgentRequirement`
- `GraphGuard`
- `NodeExecutionPolicy`
- `OrchestrationGoal`
- `OrchestrationOutcome`

Do not connect them to production command resolution yet.

Add unit tests for graph validation:

- missing dependency detection
- cycle detection
- unknown node references
- duplicate node IDs

### Phase 5: Build GraphScheduler

Implement `GraphScheduler` beside the existing `AgentScheduler`.

Required behavior:

- find ready nodes by dependency completion
- run ready nodes concurrently
- resolve capability requirements to concrete agents
- respect circuit breakers
- apply success patches
- append errors on failures
- fail closed for required gates
- trace node and selected agent
- support skipped nodes through guards

Add tests for:

- simple linear graph
- parallel independent nodes
- dependency-gated node execution
- guard skipped node
- missing optional agent
- missing required gate
- circuit breaker skip
- fail-closed required gate

### Phase 6: Add CapabilityGraphPlanner

Create `CapabilityGraphPlanner` beside the current `AgentPlanner`.

It should produce:

- direct command graph matching the current model-available pipeline
- fallback graph matching the current model-unavailable pipeline
- unsupported graph

The first direct command graph should preserve current logical ordering:

1. NLU agents in parallel
2. knowledge agents and candidate retrieval
3. retrieval judge
4. candidate ranking
5. candidate hydration
6. instruction composition
7. draft generation
8. safety validation
9. parameter validation
10. confirmation policy
11. execution planning
12. optional mock execution when policy allows

Add tests comparing current `AgentPlanner` intent with graph planner output.

### Phase 7: Add Runtime Selection

Add an orchestrator configuration:

```swift
public enum OrchestratorRuntimeMode: Sendable, Hashable {
    case legacyPhaseScheduler
    case graphScheduler
}
```

Default to `legacyPhaseScheduler` at first.

Allow tests and internal callers to opt into `graphScheduler`.

Add direct command parity tests:

- fallback command resolves the same selected device
- model-unavailable metrics remain populated
- safety confirmation still works
- memory hint pronoun resolution still works

### Phase 8: Switch Direct Command Default

After parity tests pass, change the default runtime to `graphScheduler`.

Keep the legacy scheduler available for a short compatibility period.

### Phase 9: Add Operation Detection

Add:

- `HomeAutomationOperationType`
- `HomeOperationDetectionResult`
- `AgentID.operationDetection`
- `AgentCapability.operationDetection`
- `OperationDetectionAgent`

Update graph planning so the first graph can route by operation:

- execute device command -> direct command graph
- automation creation -> future automation graph
- unsupported -> unsupported graph

Initially, automation creation can route to a placeholder unsupported/clarification graph until automation agents exist.

### Phase 10: Add Automation Graph Later

Once the orchestrator runtime is graph-based, add automation creation as a new graph goal rather than modifying the direct command graph.

Future automation graph should include:

- operation detection
- automation decomposition
- trigger extraction
- condition graph extraction
- action resolution subgraphs
- condition operand resolution subgraphs
- automation assembly
- automation validation
- backend translation

## Testing Requirements

### Existing Behavior Regression

Current direct command tests must continue to pass:

- `Turn on the bedroom lamp`
- `Set bedroom lamp to 40 percent`
- `Make bedroom AC cooler by 2 degrees`
- high-risk lock confirmation
- memory-based pronoun resolution
- fallback-only resolution

### New Architecture Tests

Add tests for:

- agent manifest registration
- capability-based agent selection
- graph validation
- graph dependency execution
- graph parallel execution
- graph guard skip
- fail-closed mandatory gate
- typed context root compatibility
- typed context action and condition scoping
- graph metrics capture
- direct command parity between legacy and graph runtime

### Future Compatibility Proof

Add a test-only stub graph:

```text
operationDetection -> fakeAutomationPlanner -> fakeAutomationResult
```

The test should prove that adding a new operation graph does not require modifying `GraphScheduler`.

## Acceptance Criteria

The orchestrator refactor is successful when:

1. Existing direct command behavior remains unchanged.
2. Agents can be selected by capability, not only by hardcoded ID.
3. A graph planner can express the current command pipeline.
4. The graph scheduler can run sequential and parallel dependencies.
5. Mandatory safety gates fail closed through manifest policy.
6. Context supports scoped values for future multi-action operations.
7. Metrics identify graph ID, graph version, node statuses, selected agents, skipped nodes, and failures.
8. Operation detection can be added as a graph node without changing scheduler internals.
9. A stub future operation graph can run in tests without modifying the direct command graph.
10. The architecture is ready for automation creation as a separate operation graph.

## Explicit Non-Goals

- Do not implement automation creation in this refactor.
- Do not remove the current scheduler until graph parity is proven.
- Do not change the public direct command API in the first migration.
- Do not make RAG or Foundation Models responsible for final safety decisions.
- Do not force all future operations to return `HomeAutomationResolverResult`; introduce generalized outcomes internally first.

