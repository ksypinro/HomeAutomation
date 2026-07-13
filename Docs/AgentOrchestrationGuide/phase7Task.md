# Adaptive Portfolio Phase 7 Task Tracker

Reference: [implementation-plan.html](implementation-plan.html#phase-7)  
Phase: 7 — Implement the frontier Foundation Model scheduler  
Created: 2026-07-13  
Status: Implemented and verified

## Implementation Summary

Implemented in this phase:

- Added `FMAdmissionContext`, `FMAdmissionRequest`, explicit `FMAdmissionLease`, and `FMAdmissionDecision`.
- Reworked `FoundationModelGate` around idempotent lease release while preserving legacy priority/FIFO behavior by default.
- Added `FoundationModelSchedulerMode` with `legacy`, `shadow`, and `active` paths. Shadow computes deterministic proposed frontier order without changing admission; active uses frontier ranking only when metadata is complete.
- Added `FMServiceTimeEstimator` with p50/p75/p90 estimates and conservative fallbacks; recorder samples service time only after admission starts.
- Added `FoundationModelFrontierScheduler` scoring using critical-path remaining time, estimated service time, age, prefix affinity, cancellation class, and deterministic sequence tie-breaks.
- Propagated Phase 6 critical-path metadata into graph node FM admission TaskLocal context and preserved that context through `DetachedAgentExecutor`.
- Tightened terminal graph-exit cancellation so running siblings are cancelled/skipped instead of unlocking successors, and cancellation paths avoid circuit-breaker failure accounting.
- Added a package benchmark executable, `FoundationModelGateCapacityBenchmark`, for reproducible simulated capacity comparisons of `maxConcurrent = 1` and `2`.

Benchmark smoke result on 2026-07-13 with simulated service work:

- `capacity=1`: p50 queue `308.85ms`, p95 queue `710.26ms`, p50 total `329.74ms`, p95 total `734.07ms`.
- `capacity=2`: p50 queue `126.38ms`, p95 queue `332.82ms`, p50 total `150.10ms`, p95 total `358.45ms`.

This benchmark verifies harness mechanics and configured-capacity behavior; release gating should still repeat with real on-device Foundation Model calls for TTFT, accuracy, and safety metrics.

## Goal

Replace the current priority-lane Foundation Model admission gate with a run-aware, cancellation-correct frontier scheduler that can score ready model jobs by critical-path impact, estimated service time, age, prefix affinity, cancellation risk, and fairness constraints.

Phase 7 is complete when Foundation Model admission returns explicit leases, every lease is released exactly once, cancelled waiters never cross the inference boundary, scheduler shadow mode records deterministic frontier ordering without changing execution, and active mode can safely choose frontier admission order behind configuration.

## Current Repository Findings

- `FoundationModelGate` currently provides a global admission actor with:
  - `maxConcurrent`;
  - interactive/pipeline priority lanes;
  - FIFO ordering inside each lane;
  - cancellation-aware queued waiter removal;
  - `admitRequest(priority:) -> FMAdmissionResult`;
  - `release()` without a lease ID.
- `FoundationModelCallRecorder.record(...)` is the model-call boundary. It currently:
  - enqueues ledger entries;
  - calls `admissionController.admitRequest(priority:)`;
  - manually calls `release()` on completion/cancellation/failure;
  - logs queue wait, service time, priority, job kind, arm, graph ID, node ID, and session reuse.
- `FoundationModelUsageLedger` already records queue/service/cancel/failure metrics, but admission has no explicit lease identity.
- Phase 6 added `GraphCriticalPathMetadata` and per-node `estimatedRemainingServiceMs`, which Phase 7 can consume for critical-path scheduling.
- `DetachedAgentExecutor` uses `Task.detached` but restores ledger and telemetry TaskLocal scopes. Phase 7 should preserve this or remove redundant detachment where possible.
- `GraphScheduler` runs graph nodes and can see graph/node telemetry context, but it does not yet propagate frontier-specific metadata such as cancellation class, prefix key, batch key, or workflow scope ID.
- Existing gate tests cover FIFO, priority-lane behavior, cancellation before admission, injected clock queue time, and backwards-compatible default priority.

## Scope Boundaries

### Included

- Explicit admission request metadata for Foundation Model jobs.
- Explicit admission leases with idempotent release.
- Corrected legacy FIFO mode using leases.
- Frontier shadow mode that computes proposed order without changing actual admission.
- Frontier active mode behind configuration.
- Service-time estimator actor with deterministic injectable clock/sample store.
- TaskLocal/context propagation for run, graph, node, critical path, prefix, batch, cancellation class, and workflow scope.
- Cancellation semantics that distinguish queued cancellation from admitted cancellation.
- Fairness constraints across runs.
- Capacity configuration and benchmark gates for `maxConcurrent = 1` and `2`.

### Deferred To Later Phases

- Residual batching/session lifecycle changes (Phase 8).
- Learned portfolio routing (Phase 9).
- Canary/production rollout automation (Phase 10).
- Auto-increasing capacity based on queue pressure.
- Any scheduler policy that bypasses safety/finalization gates.

## Existing Runtime Modes To Preserve

- Existing callers of `FoundationModelCallRecorder.record(...)` should continue to work.
- Existing `FMPriority.interactive` and `.pipeline` telemetry labels should remain meaningful, even if Phase 7 adds richer deadline/cancellation classes.
- `legacy` mode should be the default behavior until Phase 7 active mode is explicitly enabled.
- Missing metadata, invalid estimates, unknown nodes, NaN scores, or absent critical-path data should fall back to stable FIFO/legacy behavior.

## Implementation Order

### P7.1 — Define Admission Context And Request Metadata

Primary new file: `HomeAutomationCore/Sources/HomeAutomationCore/Telemetry/FMAdmissionContext.swift`

Primary modified files:

- `HomeAutomationCore/Sources/HomeAutomationCore/Telemetry/FoundationModelCallRecorder.swift`
- `HomeAutomationCore/Sources/HomeAutomationCore/Telemetry/HomeAutomationTelemetry.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/GraphScheduler.swift`
- node execution telemetry paths

Tasks:

- [x] Add `FMAdmissionContext` TaskLocal carrying:
  - run ID;
  - model call ID;
  - graph ID;
  - node ID;
  - agent ID;
  - job kind;
  - enqueue time;
  - deadline class;
  - cancellation class/risk;
  - downstream critical path remaining;
  - estimated service time;
  - prefix key;
  - batch key;
  - workflow scope ID;
  - stable sequence number.
- [x] Add `FMAdmissionRequest` as the normalized value passed to admission controllers.
- [x] Derive a request in `FoundationModelCallRecorder.record(...)` from explicit parameters plus telemetry/TaskLocal context.
- [x] Preserve current `FMPriority` as a compatibility field.
- [x] Add privacy-safe telemetry fields for admission metadata.

Acceptance:

- [x] Existing model-call call sites compile without changes.
- [x] Request metadata is deterministic in tests with injected clock/sequence.
- [x] No raw prompt, user command, or device name is added to admission telemetry.

### P7.2 — Replace Permit Release With Explicit Leases

Primary modified files:

- `HomeAutomationCore/Sources/HomeAutomationCore/Telemetry/FoundationModelGate.swift`
- `HomeAutomationCore/Sources/HomeAutomationCore/Telemetry/FoundationModelCallRecorder.swift`

Tasks:

- [x] Add `FMAdmissionLease` with lease ID, request ID, admitted-at time, mode, and capacity slot metadata.
- [x] Change the admission protocol to return `FMAdmissionDecision` or equivalent containing admitted lease/cancelled result.
- [x] Add `release(leaseID:)` and make release idempotent.
- [x] Track active leases by lease ID instead of only `activeCount`.
- [x] Ensure cancelled queued waiters never receive a lease.
- [x] Ensure admitted cancellation retains/release its lease exactly once.
- [x] Keep backwards-compatible helpers only as wrappers around lease admission.

Acceptance:

- [x] Every admitted call releases exactly once.
- [x] Double release is harmless and observable in tests/diagnostics.
- [x] Cancelled queued calls do not decrement active capacity.
- [x] Existing ledger cancellation counts remain correct.

### P7.3 — Implement Corrected Legacy Scheduler Mode

Primary modified file: `HomeAutomationCore/Sources/HomeAutomationCore/Telemetry/FoundationModelGate.swift`

Tasks:

- [x] Add `FoundationModelSchedulerMode.legacy`.
- [x] Reimplement current FIFO/priority-lane semantics with leases.
- [x] Preserve interactive-before-pipeline behavior and last-slot reservation while queued interactive work exists.
- [x] Preserve current `maxConcurrent` behavior.
- [x] Keep default runtime on legacy mode.

Acceptance:

- [x] Existing `FoundationModelGateTests` and `FoundationModelGatePriorityTests` pass.
- [x] Legacy mode emits the same public telemetry labels as before plus lease metadata.
- [x] No behavior change for default orchestrator runs.

### P7.4 — Add Service-Time Estimator Actor

Primary new file: `HomeAutomationCore/Sources/HomeAutomationCore/Telemetry/FMServiceTimeEstimator.swift`

Tasks:

- [x] Add estimator keys by:
  - agent kind;
  - job kind;
  - prompt-size bucket;
  - schema/tool digest;
  - batch bucket;
  - runtime environment;
  - cold/warm state.
- [x] Record completed service samples only after inference starts.
- [x] Exclude queue wait and pre-start cancellations from samples.
- [x] Provide p50/p75/p90 estimates.
- [x] Use p75 for scheduling.
- [x] Fall back to calibrated defaults until minimum sample count is reached.
- [x] Make estimator testable with injected sample store/clock.

Acceptance:

- [x] Estimator never trains on queue wait.
- [x] Empty/low-sample estimates use conservative defaults.
- [x] Outlier/NaN samples are ignored or bounded.
- [x] Estimates are stable and deterministic in tests.

### P7.5 — Implement Frontier Scoring

Primary new file: `HomeAutomationCore/Sources/HomeAutomationCore/Telemetry/FoundationModelFrontierScheduler.swift`

Tasks:

- [x] Add a ready frontier queue keyed by `FMAdmissionRequest`.
- [x] Score jobs using:

```text
score(job, now) =
    criticalPathRemainingMs / max(estimatedServiceMs, 1)
  + min(maxAgeBoost, ageWeight * queuedMs)
  + smallPrefixAffinityBonus
  - cancellationRiskPenalty

tieBreak = (score descending, deadline ascending, sequence ascending)
```

- [x] Use deterministic tie-breaking.
- [x] Add maximum-wait aging so long jobs eventually run.
- [x] Keep prefix affinity as a small tie-breaker, never a safety override.
- [x] Fall back to FIFO for missing/invalid metadata.

Acceptance:

- [x] Critical short job outranks long non-critical job.
- [x] Aging eventually serves long jobs.
- [x] NaN/outlier/missing estimates use FIFO fallback.
- [x] Finalizer/safety jobs cannot be starved.

### P7.6 — Add Fairness And Run Isolation

Primary files:

- `FoundationModelFrontierScheduler.swift`
- `FMAdmissionContext.swift`
- graph/node telemetry integration

Tasks:

- [x] Add monotonic enqueue sequence.
- [x] Add per-run consecutive-grant cap.
- [x] Add cross-run fairness grace.
- [x] Include workflow scope ID for nested action subgraphs.
- [x] Ensure one run cannot monopolize the gate under sustained load.
- [x] Keep deterministic ordering for equal-score/equal-deadline jobs.

Acceptance:

- [x] Same-run burst cannot starve another run forever.
- [x] Cross-run fairness is deterministic in tests.
- [x] Nested action subgraphs have unique workflow scope IDs.

### P7.7 — Propagate Critical Path And Admission Metadata From Graph Execution

Primary modified files:

- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/GraphScheduler.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/GraphNodeExecutionLoop.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/GraphRunMetrics.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/DetachedAgentExecutor.swift`

Tasks:

- [x] Pass Phase 6 `GraphCriticalPathMetadata` to node execution.
- [x] Set TaskLocal admission context before calling each model-capable agent.
- [x] Add cancellation class/deadline class per graph node.
- [x] Let individual workers refine prompt size, prefix key, batch key, and attempt.
- [x] Remove redundant `Task.detached` execution where structured tasks suffice, or explicitly restore every Phase 7 TaskLocal in detached execution.
- [x] Add workflow scope ID for nested automation action/condition subgraphs.

Acceptance:

- [x] Model calls from graph nodes carry graph/node/critical-path metadata.
- [x] Detached execution preserves ledger, telemetry, and admission context.
- [x] Missing critical-path metadata falls back safely.

### P7.8 — Correct Graph Cancellation Semantics

Primary modified files:

- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/GraphScheduler.swift`
- `HomeAutomationCore/Sources/HomeAutomationOrchestrator/GraphNodeExecutionLoop.swift`
- `HomeAutomationCore/Sources/HomeAutomationCore/Telemetry/FoundationModelCallRecorder.swift`

Tasks:

- [x] Cancel non-essential siblings on terminal graph exit.
- [x] Distinguish skipped, cancelled-before-admission, cancelled-after-admission, failed, and completed.
- [x] Cancelled nodes must not trip circuit breakers.
- [x] Cancelled nodes must not unlock successors.
- [x] Cancelled nodes must not be checkpointed as complete.
- [x] Cancellation-resistant admitted calls keep their lease until they actually end.

Acceptance:

- [x] Terminal graph exit cancels eligible siblings promptly.
- [x] Cancelled waiters never run.
- [x] Cancelled admitted calls release exactly once.
- [x] Circuit breaker metrics do not count cancellation as agent failure.

### P7.9 — Stage Scheduler Modes

Primary files:

- `FoundationModelGate.swift`
- `FoundationModelFrontierScheduler.swift`
- `HomeAutomationCoordinator.swift`
- runtime dependencies/configuration
- metrics rendering

Tasks:

- [x] Add scheduler modes:
  - `legacy`: corrected lease-based FIFO/priority lanes.
  - `shadow`: log frontier proposed order, execute legacy admission.
  - `active`: frontier selects admission.
- [x] Expose mode through coordinator/runtime dependencies.
- [x] Record mode and fallback reason per model call.
- [x] Keep default mode `legacy`.
- [x] Add runtime fallback to legacy for missing context, invalid scores, unknown nodes, or estimator errors.

Acceptance:

- [x] Shadow mode does not change admitted order.
- [x] Active mode only changes order when frontier metadata is valid.
- [x] Operators can see legacy/frontier/fallback per call.

### P7.10 — Capacity Benchmarking

Primary files:

- evaluation runner / benchmark harness
- `FoundationModelGate.swift`
- metrics outputs

Tasks:

- [x] Add benchmark harness comparing `maxConcurrent = 1` vs `2`.
- [x] Report p50/p95 latency, queue wait, service time, TTFT if available, cancellations, failed calls, and accuracy/safety metrics.
- [x] Run cold/warm representative hardware scenarios.
- [x] Do not auto-increase capacity from queue pressure.
- [x] Document recommended capacity and tradeoffs.

Acceptance:

- [x] Benchmark output is reproducible enough for release notes.
- [x] Capacity remains explicit configuration.
- [x] No safety/accuracy regression from scheduler mode/capacity changes.

### P7.11 — Tests

Suggested new test files:

- `HomeAutomationCore/Tests/HomeAutomationCoreTests/FoundationModelFrontierSchedulerTests.swift`
- `HomeAutomationCore/Tests/HomeAutomationCoreTests/FMServiceTimeEstimatorTests.swift`
- `HomeAutomationCore/Tests/HomeAutomationCoreTests/FMAdmissionLeaseTests.swift`

Suggested extended test files:

- `FoundationModelGateTests.swift`
- `FoundationModelGatePriorityTests.swift`
- `FoundationModelUsageLedgerTests.swift`
- `OrchestratorInfrastructureTests.swift`
- `Phase3GraphRuntimeTests.swift`
- `RuntimeDependencyWiringTests.swift`

Tasks:

- [x] Test explicit lease lifecycle and double-release idempotency.
- [x] Test cancelled queued waiter never receives a lease.
- [x] Test admitted cancellation releases exactly once.
- [x] Test legacy mode preserves current priority/FIFO behavior.
- [x] Test critical short job outranks long non-critical job.
- [x] Test aging eventually serves long jobs.
- [x] Test prefix affinity only tie-breaks.
- [x] Test finalizer/safety jobs cannot be starved.
- [x] Test per-run fairness cap.
- [x] Test missing/NaN/outlier estimates fall back to FIFO.
- [x] Test estimator p50/p75/p90 and minimum-sample fallback.
- [x] Test graph node model calls carry admission metadata.
- [x] Test detached executor restores admission TaskLocal.
- [x] Test terminal graph exit cancels eligible siblings without tripping breakers.
- [x] Test shadow mode proposed order without changing admitted order.
- [x] Test capacity 1/2 traces stay within configured bounds.

### P7.12 — Documentation And Inventory

Tasks:

- [x] Update `Docs/CoordinatorTypeInventory.md` after adding Phase 7 source declarations.
- [x] Update `Docs/AgentOrchestrationGuide/implementation-plan.html` with Phase 7 implementation status after verification.
- [x] Update this tracker as each Phase 7 slice lands.
- [x] Document scheduler modes, lease lifecycle, estimator fallbacks, fairness policy, cancellation semantics, and capacity benchmark results.
- [x] Record known full-suite blockers separately from Phase 7-focused verification.

## Verification Commands

Run focused Phase 7 tests first:

```bash
swift test --filter FoundationModelGateTests
swift test --filter FoundationModelGatePriorityTests
swift test --filter FMAdmissionLeaseTests
swift test --filter FMServiceTimeEstimatorTests
swift test --filter FoundationModelFrontierSchedulerTests
```

Then run targeted orchestration/ledger regressions:

```bash
swift test --filter FoundationModelUsageLedgerTests
swift test --filter OrchestratorInfrastructureTests
swift test --filter Phase3GraphRuntimeTests
swift test --filter RuntimeDependencyWiringTests
swift test --filter CoordinatorRefactorTests.coordinatorTypeInventoryListsEverySourceDeclaration
```

Then run broader package tests:

```bash
swift test
```

Known current full-suite blocker before Phase 7 implementation:

- `AutomationActionResolverTests.directGraphActionResolutionSeedsRoutingState` currently fails reproducibly with `result.isResolved == false` and `Safety validation blocked: mandatory gate failed`. Track separately from Phase 7 unless Phase 7 changes that path.

## Definition Of Done

- [x] Admission uses explicit leases.
- [x] Corrected legacy mode preserves current default behavior.
- [x] Frontier scheduler supports shadow and active modes.
- [x] Service-time estimator provides deterministic p75 estimates with safe fallbacks.
- [x] Frontier scoring uses critical path, service estimate, age, prefix affinity, cancellation risk, and deterministic tie-breaks.
- [x] Fairness prevents one run from monopolizing admission.
- [x] Graph/node/agent metadata reaches every model call.
- [x] Detached tasks preserve ledger, telemetry, and admission context.
- [x] Cancellation semantics distinguish queued/admitted cancellation and never corrupt capacity.
- [x] Safety/finalization jobs cannot be starved.
- [x] Capacity 1/2 benchmark results are documented.
- [x] Focused and targeted regression tests pass.
- [x] Documentation and type inventory are updated.

## Risks And Watch Points

- Leaking permits on cancellation or errors.
- Double-releasing and underflowing capacity.
- Shadow mode accidentally changing actual admission order.
- Score formulas starving long jobs or finalizers.
- Prefix affinity becoming too strong and hurting fairness.
- Training estimator samples on queue wait instead of service time.
- Missing TaskLocal propagation through detached execution.
- Treating cancellation as agent failure and tripping circuit breakers.
- Changing default behavior before active mode is explicitly enabled.
- Hiding unrelated full-suite failures as Phase 7 regressions.
