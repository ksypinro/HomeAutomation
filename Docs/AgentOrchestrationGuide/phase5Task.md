# Adaptive Portfolio Phase 5 Task Tracker

Reference: [implementation-plan.html](implementation-plan.html#phase-5)  
Phase: 5 — Refactor arm executors and activate static adaptive mode  
Created: 2026-07-13  
Status: Partially implemented — active static seam and focused tests green on 2026-07-13

## Goal

Activate the Phase 4 static portfolio decision path safely. Phase 5 should execute the selected eligible arm inside one top-level orchestration run, without nested orchestrators, duplicated root work, reset metrics, duplicated input/outcome events, or repeated deterministic preparation.

Phase 5 is complete when `adaptivePortfolio` can use the static router to choose among graph, graph + Tier-1, and verifier-loop arms, while preserving the explicit graph and verifier-loop modes as construction-time rollback choices.

## Current Repository Findings

- Phase 4 static shadow routing is implemented. `PortfolioRolloutMode.shadowStatic` computes and logs a `PortfolioDecision`, but active execution still follows `foundationModelArm`/`orchestrationMode`.
- `HomeCommandOrchestrator` currently owns the whole run inline:
  - deterministic preparation;
  - run ID, telemetry context, event bus, ledger, metrics;
  - root routing;
  - verifier-loop branch;
  - graph direct-command, automation-creation, and unsupported branches;
  - finalization and outcome emission.
- `OrchestrationMode` currently supports only `.graph` and `.verifierLoop`.
- `FoundationModelCallArm` already has `.graph`, `.graphWithTier1`, and `.verifierLoop`, which are the active portfolio arms Phase 5 should select from.
- `HomeAutomationRuntimeDependencies` already carries `portfolioRolloutMode`, `foundationModelArm`, `orchestrationMode`, and `loopOrchestrator`, but it does not yet carry a portfolio controller or arm executors.
- `HomeAutomationCoordinator.makeRuntimeDependencies(orchestrationMode:useMiniPipeline:portfolioRolloutMode:)` currently creates a fresh metrics collector and conversation memory instead of reusing coordinator-owned observability dependencies. Phase 5 should avoid any per-arm construction path that resets run state.
- The graph + Tier-1 arm is currently modeled by building a mini-pipeline-backed `AgentRegistry` at dependency construction time. Phase 5 must make Tier-1 selection a per-request arm strategy without rebuilding registries per request.
- Loop acceptance already goes through the common finalizer for accepted verifier outputs. Loop escalation can fall through to graph, but Phase 5 must ensure escalation reuses the prepared request/envelope evidence and does not repeat deterministic preparation.
- Full `swift test` remains blocked by unrelated verifier/verdict expectations in `DraftVerifierWorkerSession` and `DraftVerdict`; Phase 5 verification should distinguish those known failures from new adaptive-portfolio regressions.

## Scope Boundaries

### Included

- A single run context that owns all per-run mutable state and shared services.
- Graph and verifier-loop arm executors that execute inside the same run context.
- Static adaptive portfolio active mode.
- Conditional root routing from prepared deterministic evidence.
- Per-request Tier-1/full-graph automation strategy selection.
- Loop escalation seeding into graph without duplicate preparation.
- Metrics and telemetry proving one input/outcome event pair, one ledger, one run ID, and selected-arm parity.

### Deferred To Later Phases

- Dependency-minimal graph compilation (Phase 6).
- Frontier Foundation Model scheduling (Phase 7).
- Residual batching/session lifecycle work (Phase 8).
- Learned routing/model artifacts (Phase 9).
- Canary rollout controls beyond local/static activation gates (Phase 10).

Phase 5 should activate the static router only; it must not introduce learned routing or dynamic graph compilation.

## Candidate Execution Arms

Active static portfolio mode should select only executable arms:

- `graph`: current graph runtime.
- `graphWithTier1`: graph runtime with Tier-1 mini-pipeline action resolution strategy.
- `verifierLoop`: verifier-loop-first path with common finalizer and graph/finalizer escalation.

Telemetry-only labels such as `exactTemplate`, `evaluation`, and `unknown` must remain non-executable.

## Implementation Order

### P5.1 — Define Active Rollout And Orchestration Mode

Primary files:

- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/PortfolioRolloutMode.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Loop/OrchestrationMode.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/HomeAutomationCoordinator.swift`

Tasks:

- [x] Extend rollout semantics with an active static mode, for example `PortfolioRolloutMode.activeStatic`.
- [x] Add `OrchestrationMode.adaptivePortfolio` as the explicit activation switch.
- [x] Preserve `.graph` and `.verifierLoop` as rollback modes.
- [x] Keep default construction on the current graph behavior.
- [x] Reject or fail closed if `adaptivePortfolio` is requested with a rollout mode that cannot execute a selected arm.
- [x] Record both selected portfolio arm and actual executing arm in metrics/telemetry.

Acceptance:

- [x] Default coordinator/orchestrator construction is behaviorally unchanged.
- [x] Explicit graph/verifier-loop modes still bypass active portfolio selection.
- [x] `adaptivePortfolio` cannot silently execute non-executable arms.

### P5.2 — Introduce `OrchestrationRunContext`

Primary new file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/OrchestrationRunContext.swift`

Tasks:

- [x] Define a `Sendable` run context object/value that owns:
  - command request and trimmed text;
  - prepared request;
  - run ID, trace ID, span ID;
  - telemetry contexts;
  - `AgentEventBus`;
  - `ResolutionContextStore`;
  - `FoundationModelUsageLedger`;
  - `OrchestratorMetrics`;
  - policy, scheduler, circuit breakers, graph planner, registry, device registry, SmartThings creator, memory, and metrics collector references;
  - finalizer factory or finalizer dependencies;
  - selected/executing arm fields.
- [ ] Move common setup currently duplicated in `HomeCommandOrchestrator.resolveStream` into context construction.
- [ ] Provide helpers for publishing input/outcome events and completing metrics exactly once.
- [x] Ensure all model-capable work runs under the same telemetry and ledger TaskLocal scopes.
- [x] Store prepared request and portfolio decision in scoped context through typed adaptive keys.
- [x] Preserve conversation memory and metrics collector from coordinator-owned dependencies.

Acceptance:

- [x] One run has exactly one run ID, event bus, ledger, metrics object, and context store.
- [x] Structured child tasks inherit the same ledger/telemetry context.
- [x] No arm execution path creates a second top-level orchestrator, ledger, metrics collector, or conversation memory.

### P5.3 — Extract Graph Arm Executor

Primary new/supporting file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/ArmExecutors.swift`

Source to refactor from: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/HomeCommandOrchestrator.swift`

Tasks:

- [x] Define an executor protocol or concrete `GraphArmExecutor` with `arm == .graph` or a strategy parameter for `.graphWithTier1`.
- [ ] Move current direct-command graph execution into the executor.
- [ ] Move current automation-creation graph execution into the executor.
- [ ] Move current unsupported-operation graph/fallback execution into the executor.
- [ ] Keep final result assembly and finalization receipt handling inside the shared run context.
- [ ] Ensure executor methods return a proposal/execution output that the top-level orchestrator finalizes/emits once.
- [ ] Avoid directly publishing terminal outcome events from inside executor internals unless mediated by the run context.
- [x] Preserve existing graph metrics, graph run IDs, node statuses, finalization receipts, and model-call attribution.

Acceptance:

- [x] Graph explicit mode produces the same user-visible outcomes as before.
- [x] Automation creation still validates/compiles/optionally creates through the common safety gates.
- [x] Unsupported operations still fail closed.
- [x] No duplicate input/outcome event is emitted.

### P5.4 — Extract Verifier Loop Arm Executor

Primary new/supporting file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/ArmExecutors.swift`

Source to wrap: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Loop/VerifierLoopOrchestrator.swift`

Tasks:

- [x] Define `VerifierLoopArmExecutor` around the existing `VerifierLoopOrchestrator`.
- [x] Execute the loop inside the shared run context/ledger/telemetry scope.
- [x] For accepted loop envelopes, call the common finalizer through shared context dependencies.
- [ ] For clarification/unsupported/non-actionable exits, return a proposal/result for top-level emission.
- [ ] For escalations, produce a typed escalation output with envelope, reason, and escalation chain.
- [x] Preserve loop metrics and per-iteration repair metrics.
- [x] Keep risk-understatement and dispute normalization semantics from Phase 1.

Acceptance:

- [x] Explicit verifier-loop mode remains behaviorally unchanged.
- [x] Accepted loop outputs are never emitted as actionable results without finalization receipt.
- [x] Loop metrics and escalation chain remain queryable as one run.

### P5.5 — Add `AdaptivePortfolioController`

Primary new file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/AdaptivePortfolioController.swift`

Tasks:

- [x] Consume `PreparedOrchestrationRequest`, `StaticPortfolioRouter`, `PortfolioEligibilityPolicy`, and arm executors.
- [x] Compute a `PortfolioDecision` exactly once per run in active static mode.
- [x] Store/log the decision with the same bounded payload as shadow mode plus active execution fields.
- [x] Select the executor for `decision.selectedArm`.
- [x] Fall back to graph if the selected arm is not executable, not eligible, or executor lookup fails.
- [x] Record selected arm, fallback reason, eligible arms, and router duration in `PortfolioMetrics`.
- [x] Keep `shadowStatic` behavior as decision-only and non-mutating.

Acceptance:

- [x] Active static mode executes the selected eligible arm.
- [x] Empty/uncertain/no-executor decisions execute graph fallback.
- [x] Shadow mode still never changes the executing arm.
- [x] Router is called once per active adaptive run.

### P5.6 — Conditional Root Routing From Prepared Evidence

Primary files:

- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/OrchestrationRunContext.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/ArmExecutors.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/HomeCommandOrchestrator.swift`

Tasks:

- [x] Define when prepared deterministic operation evidence is strong enough to seed routing without running the root FM graph.
- [x] For high-confidence in-domain direct commands and simple automation creation, seed the operation into context and skip duplicate root routing.
- [x] For low-confidence, OOD, unsupported, stale, or missing-feature cases, run the existing root routing path.
- [x] Preserve operation detection event semantics with a clear deterministic/prepared source label.
- [x] Ensure skipped root routing does not create a phantom model-call or graph-node metric.
- [x] Keep finalizer and safety gates mandatory regardless of routing source.

Acceptance:

- [x] High-confidence prepared routing avoids duplicate root routing.
- [x] OOD/low-confidence cases still run root routing or fail closed.
- [x] Model-call counts do not increase relative to explicit graph/verifier modes.

### P5.7 — Unify Tier-1 Selection Per Request

Primary files:

- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Automation/AutomationActionResolver.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Automation/AutomationComponentFanOutRunner.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/HomeAutomationCoordinator.swift`

Tasks:

- [ ] Introduce `AutomationActionResolutionStrategy` or equivalent bounded strategy enum.
- [ ] Let the automation action resolver choose full-graph vs mini-pipeline behavior from typed run context.
- [ ] Store the selected strategy in run context based on the portfolio arm.
- [x] Avoid rebuilding full and mini-pipeline registries per request.
- [x] If a full resolver refactor must be staged, build immutable graph and graph+Tier1 registries once in coordinator-owned portfolio dependencies.
- [x] Preserve existing explicit `useMiniPipeline` behavior for tests and rollback.

Acceptance:

- [x] `graphWithTier1` arm uses Tier-1 where intended.
- [x] `graph` arm does not accidentally use Tier-1.
- [x] Registry/agent construction is not repeated per request.

### P5.8 — Seed Loop Escalation Into Graph

Primary files:

- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/ArmExecutors.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Loop/LoopResultBridge.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Finalization/*`

Tasks:

- [ ] Carry loop escalation envelope, prepared request, deterministic envelope, registry snapshot, and valid artifacts into graph execution.
- [ ] Avoid repeating deterministic preparation after loop escalation.
- [ ] Preserve escalation chain `[.verifierLoop, .graph]` or `[.verifierLoop, .finalization]` in ledger entries.
- [ ] Ensure final graph/finalizer output still has a finalization receipt before any actionable result.
- [ ] Treat stale prepared snapshots conservatively: reprepare once or execute graph fallback with explicit diagnostic.

Acceptance:

- [ ] Loop-to-graph escalation does not rerun preparation.
- [ ] Escalation trace remains one run with one ledger.
- [ ] Finalization receipt invariants remain green.

### P5.9 — Integrate Top-Level Orchestrator Flow

Primary file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/HomeCommandOrchestrator.swift`

Tasks:

- [ ] Replace the large inline graph/verifier branch in `resolveStream` with:
  1. prepare request;
  2. build run context;
  3. select explicit or adaptive controller path;
  4. execute one arm;
  5. finalize/emit/store outcome once.
- [ ] Keep explicit `.graph` and `.verifierLoop` modes using the same arm executors as adaptive mode.
- [x] Ensure `run.completed` telemetry and outcome events are emitted once.
- [x] Ensure metrics are stored once, after ledger snapshot capture.
- [x] Preserve streaming behavior and event ordering except for intentionally documented adaptive decision events.
- [x] Preserve public `resolve` and `resolveStream` APIs.

Acceptance:

- [ ] Exactly one input event and one outcome event per request.
- [ ] Exactly one metrics record per request.
- [ ] Existing UI/API callers do not need changes.

### P5.10 — Tests

Suggested new test file:

- `HomeAutomationCore/Tests/HomeAutomationOrchestratorTests/AdaptivePortfolioIntegrationTests.swift`

Suggested extended test files:

- `RuntimeDependencyWiringTests.swift`
- `PortfolioShadowModeTests.swift`
- `OrchestratorInfrastructureTests.swift`
- `AutomationCreationFlowTests.swift`
- `VerifierLoopTests.swift`
- `Phase3GraphRuntimeTests.swift`

Tasks:

- [ ] Test `adaptivePortfolio` active static direct-command parity with explicit graph/verifier modes where applicable.
- [x] Test active static simple schedule chooses and executes `graphWithTier1`.
- [x] Test active static low-risk direct command chooses and executes verifier loop.
- [ ] Test device trigger/complex condition/memory/OOD/high-risk requests fall back to graph.
- [x] Test shadow mode remains decision-only after active mode is introduced.
- [x] Test active mode emits one input event and one outcome event.
- [x] Test active mode has one run ID, one ledger, one metrics record, and no nested orchestrator metrics.
- [x] Test no duplicate root model call when prepared evidence is strong.
- [ ] Test low-confidence/OOD requests still run root routing or fail closed.
- [ ] Test loop escalation reuses prepared artifacts and records escalation chain.
- [x] Test graph + Tier-1 strategy is selected per request and does not leak into graph arm.
- [x] Test construction-time rollback to explicit graph and verifier-loop modes.
- [ ] Test finalization receipt invariants for active adaptive direct command and automation creation.
- [x] Test full JSON/Codable metrics round trip with selected/executing arm and portfolio metrics.

### P5.11 — Documentation And Inventory

- [x] Update `Docs/CoordinatorTypeInventory.md` after adding Phase 5 source declarations.
- [x] Update `Docs/AgentOrchestrationGuide/implementation-plan.html` with Phase 5 implementation status after verification.
- [x] Update this tracker as each Phase 5 slice lands.
- [x] Document the active rollout modes and rollback choices.
- [x] Document event ordering and metrics semantics for active adaptive mode.
- [x] Record known full-suite external blockers separately from Phase 5-focused verification.

### P5.12 — Verification Commands

Run focused Phase 5 tests first:

```bash
swift test --filter AdaptivePortfolioIntegrationTests
swift test --filter RuntimeDependencyWiringTests
swift test --filter PortfolioShadowModeTests
```

Then run targeted parity/regression tests:

```bash
swift test --filter OrchestratorInfrastructureTests
swift test --filter AutomationCreationFlowTests
swift test --filter VerifierLoopTests
swift test --filter Phase3GraphRuntimeTests
swift test --filter CoordinatorRefactorTests.coordinatorTypeInventoryListsEverySourceDeclaration
```

Then run the broader suite:

```bash
swift test
```

If the full suite still has unrelated verifier verdict failures, capture the exact failing tests and confirm all Phase 5-focused tests are green.

Verification notes, 2026-07-13:

- `swift test --filter 'AdaptivePortfolioIntegrationTests|RuntimeDependencyWiringTests'` passed: 15 tests.
- `swift test --filter 'AdaptivePortfolioIntegrationTests|PortfolioShadowModeTests|StaticPortfolioRouterTests|RuntimeDependencyWiringTests|CoordinatorRefactorTests.coordinatorTypeInventoryListsEverySourceDeclaration'` passed: 22 tests.
- `swift test --filter 'AdaptivePortfolioIntegrationTests|PortfolioShadowModeTests|StaticPortfolioRouterTests|RuntimeDependencyWiringTests|CoordinatorRefactorTests.coordinatorTypeInventoryListsEverySourceDeclaration|OrchestratorInfrastructureTests|AutomationCreationFlowTests|VerifierLoopTests|Phase3GraphRuntimeTests'` passed: 117 tests.
- Re-ran the 117-test focused/regression filter from `HomeAutomationCore` after the router-duration metrics fix; it passed.
- Full-suite status remains to be checked after the remaining Phase 5 refactor slices; prior full-suite blocker is unrelated verifier verdict expectations in `DraftVerifierWorkerSession` and `DraftVerdict`.

Implemented slice summary:

- Active static mode is available through `OrchestrationMode.adaptivePortfolio` + `PortfolioRolloutMode.activeStatic`.
- `AdaptivePortfolioController` computes one static decision and maps it to a selected/executing arm with graph fallback for missing or non-executable executors.
- Runtime dependencies prebuild a Tier-1 registry once so `graphWithTier1` selection does not rebuild a registry per request.
- Active adaptive mode records selected/executing arms, fallback reason, portfolio decision, and portfolio metrics.
- High-confidence prepared operation evidence skips duplicate root routing in active adaptive mode.
- Explicit `.graph` and `.verifierLoop` modes remain rollback paths and pass targeted regression tests.

Remaining refactor work:

- Move common run setup and outcome completion helpers from `HomeCommandOrchestrator.resolveStream` into `OrchestrationRunContext`.
- Move direct-command, automation-creation, and unsupported graph branch bodies into concrete graph arm executor methods.
- Move verifier-loop accepted/clarification/escalation handling into concrete verifier-loop executor methods with typed proposal/escalation outputs.
- Introduce a first-class `AutomationActionResolutionStrategy` in typed run context instead of using prebuilt registry selection as the staged bridge.
- Carry prepared loop-escalation artifacts into graph execution explicitly and add focused escalation-reuse tests.

## Definition Of Done

- [ ] `OrchestrationRunContext` owns one top-level run state for explicit and adaptive modes.
- [ ] Graph and verifier-loop arm executors execute inside that shared run context.
- [x] `adaptivePortfolio` active static mode selects and executes eligible arms.
- [x] Explicit graph and verifier-loop modes remain rollback choices.
- [x] No nested `HomeCommandOrchestrator` is instantiated per arm.
- [x] Deterministic preparation runs once per request.
- [x] Root routing is skipped only when prepared deterministic evidence is strong enough.
- [ ] Loop escalation reuses prepared artifacts and preserves escalation telemetry.
- [x] Graph + Tier-1 is selected per request without per-request registry rebuilds.
- [x] Every actionable result still has a finalization receipt.
- [x] Event stream has one input and one outcome event per request.
- [x] Metrics/ledger/telemetry expose selected arm, executing arm, portfolio decision, and observed outcomes without duplicate records.
- [x] Focused and targeted regression tests pass.
- [x] Documentation and type inventory are updated.

## Risks And Watch Points

- Accidentally nesting orchestrators per arm and resetting run ID, memory, metrics, or ledger.
- Executing `.exactTemplate`, `.evaluation`, or `.unknown` as if they were real arms.
- Emitting both graph and adaptive outcome events for the same request.
- Skipping root routing on weak, stale, OOD, or missing prepared features.
- Letting Tier-1 strategy leak into explicit graph mode.
- Repeating deterministic preparation during loop escalation.
- Returning loop-accepted proposals without the common finalizer.
- Treating active static mode as production rollout without later canary/rollback controls.
- Hiding known unrelated full-suite failures as Phase 5 failures.
