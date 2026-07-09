# Automation Parallelism — Implementation Tracker

Reference: [AutomationParallelismStrategy.md](AutomationParallelismStrategy.md)

## Phase I — Scheduling only, no behavior change
> Low risk — outputs identical, order-independent merges.

- [x] I1: SJF gate lanes (§4.4) — `FMPriority` enum (`interactive` / `pipeline`), dual-queue admission on `FoundationModelGate`, reserved interactive slot, per-priority telemetry label
- [x] I2: Parallel loop repairs (§4.5) — replace sequential `for step in plan.steps` with bounded `withTaskGroup` in `VerifierLoopOrchestrator`; merge results in deterministic specialist-priority order; same change for pre-verify zero-confidence pass
- [x] I3: Fan-out CPU cap (fix P2) — add `maxConcurrentComponents` to `AutomationComponentFanOutRunner`, cap the task group so N actions don't spawn N unbounded subgraphs
- [x] I4: Per-priority FM telemetry — thread `FMPriority` through `FoundationModelCallRecorder.record` → `FoundationModelGate.admit`, surface as `fmPriority` label on `model.call.started`
- [x] I5: Tests for Phase I + inventory update

---

## Phase II — Two-wave fan-out
> Medium risk — new scheduler replaces flat task group; behavior gated by exit criteria.

- [x] II1: Two-wave component scheduling (§4.1) — deterministic Wave 1 burst via Tier 1 mini-pipeline; FM Wave 2 implicit when τ-gate fails
- [x] II2: Clarification short-circuit (§4.7) — `group.cancelAll()` on `needsClarification` outcome + telemetry labels (`clarificationShortCircuit`, `resolvedComponentCount`, `cancelledComponentCount`)
- [x] II3: Tier 1 as Wave-1 action path — already wired via `useMiniPipeline` in `AutomationActionResolver`
- [x] II4: Tests for Phase II + inventory update — `PhaseIIParallelismTests.swift` (4 tests: clarification short-circuit, Wave 1 deterministic burst, multi-action resolution, FM gate priority)

---

## Phase III — Call reduction
> Medium risk — new prompts/schemas need shadow evaluation.

- [x] III1: Batched condition resolution (§4.2) — `BatchedConditionClauseResolver` with τ-gate per clause, `BatchedConditionClauseFMOutput` array schema, per-item fallback when confidence < 0.5; `AutomationComponentFanOutRunner` routes ≥2 conditions through batched path
- [x] III2: Session pools + pre-warming (§4.3) — `FoundationModelSessionPool` actor keyed by `SessionKind`, `acquire`/`release` lifecycle, max pool size cap; condition + trigger worker sessions use pool when available; `AutomationCoordinator.prewarmSessions()` registers instructions and pre-warms during `DefaultAgentRegistryFactory` setup
- [x] III3: Tests for Phase III + inventory update — `PhaseIIICallReductionTests.swift` (7 tests: batched resolution, single-condition fallback, pool acquire/release, pool max size, pre-warming, session kind values, deterministic path); 5 new types added to `CoordinatorTypeInventory.md`; fixed batched resolver to produce `AutomationConditionOperandResolutionRecord` entries for per-condition graph node tracking

---

## Phase IV — Speculation
> Medium risk — needs plan-diff + cancellation correctness.

- [x] IV1: Speculative segmentation overlap (§4.6) — segmentation worker `speculativeMode` returns deterministic plan immediately; fan-out runner runs Wave 1 + FM segmentation concurrently via `withTaskGroup(of: SpeculativeSegmentationOutcome.self)`; `diffPlans(deterministic:refined:)` diffs trigger/actions/conditions/conditionTree; on mismatch, changed components are re-resolved
- [x] IV2: Speculative assembly & compilation (§4.8) — `SpeculativeAssemblyCompiler` runs `AutomationDraftAssemblyAgent` + `SmartThingsRuleCompiler` speculatively after Wave 1; result carried in `AutomationResolvedComponentSet.speculativeCompilation`; downstream `AutomationDraftAssemblyAgent` and `SmartThingsCompilationAgent` short-circuit when speculative result is present
- [x] IV3: Tests for Phase IV + inventory update — `PhaseIVSpeculationTests.swift` (12 tests: plan diffing identity/trigger/action/condition/removal, speculative compilation result fields, resolved component set speculative carry/default, segmentation worker speculative/non-speculative modes, assembly agent short-circuit, end-to-end flow); 3 new types added to `CoordinatorTypeInventory.md`

---

## Notes

- Every phase must hold Phase G exit gates (accuracy ≥ baseline, clarification delta ≤ 3 pts, safety-gate parity).
- Phase I is safe to start immediately — scheduling-only, no behavior change.
- Rollout guard: `--compare-orchestration` validates each phase before merging.
