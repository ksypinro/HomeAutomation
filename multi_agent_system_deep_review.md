# Analytical Architectural Review: HomeAutomation Multi-Agent System

This document reviews the `HomeAutomation` multi-agent system after the graph-only refactor and the first MAS architecture improvements. It focuses on coordination, data exchange, contract validation, graph adaptability, and performance observability.

## 1. Current Coordination Model

The project uses a centralized graph runtime:

- `GraphPlanner` selects or composes an operation graph.
- `OperationGraphCatalog` owns graph shapes for root routing, direct command, fallback, automation creation, and unsupported handling.
- `GraphScheduler` executes an `OrchestrationGraph` with dependency-aware concurrency.
- `ResolutionContextStore` is the actor-owned blackboard that applies agent patches.

Formally, each graph is a DAG:

```text
G = (V, E)
```

- `V` is the set of graph nodes.
- `E` is the set of dependency edges.
- A node is runnable when all predecessor nodes have completed or been skipped according to graph policy and guard semantics.

The ready set is:

```text
Ready(t) = { v in V | v is pending and dependencies(v) subset completed(t) }
```

The scheduler is now event-driven within the DAG. It does not wait for an entire runnable batch to finish before checking downstream readiness. When a node completes, its patch is applied, dependencies are updated, and newly ready nodes can start while unrelated nodes from the previous batch are still running. Safety gates remain dependency-ordered and are not bypassed.

## 2. Performance And Bottleneck Analysis

### 2.1 Actor Bottleneck Status

The centralized `ResolutionContextStore` actor is a possible bottleneck, not a proven one. Parallel agents still serialize at the actor boundary for `snapshot()` and `apply(_:)`, but the cost must be measured before optimizing.

Current instrumentation records:

- context snapshot duration
- context apply duration
- context key count
- runnable graph batch size
- graph node queue duration
- transition decisions

These values are emitted through graph metrics and telemetry events such as `context.snapshot`, `context.apply`, and `graph.transition`.

### 2.2 Current Optimization Posture

The safest current posture is:

- keep the actor as the only mutation owner
- use measurements to decide whether snapshots or patch application need optimization
- prefer lightweight context facets and typed artifacts before attempting deeper actor-store changes
- preserve deterministic patch conflict behavior for future batched patch application

If metrics show actor contention, likely next steps are snapshot views, specialized scoped artifact storage, and batched patch application with explicit conflict policy.

## 3. Agent Data Exchange

The system still uses a blackboard model rather than direct agent-to-agent messages:

```text
Agent A -> ResolutionContextPatch -> ResolutionContextStore -> ResolutionContext snapshot -> Agent B
```

This is a good fit for graph execution because agents remain independently testable and do not need peer references. The main risk is type-erased coupling through string keys.

### 3.1 Typed Artifact Path

The project now has a typed artifact layer:

- `ContextArtifactKey<Value>`
- `ContextArtifactStore`
- typed `ResolutionContext.artifact(for:)`
- typed `ResolutionContext.requireArtifact(for:)`
- typed `ResolutionContextPatch.setArtifact(_:for:)`

Internally, storage remains backed by `AnySendableValue` for compatibility, but new scoped exchanges can use typed keys. Wrong-type reads produce diagnostics with key name, scope, expected type, and actual type.

Automation scoped values were migrated first because automation fan-out depends heavily on scoped data exchange.

### 3.2 Context Facets

`ResolutionContext` now conforms to smaller read-only facet protocols:

- `RequestContextFacet`
- `OperationContextFacet`
- `NLUContextFacet`
- `KnowledgeContextFacet`
- `CandidateContextFacet`
- `CapabilityContextFacet`
- `AutomationContextFacet`
- `ExecutionContextFacet`

This reduces accidental coupling in input builders. Agents can be adapted toward smaller context views while the underlying context remains compatible with existing workers.

## 4. Contract Validation

Manifest validation already existed before this review and should not be described as absent. The current direction is stronger contract validation, not first-time validation.

Current validation covers:

- graph topology
- missing nodes and edges
- cycles
- unreachable nodes
- missing terminal outputs
- legacy string `consumes` / `produces`
- typed artifact contracts from `AgentManifest`

Typed artifact contracts allow graph validation to catch mismatched producer and consumer artifact types before runtime. Validation errors include graph ID, node ID, key, scope, expected type, and actual type.

## 5. Controlled Graph Adaptability

Arbitrary agent-authored graph mutation is too risky for smart-home control. The project now uses constrained transition requests instead of open-ended graph mutation.

Supported v1 transitions:

- `routeToClarification`
- `routeToUnsupported`
- `routeToFallback`
- `insertConfirmationBeforeExecution`
- `retryWithAlternateCapability`

All transitions go through `GraphTransitionPolicy`. Unknown or unsafe requests fail closed. Safety gates may only request confirmation insertion. Capability retry is limited to the capability resolution step.

Every transition is logged with:

- requesting node
- requesting agent
- transition kind
- reason
- approval or rejection

This keeps the graph adaptable without allowing agents to remove validation, skip safety gates, or add arbitrary execution nodes.

## 6. Capability Resolution Status

Capability matching remains one of the most important correctness points. The current architecture already has a first-class `CapabilityResolutionAgent`, but capability intent still emerges from several sources:

- NLU intent families
- device type extraction
- RAG capability knowledge
- candidate ranking
- instruction composition
- draft generation
- parameter and safety validation

The improved path is for `CapabilityResolutionAgent` to produce a structured `HomeCapabilityDecision` with selected capability, selected command, alternatives, evidence, and confidence. The graph can use low-confidence decisions to route to clarification and medium-confidence alternatives to request a bounded alternate capability retry. Safety validation remains the final authority.

## 7. MAS Gap Analysis

| Architectural Metric | Current Implementation | Strong MAS Target | Current Recommendation |
| --- | --- | --- | --- |
| Agent autonomy | Graph-invoked specialist agents | Fully autonomous agents | Keep graph-invoked agents for safety-critical smart-home work. |
| Coordination | Central DAG scheduler | Decentralized negotiation | Keep centralized graph coordination; add constrained transitions only. |
| Data exchange | Blackboard with typed artifact path | Strong typed messages | Continue typed artifact and facet migration. |
| Adaptability | Static graph plus approved transitions | Dynamic graph mutation | Avoid arbitrary mutation; keep policy-approved transition types. |
| Safety | Mandatory gates and fail-closed policy | Formal safety governance | Preserve deterministic safety gates as authoritative. |
| Observability | Daily logs, JSONL telemetry, graph metrics | Evaluation-grade traces | Continue expanding stable fields and per-agent evaluation metrics. |

## 8. Priority Recommendations

1. Use the new telemetry to profile real context-store costs before changing actor internals.
2. Continue migrating scoped string writes to typed artifact keys.
3. Move more input builders to context facets so agents see only the state they need.
4. Add more typed artifact contracts to manifests, especially for capability and execution outputs.
5. Keep graph transitions constrained and explicitly policy-approved.
6. Expand capability-resolution evaluation with confidence, alternatives, and recovery-path assertions.
7. Add performance tests for snapshot/apply latency, node queue time, and event-driven readiness.
8. Keep documentation aligned with the graph-first, typed-artifact, safety-gated architecture.
