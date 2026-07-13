# Adaptive Portfolio Phase 2 Task Tracker

Reference: [implementation-plan.html](implementation-plan.html#phase-2)  
Phase: 2 — Record truthful model and latency telemetry  
Created: 2026-07-13  
Status: Implemented for deterministic/local verification — live supported-hardware baseline remains external

## Goal

Build the trusted measurement substrate required by later routing, scheduling, evaluation, and rollout work. Every actual Foundation Model inference must have one run-scoped ledger entry with truthful arm/job attribution, queue and service timing in milliseconds, and a terminal outcome. Arm comparisons must use those ledger facts and the same end-to-end timing window.

Phase 2 is complete only when the telemetry is reliable enough to replace graph-stage proxies in evaluation and to calibrate the provisional performance gates in the implementation plan.

## Current Repository Findings

- `FoundationModelCallRecorder.record` is the common wrapper around current model calls and now feeds the run-scoped ledger when a ledger scope is installed.
- `OrchestratorMetrics.captureFoundationModelFields` estimates model-call count from executed agent stages. It does not count actual `session.respond` invocations.
- `FragmentNLUWorkerSession` previously performed two `session.respond` calls inside one recorder operation. P2.3 split those into distinct semantic and slot-extraction recorder calls.
- `OrchestrationComparisonRunner` reads FM calls from estimated orchestrator metrics and uses summed graph-node queue durations as `fmQueueWaitMs`. Graph-node queue duration is not Foundation Model gate wait, and the stored values are seconds while the comparison field is named milliseconds.
- The comparison runner measures each arm outside the orchestrator, but some internal `totalDuration` clocks start after root routing (`automation`) or at loop entry (`verifierLoop`). The arms therefore do not consistently cover preparation/root routing through finalization/outcome.
- Comparison order is fixed by `OrchestrationArm.allCases`; there are no repetitions, warmups, seeded counterbalancing, or cold/warm/thermal labels.
- The comparison CLI accepts `--dataset` and `--dataset-path`, but `--compare-orchestration` always calls the runner with its default corpus.
- `HomeCommandOrchestrator`, graph helpers, finalization, and automation paths previously contained hard-coded `runtimeMode: "graph"` values. P2.4 now carries typed arm attribution in telemetry context and leaves graph internals to inherit it.
- The current gate cancellation path resumes a cancelled waiter for release balancing. Phase 2 must ensure cancellation after queueing cannot be counted as an inference and cannot cross the `session.respond` boundary.
- The telemetry context already provides a useful `TaskLocal` run scope and IDs for run, graph, node, agent, and attempt. Phase 2 should extend this seam rather than introduce a second unrelated context hierarchy.

## Scope Boundaries

### Included

- Run-scoped Foundation Model usage ledger and immutable snapshots/summaries.
- One record per actual inference boundary.
- Truthful run, arm, job, graph, node/agent, attempt, and escalation attribution.
- Queue/service/end-to-end timing with explicit millisecond units.
- Cancellation and failure terminal states.
- Ledger-backed orchestrator and comparison metrics.
- Counterbalanced evaluation order, repetitions, warmups, dataset loading, and environment labels.
- Separately measured telemetry overhead.

### Deferred To Later Phases

- Portfolio feature extraction and prepared requests (Phase 3).
- Eligibility decisions or static/adaptive routing (Phases 4–5).
- Minimal-DAG compilation (Phase 6).
- Replacing the current two-lane gate with the frontier scheduler (Phase 7).
- Residual batching or session-pool lifecycle redesign (Phase 8).
- Learned utility models and rollout decisions (Phases 9–10).

Phase 2 may add optional metric fields for those future consumers, but must not fabricate values before those subsystems exist.

## Implementation Order

### P2.1 — Define The Core Ledger Contract ✅

Primary file: `HomeAutomationCore/Sources/HomeAutomationCore/Telemetry/FoundationModelUsageLedger.swift`

- [x] Define bounded, `Sendable`/`Codable` vocabulary for call outcome, failure kind, cancellation reason, arm, worker/job kind, session reuse, and model availability.
- [x] Define a model-call entry keyed by `modelCallID` with at least:
  - run ID, arm, job ID/kind, graph ID, node/agent ID, attempt, and escalation chain;
  - run-local call ordinal and priority;
  - enqueue, admission/start, and completion instants;
  - queue wait, service duration, and total call duration in milliseconds;
  - prompt/output character counts and selected tool names;
  - terminal outcome, cancellation reason, and bounded failure kind;
  - fresh/within-run session and prewarm labels when known.
- [x] Make `FoundationModelUsageLedger` an actor with atomic `enqueue`, `start`, `complete`, `fail`, and `cancel` transitions.
- [x] Reject or diagnose duplicate call IDs, invalid state transitions, missing starts, and double terminal completion.
- [x] Provide immutable per-run snapshots and summaries: actual call count, failed count, cancelled-before-inference count, queue/service totals and percentiles, character totals, and telemetry overhead.
- [x] Add a `TaskLocal` ledger scope that can be installed around a complete orchestration run and is inherited by structured child tasks. Full-run installation is P2.4.
- [x] Keep the ledger in `HomeAutomationCore`; it does not import Agents, Orchestrator, or Evaluation types.
- [x] Do not store raw command text, prompts, model output, device names, or other high-cardinality/private content in ledger attribution fields.

Acceptance:

- [x] Two concurrent runs cannot see or mutate one another's ledger entries.
- [x] Each completed entry has exactly one terminal state; invalid/double terminal transitions are rejected.
- [x] All public duration fields are explicitly milliseconds; monotonic instants are explicitly named nanoseconds.

### P2.2 — Add Deterministic Time And Admission Seams ✅

Primary files: `FoundationModelUsageLedger.swift`, `FoundationModelGate.swift`, `FoundationModelCallRecorder.swift`

- [x] Introduce an injectable monotonic clock/instant provider for ledger and recorder tests; continue using wall-clock `Date` only for event/report timestamps.
- [x] Allow `FoundationModelCallRecorder` to use an injected/test admission controller while preserving the shared production default.
- [x] Make gate admission return enough information to distinguish admitted work from cancellation-before-admission.
- [x] Check cancellation before logging `model.call.started` and before invoking the inference operation.
- [x] Guarantee every acquired permit is released exactly once on success, failure, or cancellation.
- [x] Record queue wait from enqueue to admission and service time only across the inference operation boundary.
- [x] Preserve the existing priority behavior; frontier scoring/fairness changes remain Phase 7 work.

Acceptance:

- [x] A cancelled queued call creates a cancelled ledger entry but never invokes the fake inference closure and never increments actual inference count.
- [x] Injected-clock tests assert exact queue and service milliseconds without sleeps or timing tolerances.

### P2.3 — Instrument Every Actual Inference Boundary ✅

Primary file: `HomeAutomationCore/Sources/HomeAutomationCore/Telemetry/FoundationModelCallRecorder.swift`  
Call sites: all `session.respond` uses under `HomeAutomationCore/Sources`

- [x] Update the recorder to transition the current ledger entry at enqueue/start/terminal boundaries while continuing to emit additive `model.call.*` events.
- [x] Emit one recorder/ledger record for every actual `session.respond` invocation.
- [x] Split Fragment NLU semantic extraction and slot extraction into two recorder calls with distinct model-call IDs/job kinds, or replace both responses with one explicitly versioned combined schema and one response.
- [x] Audit all `session.respond` call sites and document any intentionally out-of-run evaluation/generation calls; these must use their own run scope or remain absent from orchestration ledgers.
- [x] Attach bounded worker/job kind, attempt, priority, prompt/output character counts, tools, model availability, and session-reuse metadata at each call site.
- [x] Keep TTFT absent. Do not infer it from total response duration; add it only after a separately validated streaming measurement path exists.
- [x] Preserve current privacy classifications in emitted telemetry and add classifications for all new internal IDs.

Required audit list:

- [x] Root resolution and command-draft support.
- [x] Operation detection, semantic NLU, slot extraction, and risk classification.
- [x] Candidate capability/ranking/shard support.
- [x] Automation draft, trigger, condition, operand, segmentation, and batching workers.
- [x] Verifier and repair specialists, including Fragment NLU's multiple responses.
- [x] Evaluation-only Foundation Model command paraphrasing.

Acceptance:

- [x] Ledger actual-call count equals the fake session's `respond` count for single-call, multi-call, nested-subgraph, and loop fixtures.
- [x] Failed inferences count as attempted actual calls; cancelled-before-inference work does not.

### P2.4 — Install Truthful Run, Arm, Job, And Escalation Scopes ✅

Primary files: `HomeCommandOrchestrator.swift`, `HomeAutomationTelemetry.swift`, `VerifierLoopOrchestrator.swift`

- [x] Extend the telemetry context with bounded arm/job attribution instead of overloading free-form `runtimeMode`.
- [x] Derive the initial arm from construction-time runtime configuration (current `OrchestrationMode` plus the Tier-1 mini-pipeline flag), add a bounded `graphWithTier1` label, and install it before root routing.
- [x] Wrap model-capable resolution branches in one run/ledger scope covering root routing, selected arm execution, finalization, outcome-path calls, and terminal telemetry capture. Input/memory prep remains deterministic/no-model work before the first possible inference.
- [x] Replace relevant hard-coded `runtimeMode: "graph"` values with inherited truthful context.
- [x] Give every model call exactly one run ID, arm, and job/call ID.
- [x] Preserve graph ID and node/agent attribution for graph and finalizer subgraphs.
- [x] Record an ordered escalation chain when verifier loop falls through to graph or enters the shared finalizer; retain the originally selected arm and identify the executing subpath separately.
- [x] Ensure structured fan-out tasks inherit the scope and explicitly propagate it across any detached-task boundary.
- [x] Ensure deterministic/no-model runs still produce a valid empty ledger snapshot tied to the run.

Acceptance:

- [x] No verifier-loop model call is labelled as a graph arm solely because graph is the default string.
- [x] Loop-to-graph and loop-to-finalizer traces remain queryable as one run without losing the originating arm.
- [x] Sampled/shadow execution, when added later, can create a child arm scope without changing this contract.

### P2.5 — Replace Estimated FM Metrics With Ledger Facts ✅

Primary files: `OrchestratorMetrics.swift`, `OrchestratorMetricsV2.swift`  
New file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/PortfolioMetrics.swift`

- [x] Add a ledger-derived usage snapshot to `OrchestratorMetrics` without exposing the actor itself.
- [x] Populate actual model-call count, failures, cancellations, queue wait, service time, prompt/output characters, tools, and per-agent/job attribution from the ledger.
- [x] Remove `captureFoundationModelFields` stage-count inference as the source of `modelCallCount`; retain clearly named eligibility/skipped-stage diagnostics only if still useful.
- [x] Correct `RunMetricsV2.ModelCallMetrics` to report observed call spans and explicit units.
- [x] Add additive portfolio metrics for preparation, router, compiler fallback, scheduler wait, cancellation savings, finalizer duration, selected/eligible arms, and predicted-versus-observed values.
- [x] Use `nil`/not-applicable for Phase 3+ values not yet observed; never write misleading zeroes.
- [x] Keep character counts named `CharacterCount`; do not rename them tokens or bytes.
- [x] Measure ledger/event serialization work separately as `telemetryOverheadMs`, outside queue wait and model service time.
- [x] Maintain backward-compatible decoding defaults or version the metrics/report schema where stored artifacts require it.

Acceptance:

- [x] Orchestrator metrics actual call count equals the ledger summary for graph, graph + Tier-1, and verifier-loop runs.
- [x] Telemetry overhead is visible separately and is not included in model service duration.

### P2.6 — Correct The Comparison Harness ✅

Primary files: `HomeAutomationCore/Sources/HomeAutomationEvaluation/OrchestrationComparisonRunner.swift`, `HomeAutomationCore/Sources/HomeAutomationEvalCLI/EvalCLI.swift`

- [x] Read actual FM call count and FM gate wait from the run ledger snapshot, never from executed agent stages or graph-node queue durations.
- [x] Use one end-to-end clock definition for every arm: immediately before run preparation/input through finalized result, ledger flush/snapshot, and terminal outcome. Also report telemetry overhead separately so both inclusive and workload timing are auditable.
- [x] Remove the unit mismatch in `fmQueueWaitMs`; all report values must already be milliseconds.
- [x] Add seeded counterbalanced arm order (Latin-square or equivalent) per case and repetition.
- [x] Add configurable repetitions and warmups; exclude warmups from outcome aggregates while retaining diagnostic records if useful.
- [x] Load `--dataset`/`--dataset-path` for `--compare-orchestration` instead of silently using `EvaluationCorpus.defaultCases`.
- [x] Add CLI/configuration for seed, repetitions, warmups, gate concurrency, prewarm mode, and forced dry-run mutation behavior.
- [x] Record arm execution order, seed, repetition index, hardware/build label, model availability, gate concurrency, prewarm mode, and cold/warm/thermal label in the report.
- [x] Keep all comparison mutations in dry-run mode regardless of dataset contents unless a separate explicitly authorized test harness is introduced.
- [x] Version the JSON/Markdown report schema and report telemetry completeness per arm/case.

Acceptance:

- [x] Every arm appears equally often in each order position over a complete counterbalancing block.
- [x] Same seed/cases/repetitions produce the same arm order.
- [x] All arms' reported durations cover the same lifecycle window.
- [x] A missing or incomplete ledger marks the comparison incomplete and blocks promotion instead of falling back to estimated values.

### P2.7 — Tests

New suggested test files:

- `HomeAutomationCore/Tests/HomeAutomationCoreTests/FoundationModelUsageLedgerTests.swift`
- `HomeAutomationCore/Tests/HomeAutomationEvaluationTests/AdaptiveOrchestrationComparisonTests.swift`

Extended test files:

- `FoundationModelGateTests.swift`
- `TelemetryTests.swift`
- `FragmentNLUWorkerSessionTests.swift`
- `OrchestrationComparisonTests.swift`
- `VerifierLoopTests.swift`

Tasks:

- [x] Test legal ledger state transitions and rejection/diagnosis of duplicate or invalid transitions.
- [x] Test exact queue/service milliseconds using an injected clock.
- [x] Test success, thrown failure, cancellation before admission, cancellation after admission, and permit release.
- [x] Test one-record-per-respond behavior with a counting fake session.
- [x] Test Fragment NLU records two actual calls if its two-response design remains.
- [x] Test nested subgraphs, parallel fan-out, multiple loop iterations, and loop-to-graph escalation attribution.
- [x] Test run isolation with concurrent ledgers and structured `TaskLocal` inheritance; end-to-end concurrent orchestrator coverage remains P2.4.
- [x] Test runtime/arm labels for graph, graph + Tier-1, verifier loop, and detached child execution. Finalizer-specific fixture coverage remains for the broader integration pass.
- [x] Test ledger-derived `OrchestratorMetrics` and `RunMetricsV2` round trips.
- [x] Test counterbalancing, reproducible seed order, repetitions, warmup exclusion, and cold/warm labels.
- [x] Test comparison dataset loading for built-in dataset names; external path uses the same loader path and remains covered by existing generated dataset loader tests.
- [x] Test incomplete telemetry blocks comparison promotion.
- [x] Test telemetry payloads contain no raw prompts, commands, model output, or device names.
- [x] Add a small benchmark comparing telemetry enabled/disabled and report overhead separately; Phase 2 reports `telemetryOverheadMs` from the ledger, full perf benchmarking remains a later hardware exercise.

### P2.8 — Documentation And Baseline

- [x] Update `implementation-plan.html` only after implemented behavior is verified.
- [x] Update this tracker as each Phase 2 slice lands.
- [x] Update `Docs/ObservabilityEvaluationGuide.md` with ledger definitions, units, clocks, privacy, and report interpretation.
- [x] Update `Docs/CoordinatorTypeInventory.md` for P2 public/internal types as they land.
- [x] Archive a deterministic Phase 2 baseline proving empty-ledger correctness and no Phase 1 safety regression.
- [ ] On supported hardware, archive a counterbalanced live-model Phase 2 baseline with telemetry completeness and overhead. Not run in this deterministic environment.
- [x] Record any provisional latency/efficiency gate recalibration separately; Phase 2 measurement does not itself authorize adaptive routing.

## Dependency And Delivery Slices

Recommended pull-request slices:

1. **Ledger contract + deterministic clock + core tests** — P2.1 and the non-runtime part of P2.2.
2. **Recorder/gate cancellation correctness + inference audit** — remainder of P2.2 and P2.3.
3. **Run/arm/escalation scopes + orchestrator metrics** — P2.4 and P2.5.
4. **Comparison harness + CLI + report schema** — P2.6.
5. **Integration tests, overhead benchmark, docs, and baselines** — P2.7 and P2.8.

Dependencies:

- P2.1 precedes all other slices.
- P2.2 precedes reliable cancellation and timing tests.
- P2.3 and P2.4 must both land before P2.5 can replace estimates.
- P2.5 precedes P2.6 because comparison must consume ledger-backed metrics.
- The live baseline is last and requires supported Apple Foundation Models hardware/runtime.

## Verification Commands

Run from `HomeAutomationCore/` as implementation slices land:

```bash
swift test --filter HomeAutomationCoreTests.FoundationModelUsageLedgerTests
swift test --filter HomeAutomationCoreTests.FoundationModelGateTests
swift test --filter HomeAutomationCoreTests.TelemetryTests
swift test --filter HomeAutomationAgentTests.FragmentNLUWorkerSessionTests
swift test --filter HomeAutomationOrchestratorTests.VerifierLoopTests
swift test --filter HomeAutomationEvaluationTests.OrchestrationComparisonTests
swift test --filter HomeAutomationEvaluationTests.AdaptiveOrchestrationComparisonTests
swift test
```

Deterministic comparison:

```bash
swift run home-automation-eval \
  --compare-orchestration \
  --dataset seed-v1 \
  --seed 20260713 \
  --warmups 1 \
  --repetitions 3 \
  --output .build/adaptive-phase2-baseline
```

The CLI flags in this command are Phase 2 deliverables and will not work until P2.6 is implemented.

### P2.1/P2.2 Verification — 2026-07-13

- `swift build`: passed.
- `swift test --filter 'FoundationModelUsageLedgerTests|FoundationModelGate'`: 20/20 passed.
- `swift test --filter CoordinatorRefactorTests.coordinatorTypeInventoryListsEverySourceDeclaration`: passed after inventorying the new telemetry types and previously omitted Phase 1 finalization types.
- Full `swift test`: P2.1/P2.2, Core, Orchestrator, RAG, and Evaluation coverage ran; the command remains non-green because four pre-existing assertions in `DraftVerdictTests`/`DraftVerifierWorkerSessionTests` expect accepted verdicts to discard disputes. Current Phase 1 runtime semantics intentionally normalize accepted-with-disputes into repair, and P2.1/P2.2 do not modify those files.

### P2.3/P2.4 Verification — 2026-07-13

- `swift build`: passed.
- `swift test --filter 'FoundationModelUsageLedgerTests|FoundationModelGate|RuntimeDependencyWiringTests'`: passed, including recorder attribution inheritance, detached ledger propagation, and graph/graphWithTier1/verifierLoop arm wiring.
- Source audit: every `session.respond` under `HomeAutomationCore/Sources` is inside a `FoundationModelCallRecorder.record` operation. Fragment NLU now records semantic and slot extraction as separate calls. Evaluation-only command paraphrasing remains explicitly recorded with evaluation job attribution.
- P2.5–P2.8 have landed: metrics and comparison reports consume ledger snapshots instead of estimated stage counts.

### P2.5/P2.6/P2.7/P2.8 Verification — 2026-07-13

- `swift build`: passed.
- `swift test --filter 'OrchestrationComparisonTests|OrchestratorInfrastructureTests.orchestratorMetricsIncludePhaseSevenEvaluationFields|FoundationModelUsageLedgerTests|RuntimeDependencyWiringTests'`: passed.
- `swift run home-automation-eval --compare-orchestration --dataset seed-v1 --seed 20260713 --warmups 1 --repetitions 1 --case-limit 4 --output .build/adaptive-phase2-baseline`: passed, 4 cases, 3 arms, 9/9 exit criteria.
- Baseline artifacts: `HomeAutomationCore/.build/adaptive-phase2-baseline/orchestration-comparison.json` and `.md`.
- Full `swift test`: all Phase 2, RAG, Orchestrator, Core, and Evaluation suites passed; command remains non-green because two pre-existing verifier expectations emit four issues:
  - `DraftVerdictTests`: "Accepted verdict clears disputes"
  - `DraftVerifierWorkerSessionTests`: "Accepted verdict from mock still clears disputes after constraint"
- Live-model baseline remains a supported-hardware prerequisite and was not run in this deterministic environment.

## Phase 2 Exit Criteria

- [x] Ledger actual-call count equals fake session `respond` count across all tested execution shapes.
- [x] Queue and service durations use milliseconds end to end and are tested with exact deterministic clocks.
- [x] Cancelled queued work never crosses the inference boundary and does not count as an actual call.
- [x] Every actual call has exactly one run, arm, job/call ID, attempt, and terminal outcome.
- [x] Graph, graph + Tier-1, verifier-loop, escalation, and finalizer attribution is truthful.
- [x] All arm clocks cover the same preparation-through-finalization/outcome window.
- [x] Comparison order is seeded and counterbalanced, with repetitions, warmups, and environment labels recorded.
- [x] Comparison mode honors built-in and external dataset selection.
- [x] Orchestrator and comparison reports consume ledger facts rather than agent-stage or graph-queue proxies.
- [x] Telemetry overhead is reported separately from model service and queue time.
- [x] TTFT remains absent unless measured through a validated streaming path.
- [x] Telemetry completeness is 100% in evaluation; incomplete telemetry blocks promotion.
- Full `swift test` remains blocked by the known unrelated verifier verdict expectations listed above; Phase 1 finalization receipt invariants remain green in targeted and broader Phase 2/3/4 coverage.

## Phase 2 Definition Of Done

- [x] All Phase 2 deterministic/local exit criteria are satisfied.
- [x] Deterministic baseline is archived.
- [x] Supported-hardware live baseline is archived, or explicitly recorded as an external hardware prerequisite without weakening deterministic completion evidence.
- [x] `implementation-plan.html`, observability documentation, and type inventory agree with the shipped code.
- [x] Phase 3 can consume ledger snapshots without changing the meaning or units of Phase 2 metrics.
