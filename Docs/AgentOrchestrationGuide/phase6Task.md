# Adaptive Portfolio Phase 6 Task Tracker

Reference: [implementation-plan.html](implementation-plan.html#phase-6)  
Phase: 6 — Compile dependency-minimal DAGs  
Created: 2026-07-13  
Status: Implemented — compiler seam and focused tests green on 2026-07-13

## Goal

Compile approved orchestration graph templates into dependency-minimal DAGs by pruning only producers whose outputs are already valid in the prepared context, replacing broad barrier edges with true data dependencies, and preserving all safety/finalization guarantees.

Phase 6 is complete when direct-command, automation-creation, fallback, finalization, and escalation graph plans can be represented as approved versioned templates, safely compiled from manifests plus seeded context/artifacts, validated before execution, and annotated with critical-path metadata for the later Phase 7 frontier scheduler.

## Current Repository Findings

- `GraphPlanner` currently constructs static graphs directly in code:
  - `rootRoutingGraph()`
  - `directCommandGraph()`
  - `fallbackGraph()`
  - `automationCreationGraph()`
  - `unsupportedGraph()`
- `OperationGraphCatalog` already selects static graph providers by operation and returns `GraphExecutionPlan`.
- `OrchestrationGraph`, `GraphNode`, `GraphEdge`, `NodeExecutionPolicy`, and `GraphGuard` are simple immutable value types and are good inputs for template/compiled graph seams.
- `AgentManifest` already declares `consumes`, `produces`, `consumedArtifacts`, `producedArtifacts`, `safetyRole`, `retryPolicy`, and `priority`.
- `GraphValidator` already checks:
  - duplicate nodes and edges;
  - missing endpoints;
  - cycles;
  - unreachable nodes;
  - optional safety gates;
  - manifest key/artifact flow from an initial `ResolutionContext`;
  - terminal output availability.
- `GraphScheduler` already validates a graph before execution and can execute a fallback path when the graph is invalid.
- Phase 5 introduced prepared request/state seams that Phase 6 can use as seed inputs, but Phase 5 structural extraction is still partial. Phase 6 should avoid depending on unfinished executor extraction unless the integration is deliberately staged.

## Scope Boundaries

### Included

- Versioned, approved graph templates for known graph families.
- Seeded graph compilation from typed context keys/artifacts and `AgentManifest` contracts.
- Safe producer pruning when all required outputs are already present and valid.
- Data-dependency edge reconstruction from manifest input/output contracts.
- Mandatory safety/finalization/mutation-approval closure that cannot be pruned.
- Compile validation with static fallback on any compiler or validator error.
- Critical-path metadata calculation for Phase 7 scheduling.
- Tests proving graph correctness, safety preservation, and parity with static templates.

### Deferred To Later Phases

- Frontier scheduling/admission decisions (Phase 7).
- Residual batching/session lifecycle changes (Phase 8).
- Learned routing/model-generated graph artifacts (Phase 9).
- Canary/production rollout automation (Phase 10).
- Arbitrary runtime graph synthesis or model-authored DAGs.

Phase 6 may compile only from approved templates already present in code. It must not invent agents, tools, operations, or unreviewed graph shapes.

## Candidate Graph Families

Phase 6 should support these graph families first:

- `rootRouting`: operation detection only; mostly a baseline template.
- `directCommand`: current direct command graph, including NLU, retrieval, ranking, draft, safety, and execution-planning gates.
- `automationCreation`: current automation creation graph, including component segmentation/fan-out, draft assembly, validation, compilation, optional rule creation, and result assembly.
- `fallback`: rule/Bixby/unsupported fallback graph.
- `unsupported`: unsupported command terminal graph.
- `finalization`: safety/finalizer graphs from `FinalizationGraphFactory`.
- `escalation`: approved loop-to-graph or loop-to-finalization continuation templates once Phase 5 escalation extraction is complete enough to expose seeded artifacts. Generic template wrapping is available, but loop-specific integration remains staged.

## Implementation Order

### P6.1 — Define Versioned Graph Templates

Primary new file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/GraphTemplate.swift`

Primary modified files:

- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/GraphPlanner.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/OperationGraphCatalog.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Finalization/FinalizationGraphFactory.swift`

Tasks:

- [x] Add `GraphTemplateID` for approved families such as direct command, automation creation, fallback, unsupported, root routing, finalization, and escalation.
- [x] Add a template version field so compiled-graph metrics can identify the source shape.
- [x] Represent immutable template nodes, edges, entry nodes, goal, and mandatory node IDs.
- [x] Mark safety/finalization/mutation approval nodes as non-prunable.
- [x] Convert existing `GraphPlanner` static graph builders to approved templates without changing planner defaults.
- [x] Keep existing public graph planner behavior unchanged until compiler activation is explicitly enabled.

Acceptance:

- [x] Existing static graph tests still pass.
- [x] Every current static graph has an equivalent approved template.
- [x] Template IDs and versions are stable and visible in metrics/debug output.

### P6.2 — Model Seeded Context And Artifact Availability

Primary new/supporting file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/DependencyMinimalGraphCompiler.swift`

Primary existing files:

- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/PreparedOrchestrationRequest.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/OrchestrationRunContext.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/ResolutionContextStore.swift`
- `HomeAutomationCore/Sources/HomeAutomationAgents/Protocols/AgentManifest.swift`

Tasks:

- [x] Define `GraphCompilationSeed` with available context keys and artifact descriptors.
- [x] Map prepared request fields into seed keys such as `request.text`, `resolutionState`, `operation`, domain/language signals, and deterministic feature outputs.
- [x] Include artifact availability from `ResolutionContext`/context store without exposing raw private payloads in metrics.
- [x] Track whether each seed is trusted, fresh, and type-compatible.
- [x] Treat stale, missing, OOD, or diagnostic-bearing prepared state conservatively.

Acceptance:

- [x] Compiler can explain why a producer was or was not pruned.
- [x] Seed validity is deterministic and does not depend on model output.
- [x] Invalid or uncertain seeds prevent pruning and fall back to the template path.

### P6.3 — Implement Dependency-Minimal Graph Compiler

Primary new file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/DependencyMinimalGraphCompiler.swift`

Tasks:

- [x] Consume an approved `GraphTemplate`, `AgentRegistry`, and `GraphCompilationSeed`.
- [x] Build per-node manifest contracts from `AgentManifest.consumes/produces` and artifact contracts.
- [x] Remove producer nodes only when every required output key/artifact is already present, fresh, and valid in the seed.
- [x] Preserve mandatory nodes, safety gates, finalization gates, mutation approval interrupts, and required fallback edges.
- [x] Replace template all-to-all barriers with true dependencies derived from producer/consumer contracts where safe.
- [x] Preserve intentional ordering edges where no manifest key captures a safety or UX invariant.
- [x] Deduplicate edges and infer entry nodes after pruning.
- [x] Emit a structured `GraphCompilationReport` with pruned nodes, retained nodes, seed keys, fallback reason, and template version.

Acceptance:

- [x] Compiled graph is never larger than the source template except for metadata.
- [x] Safety and finalization closure is non-prunable.
- [x] All retained nodes have required manifest inputs by the time they execute.
- [x] Compiler output is deterministic for the same template/seed/registry.

### P6.4 — Validate And Fail Closed To Static Graphs

Primary modified files:

- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/GraphPlanner.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/GraphScheduler.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/GraphValidator.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/OrchestratorMetrics.swift`

Tasks:

- [x] Run `GraphValidator` against every compiled graph with the seeded initial context before execution.
- [x] On compiler errors, validation errors, cycles, missing terminal outputs, missing manifests, or unsafe pruning attempts, log a compiler fallback and execute the known static graph.
- [x] Add compiler fallback metadata to `GraphExecutionPlan` and graph run metrics.
- [x] Ensure fallback execution preserves existing behavior and graph IDs where tests expect them.
- [x] Add privacy-safe telemetry/metrics payloads for compile status, template ID/version, pruned count, retained count, validation error count, and fallback reason.

Acceptance:

- [x] Malformed template/manifest/seed never reaches execution.
- [x] Invalid compiled graph always falls back to the static graph.
- [x] Compiler telemetry contains no raw command text or private device data.

### P6.5 — Add Critical Path Metadata

Primary new file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/CriticalPathAnalyzer.swift`

Primary modified files:

- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/GraphRunMetrics.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/GraphScheduler.swift`

Tasks:

- [x] Compute downstream successors for each node.
- [x] Compute topological levels and estimated remaining service cost per node.
- [x] Use conservative default service estimates until Phase 7 estimator exists.
- [x] Keep critical-path annotations outside `OrchestrationGraph` equality/hash identity.
- [x] Expose annotations through graph run metrics for Phase 7 scheduling.
- [x] Do not change scheduling order in Phase 6.

Acceptance:

- [x] Critical-path metadata is deterministic.
- [x] Graph equality/identity remains stable.
- [x] Phase 7 can consume metadata without changing graph construction APIs again.

### P6.6 — Integrate Compiler Behind A Safe Mode

Primary modified files:

- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/GraphPlanner.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/HomeAutomationCoordinator.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/HomeCommandOrchestrator.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/OrchestratorMetrics.swift`

Tasks:

- [x] Add a bounded compiler mode, for example `GraphCompilationMode.disabled`, `.shadow`, and `.active`.
- [x] Keep default mode disabled to preserve current behavior.
- [x] In shadow mode, compile and log/report the graph but execute the static template graph.
- [x] In active mode, execute the compiled graph only after validation passes.
- [x] Expose the mode through runtime dependencies/coordinator construction.
- [x] Ensure explicit graph/verifier/adaptive modes can all use the same compiler settings without nested orchestration.

Acceptance:

- [x] Default tests and existing callers remain unchanged.
- [x] Shadow mode does not change execution graph, model calls, event ordering, or result.
- [x] Active mode can be enabled in focused tests and falls back safely.

### P6.7 — Preserve Safety And Terminal Invariants

Primary files:

- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/GraphTemplate.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/DependencyMinimalGraphCompiler.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/GraphValidator.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Finalization/FinalizationGraphFactory.swift`

Tasks:

- [x] Define mandatory closure rules for safety gates, finalization nodes, confirmation interrupts, mutation approval interrupts, and fallback edges.
- [x] Prevent pruning of any node with `AgentSafetyRole.requiredGate` or `AgentSafetyRole.executionGate`.
- [x] Prevent pruning of terminal result assembly/output nodes unless a typed terminal output is already valid and explicitly allowed.
- [x] Confirm high/critical-risk commands still require confirmation/finalization gates.
- [x] Confirm SmartThings mutation approval behavior is unchanged.

Acceptance:

- [x] Safety/finalization nodes survive every compile case.
- [x] Actionable results still require finalization receipts where current code requires them.
- [x] External mutation nodes are never bypassed by seed pruning.

### P6.8 — Tests

Suggested new test file:

- `HomeAutomationCore/Tests/HomeAutomationOrchestratorTests/DependencyMinimalGraphCompilerTests.swift`

Suggested extended test files:

- `Phase2GraphInfrastructureTests.swift`
- `Phase3GraphRuntimeTests.swift`
- `FinalizationGraphFactoryTests.swift`
- `RuntimeDependencyWiringTests.swift`
- `CoordinatorRefactorTests.swift`

Tasks:

- [x] Test template conversion parity with existing graph builders.
- [x] Test direct command prepared seeds prune only valid deterministic producers.
- [x] Test automation creation prepared seeds prune only valid producers.
- [x] Test safety/finalization/mutation approval nodes are never pruned.
- [x] Test malformed manifest/seed causes static fallback.
- [x] Test cycle, reachability, and terminal-output validation failures cause static fallback.
- [x] Test broad direct-command barriers are replaced by true manifest dependencies.
- [x] Test graph result parity between unpruned template and compiled graph on representative fixtures.
- [x] Test compiled graph has fewer or equal executable nodes on eligible fixtures.
- [x] Test OOD/stale/uncertain prepared request disables pruning.
- [x] Test critical-path metadata is deterministic and excluded from graph equality.
- [x] Test shadow mode records compile report without changing executed graph.
- [x] Test active mode executes compiled graph only after validation.

### P6.9 — Documentation And Inventory

Tasks:

- [x] Update `Docs/CoordinatorTypeInventory.md` after adding Phase 6 source declarations.
- [x] Update `Docs/AgentOrchestrationGuide/implementation-plan.html` with Phase 6 implementation status after verification.
- [x] Update this tracker as each Phase 6 slice lands.
- [x] Document compiler modes, fallback behavior, and safety non-pruning rules.
- [x] Record known full-suite blockers separately from Phase 6-focused verification.

## Verification Commands

Run focused Phase 6 tests first:

```bash
swift test --filter DependencyMinimalGraphCompilerTests
swift test --filter FinalizationGraphFactoryTests
swift test --filter Phase2GraphInfrastructureTests
```

Then run targeted graph/adaptive regressions:

```bash
swift test --filter Phase3GraphRuntimeTests
swift test --filter AdaptivePortfolioIntegrationTests
swift test --filter RuntimeDependencyWiringTests
swift test --filter CoordinatorRefactorTests.coordinatorTypeInventoryListsEverySourceDeclaration
```

Then run the broader package suite:

```bash
swift test
```

If the full suite still has unrelated verifier verdict failures, capture the exact failing tests and confirm all Phase 6-focused tests are green.

Verification notes, 2026-07-13:

- `swift build` passed from `HomeAutomationCore`.
- `swift test --filter DependencyMinimalGraphCompilerTests` passed: 9 tests.
- `swift test --filter 'DependencyMinimalGraphCompilerTests|FinalizationGraphFactoryTests|Phase2GraphInfrastructureTests|Phase3GraphRuntimeTests|AdaptivePortfolioIntegrationTests|RuntimeDependencyWiringTests|CoordinatorRefactorTests.coordinatorTypeInventoryListsEverySourceDeclaration'` passed: 68 tests.
- `swift test --filter 'DependencyMinimalGraphCompilerTests|AdaptivePortfolioIntegrationTests|PortfolioShadowModeTests|StaticPortfolioRouterTests|RuntimeDependencyWiringTests|CoordinatorRefactorTests.coordinatorTypeInventoryListsEverySourceDeclaration|OrchestratorInfrastructureTests|AutomationCreationFlowTests|VerifierLoopTests|Phase3GraphRuntimeTests|Phase2GraphInfrastructureTests|FinalizationGraphFactoryTests'` passed: 151 tests.
- `swift test` did not pass: `AutomationActionResolverTests.directGraphActionResolutionSeedsRoutingState` failed reproducibly with `result.isResolved == false` after the direct action-resolution subgraph produced `Safety validation blocked: mandatory gate failed`. The Phase 6 compiler mode is disabled by default and this test does not enable it; focused Phase 6 and wider graph/adaptive regressions above are green.

## Definition Of Done

- [x] Approved versioned graph templates exist for the graph families Phase 6 supports.
- [x] Compiler prunes only producers whose outputs are already valid in typed seeds.
- [x] Compiler reconstructs true data dependencies and removes false barriers where safe.
- [x] Mandatory safety/finalization/mutation approval closure is non-prunable.
- [x] Every compiled graph is validated before execution.
- [x] Any compile/validation error falls back to the known static graph.
- [x] Critical-path metadata is computed and available for Phase 7 without affecting graph identity.
- [x] Default behavior remains unchanged unless compiler mode is explicitly enabled.
- [x] Shadow mode is decision-only and non-mutating.
- [x] Active mode executes compiled graphs only after validation passes.
- [x] Focused and targeted regression tests pass.
- [x] Documentation and type inventory are updated.

## Risks And Watch Points

- Pruning a safety/finalization gate because a similarly named context key exists.
- Treating deterministic prepared state as fresh when diagnostics, OOD, stale registry snapshots, or uncertainty should disable pruning.
- Losing intentional ordering semantics while replacing all-to-all barriers with manifest-derived edges.
- Allowing optional or fallback paths to satisfy mandatory terminal outputs incorrectly.
- Changing graph IDs/metrics in a way that breaks existing callers or evaluations.
- Letting graph annotations affect equality/hash behavior.
- Shadow mode accidentally changing execution order or model-call count.
- Hiding unrelated full-suite failures as Phase 6 regressions.
