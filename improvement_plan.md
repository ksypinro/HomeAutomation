# HomeAutomation Improvement Plan

## Summary

This document consolidates the major architectural improvement recommendations for the HomeAutomation project into a phase-by-phase roadmap. The goal is to make the system easier to extend, easier to evaluate, and easier to reason about as a modern multi-agent smart-home automation platform.

This plan focuses on modularity, graph-first orchestration, agent contracts, subgraphs, capability matching, RAG strategy, telemetry, and long-term maintainability. It does not replace existing architecture documents. Instead, it identifies the next improvement phases and calls out documentation drift that should be corrected first.

The current implementation is graph-first in source code. Phase 1 keeps the active architecture docs aligned with that reality so future work starts from the graph-only orchestrator model.

## Phase Overview

| Phase | Focus | Primary Outcome |
| --- | --- | --- |
| Phase 1 | Documentation and architecture truth cleanup | Docs match current graph-only architecture |
| Phase 2 | Root routing graph | Operation routing becomes graph-owned |
| Phase 3 | Graph scheduler decomposition | Scheduler responsibilities become independently testable |
| Phase 4 | Agent module registry | Agent wiring becomes modular |
| Phase 5 | Manifest-based data-flow validation | Graphs fail early when data contracts are broken |
| Phase 6 | First-class subgraphs | Nested automation action/condition work becomes graph-native |
| Phase 7 | Capability resolution agent | Capability matching becomes explainable and evaluable |
| Phase 8 | RAG strategy modularization | Retrieval behavior becomes per-agent and measurable |
| Phase 9 | Evaluation-ready telemetry | Logs support per-agent and whole-system evaluation |
| Phase 10 | Durable checkpoints and human interrupts | High-risk flows become resumable and auditable |

## Phase 1 - Documentation And Architecture Truth Cleanup

### What to do

- Update architecture documentation so it reflects the current graph-only implementation.
- Remove stale references to `AgentPlanner`, `AgentScheduler`, legacy runtime mode, and legacy fallback paths where they no longer exist.
- Delete `.DS_Store` files from source folders and ensure they are ignored.

### How to do it

- Review the root `README.md`, `Architecture.md`, `HomeAutomationCore/Sources/HomeAutomationOrchestrator/OrchestratorArchitecture.md`, and module READMEs.
- Replace legacy phased scheduler diagrams with `GraphPlanner`, `OperationGraphCatalog`, and `GraphScheduler`.
- Add a small "current architecture source of truth" note that points readers to the graph-only orchestrator docs.
- Confirm `.gitignore` excludes `.DS_Store`, then remove checked-in `.DS_Store` files from source folders.

### Why to do it

- Documentation drift is already visible and will mislead future work.
- A clean architecture baseline is required before deeper refactors.
- Stale references make it harder to know whether legacy scheduler concepts are still supported.

### Acceptance criteria

- No docs describe `AgentPlanner` or `AgentScheduler` as active runtime components.
- The architecture docs describe operation routing, direct command, fallback, and automation creation as graph-owned flows.
- Source folders no longer contain tracked `.DS_Store` files.

## Phase 2 - Root Routing Graph

### What to do

- Move top-level operation routing into a graph instead of running operation detection before graph planning.
- Create a root graph that starts with `operationDetection` and routes to direct command, automation creation, or unsupported handling.

### How to do it

- Introduce a `root-command-graph`.
- Make `HomeCommandOrchestrator` execute the root graph for every command.
- Represent direct command, automation creation, and unsupported handling as graph branches or subgraphs.
- Remove duplicate operation detection from the automation creation graph once root routing owns it.
- Keep operation detection Foundation Model-backed, with the deterministic semantic analyzer available as a tool or fallback.

### Why to do it

- The current flow detects the operation outside the graph and may also run operation detection inside automation creation.
- A root graph makes orchestration more consistent, observable, and extensible.
- Future operations such as automation update, automation deletion, automation query, scene creation, and routine execution can be added as graph branches instead of custom orchestrator branches.

### Acceptance criteria

- Operation detection runs once per command.
- Every command path is graph-owned.
- Pipeline events show operation detection as the first graph node.
- Unsupported operation handling is represented as graph behavior, not custom non-graph branching.

## Phase 3 - Graph Scheduler Decomposition

### What to do

- Split the current `GraphScheduler` into smaller runtime services while keeping `GraphScheduler` as the public facade.

### How to do it

- Extract `GraphDependencyTracker` to calculate ready nodes, blocked nodes, and completion state.
- Extract `GraphGuardEvaluator` to evaluate graph guards such as execution permission.
- Extract `GraphAgentSelector` to resolve agents by ID or capability.
- Extract `GraphNodeRunner` to execute one node with timeout, retry, telemetry scope, and patch handling.
- Extract `GraphRetryController` to coordinate retry policy and attempt counts.
- Extract `GraphSafetyGateHandler` to centralize fail-closed behavior.
- Extract `GraphEventEmitter` to publish UI-visible pipeline events.
- Extract `GraphTelemetryRecorder` to record structured agent, graph, and node telemetry.

### Why to do it

- `GraphScheduler` currently owns scheduling, guard evaluation, agent selection, retry, timeout, circuit breaker handling, telemetry, event emission, patch application, and fail-closed logic.
- Smaller components make behavior easier to test and safer to extend.
- The graph runtime will be easier to evolve for subgraphs, checkpoints, and branching.

### Acceptance criteria

- Existing graph behavior remains unchanged.
- Unit tests can target dependency tracking, guard evaluation, node execution, retry handling, and fail-closed handling independently.
- `GraphScheduler` remains the entry point used by the orchestrator.

## Phase 4 - Agent Module Registry

### What to do

- Break the monolithic `DefaultAgentRegistryFactory` into modular agent registration units.

### How to do it

- Introduce an `AgentModule` protocol.
- Create modules for:
  - Operation detection
  - NLU
  - Knowledge
  - Candidates
  - Draft
  - Safety
  - Execution
  - Automation
  - SmartThings
  - Fallback
- Have each module return its own `[any AnyHomeAgent]`.
- Create a shared `AgentModuleDependencies` value for common dependencies such as device registry, context retriever, model availability, policy, validators, and SmartThings creator.
- Assemble the default `AgentRegistry` from these modules.

### Why to do it

- Agent wiring is currently centralized and hard to extend safely.
- Modular registration makes it easier to add new operation families without editing one giant factory.
- It also makes it clearer which dependencies each agent group requires.

### Acceptance criteria

- The default registry is assembled from modules.
- Adding a new agent group does not require modifying unrelated agent wiring.
- Each module can be unit tested or inspected independently.

## Phase 5 - Manifest-Based Data Flow Validation

### What to do

- Use `AgentManifest.consumes` and `AgentManifest.produces` as real graph validation contracts.

### How to do it

- Extend `GraphValidator` to validate required inputs and produced outputs.
- Ensure each node's consumed keys are available from initial context or prior graph nodes.
- Validate that terminal graph paths can produce a final resolution or resolver result.
- Report data-flow errors with graph ID, node ID, missing input key, and upstream producer information when available.

### Why to do it

- The manifest already describes data dependencies but is not fully enforced.
- Data-flow validation will catch broken graph edits before runtime.
- This reduces hidden coupling between agents and graph topology.

### Acceptance criteria

- Invalid graphs fail validation before execution.
- Missing context dependencies are reported clearly with node ID and missing key.
- Safety gates cannot be configured in a way that skips required validation outputs.

## Phase 6 - First-Class Subgraphs

### What to do

- Represent nested automation action and condition resolution as first-class graph subgraphs.

### How to do it

- Add a subgraph execution abstraction with parent-to-child input mapping and child-to-parent output mapping.
- Convert `AutomationActionResolver` behavior into a graph-native subgraph runner.
- Preserve action-scoped IDs such as `a1`, `a2`, and agent invocation IDs.
- Ensure condition operand resolution can also move toward subgraph-style execution where useful.
- Store child graph metrics in parent graph metrics without flattening away action or condition scope.

### Why to do it

- Automation action resolution already behaves like a nested direct-command graph.
- Making this explicit improves observability, testing, and future nested workflows.
- It also prevents child graph state from accidentally overwriting unrelated parent graph state.

### Acceptance criteria

- Automation action fan-out still emits scoped sub-agent statuses.
- Parent graph metrics include child graph summaries.
- Child graph context cannot overwrite unrelated parent context.
- Subgraph execution supports multiple actions running in parallel or bounded parallelism.

## Phase 7 - Capability Resolution As A First-Class Agent

### What to do

- Introduce a dedicated capability decision layer.

### How to do it

- Add a `CapabilityResolutionAgent` or equivalent subsystem.
- It should output selected capability, selected command, alternatives, evidence, and confidence.
- Feed this decision into draft generation and validation.
- Use NLU intent, device type, selected candidate capabilities, canonical capability registry data, RAG snippets, and command examples as evidence.
- Keep deterministic safety validation as the final authority.

### Why to do it

- Capability matching is currently distributed across NLU, RAG, candidate ranking, instruction composition, draft generation, and validation.
- A first-class capability decision improves explainability and evaluation.
- It makes it easier to answer why the system chose `switch.on` instead of a thermostat, mode, brightness, lock, or open/close capability.

### Acceptance criteria

- Logs and metrics clearly show why a capability was selected.
- Draft generation receives capability guidance instead of rediscovering the capability from scratch.
- Safety validation remains the final authority.
- Capability alternatives and rejected candidates are available for evaluation.

## Phase 8 - RAG Strategy Modularization

### What to do

- Make retrieval strategies explicit and agent-owned.

### How to do it

- Define an `AgentRetrievalStrategy` model for source types, metadata filters, limits, ranking rules, and fallback behavior.
- Move per-agent retrieval policy out of shared helper code where practical.
- Keep canonical registries as the source of truth after retrieval.
- Ensure each RAG-backed agent declares its strategy name and retrieval purpose.
- Include strategy metadata in retrieval reports.

### Why to do it

- RAG behavior should be tunable per agent.
- This will improve prompt budget control, retrieval quality, and evaluation.
- Explicit retrieval strategies make it easier to debug weak context, irrelevant examples, and overbroad candidate retrieval.

### Acceptance criteria

- Each RAG-backed agent declares what it retrieves and why.
- Retrieval reports include strategy name, filters, source IDs, score ranges, and accepted or rejected context.
- Canonical registries remain authoritative after retrieval.

## Phase 9 - Evaluation-Ready Telemetry

### What to do

- Upgrade logging from debug-friendly daily logs to evaluation-ready traces.

### How to do it

- Add JSONL output alongside the existing daily text log.
- Include stable fields for run, graph, node, agent, invocation, action, condition, model call, tool call, latency, selected candidates, selected capability, validation result, and final outcome.
- Preserve redaction modes.
- Use `agentInvocationID` as the key for reconstructing parallel runs of the same logical agent.
- Make tool calls include parent agent invocation ID and tool invocation ID.

### Why to do it

- The project needs per-agent and whole-system evaluation.
- JSONL makes automated analysis easier than parsing text logs.
- Evaluation should be able to compare inputs, model outputs, tool usage, selected devices, selected capabilities, validation results, and final outcomes.

### Acceptance criteria

- Every agent invocation can be reconstructed from logs.
- Parallel invocations of the same agent are distinguishable by `agentInvocationID`.
- Evaluation scripts can group results by `agentID`, operation, capability, and outcome.
- Logs preserve enough metadata to evaluate both individual agents and total system performance.

## Phase 10 - Durable Checkpoints And Human Interrupts

### What to do

- Add graph checkpointing and resumable approval points.

### How to do it

- Persist graph state at safe boundaries.
- Introduce interrupt nodes for confirmation and external SmartThings rule creation.
- Resume graph execution using the same run or thread ID after user approval.
- Ensure side effects after an interrupt are idempotent or guarded by stable request IDs.
- Expose the latest checkpoint for debugging failed or paused runs.

### Why to do it

- Smart-home automation can involve high-risk or external side effects.
- Durable checkpoints allow safe approval, retry, replay, and debugging.
- Confirmation should not require rerunning expensive or nondeterministic graph nodes.

### Acceptance criteria

- Confirmation can pause and resume without rerunning completed graph nodes.
- SmartThings rule creation can be approved before external mutation.
- Failed runs can expose the last successful checkpoint.
- Resumed runs preserve run ID, operation, graph state, and relevant telemetry continuity.

## Public APIs And Interfaces To Mention

No public code API changes are required for creating this `improvement_plan.md` file.

Future implementation phases may introduce:

- `AgentModule`
- `AgentModuleDependencies`
- `GraphSubgraphNode` or an equivalent subgraph abstraction
- `AgentRetrievalStrategy`
- `CapabilityDecision`
- Checkpoint and interrupt models
- JSONL telemetry event schema

## Test Plan

This documentation-only creation does not require `swift test`.

Future implementation phases should add tests for:

- Root graph routing.
- Graph validation data-flow failures.
- Modular registry assembly.
- Subgraph action fan-out.
- Capability decision output.
- RAG strategy reports.
- JSONL telemetry schema.
- Checkpoint and resume behavior.

## Assumptions

- This file is a planning document only; code changes are separate future phases.
- Existing graph-only orchestration should remain the foundation.
- Deterministic validation and safety gates remain authoritative over model output.
- Operation detection should remain Foundation Model-backed with deterministic semantic analysis available as a tool or fallback.
- SmartThings external mutation must remain guarded by explicit validation and confirmation behavior.
