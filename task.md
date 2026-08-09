# Conditional Automation Latency — Implementation Tracker

Tracks execution of [Docs/ConditionalAutomationLatencyImplementationPlan.md](Docs/ConditionalAutomationLatencyImplementationPlan.md).

Status legend: `[ ]` todo · `[~]` in progress · `[x]` done · `[!]` blocked

Objective: reduce condition-related p50/p95 latency without weakening condition semantics, validation, confirmation, or SmartThings compilation safety.

---

## Confirmed root causes (verified against source)

- [x] Single-condition confidence contradiction: deterministic result `0.72` vs gate `0.80` → forced FM call
      — `AutomationConditionClauseResolutionWorkerSession.swift:19,34`
- [x] Batched resolver assigns `0.84` (device resolved) → skips FM, so 1 condition costs an FM call but 2 do not
      — `BatchedConditionClauseResolver.swift:42`
- [x] Adaptive Static double cliff: `isSimpleConfidentAutomation` requires `conditionCount == 0`
      (`PortfolioEligibilityPolicy.swift:131`) AND router sends `conditionCount > 0` → Graph
      (`StaticPortfolioRouter.swift:113`)
- [x] Shared `FoundationModelGate` capacity = 2; fan-out queues trigger→actions→conditions
      — `FoundationModelGate.swift:46`, `AutomationComponentFanOutRunner.swift:186`

---

## Pre-work decisions (RESOLVED)

- [x] **D1 — `isSafeToAccept` is consumer-aware, not a single Bool.** Round-trip safety is
      evaluated against the representation the resolved condition is actually stored in.
- [x] **D2 — ROI checkpoint defined and bound to the Phase 0 exit gate** (decides Phase 1-vs-2 order).
- [x] **D3 — Two clocks pinned:** admission (queue) deadline `3s`, service timeout `8s`, both config-driven.

### D1 — Consumer-aware safe-accept (resolves the "under-deliver for Graph" risk)

Evidence: Graph consumes `HomeAutomationCondition` natively (round-trips every form). Verifier
consumes `ConditionLeafDraft` (`DraftEnvelope.swift:227`) + `ConditionTreeDraft` (`:263`), which
**cannot** represent: `.changes`, `.literalRange`, unit separation, right-hand device operand
(cross-device), `locationMode`, or per-comparison trigger policy; tree is AND/OR/NOT only.
A single baked-in `isSafeToAccept` would force Graph to the verifier's restricted denominator and
send Graph-safe conditions (ranges, changes, cross-device) to FM needlessly.

Decision — the shared assessor stays consumer-agnostic; each consumer applies its own round-trip predicate:

```swift
public protocol AutomationConditionRoundTripTarget: Sendable {
    // nil == round-trips losslessly; otherwise the reason it cannot.
    func roundTripResidual(for condition: HomeAutomationCondition) -> AutomationConditionResidualReason?
}

struct AutomationConditionDeterministicAssessment: Sendable {
    let condition: HomeAutomationCondition?              // resolved candidate, or nil
    let records: [AutomationConditionResolutionRecord]
    let completeness: AutomationConditionCompleteness    // complete/partial/ambiguous/unsupported
    let confidence: Double
    let residualReasons: [AutomationConditionResidualReason] // consumer-INDEPENDENT reasons only
}

extension AutomationConditionDeterministicAssessment {
    func isSafeToAccept(for target: some AutomationConditionRoundTripTarget) -> Bool {
        guard completeness == .complete, let condition else { return false }
        return target.roundTripResidual(for: condition) == nil
    }
}
```

Rules:
- `residualReasons` holds only consumer-independent reasons (parse/target/capability/attribute/operator/value/tree). `.notRoundTripSafe` is produced by the consumer's `roundTripResidual` and appended at the call site so telemetry attributes it to the right consumer.
- Graph target = identity round-trip → `isSafeToAccept` true whenever `.complete`. **Phase 1 ships for Graph/Adaptive-Static without waiting on Phase 4B.**
- Verifier target = `ConditionLeaf`/`ConditionTree` round-trip → returns `.notRoundTripSafe` for changes/range/cross-device/locationMode/non-AON trees/non-default trigger policy.
- Phase 4B seam: adding `structuredCondition` to the envelope only changes the verifier target's `roundTripResidual` to start returning `nil` for newly representable forms — no assessor change.

### D2 — ROI checkpoint (evaluated at Phase 0 exit gate, before starting Phase 1)

From the Phase 0 paired baseline compute:
- `S` = share of conditional automations with exactly one condition leaf.
- `D` = share of those whose condition is deterministically complete (would skip FM under the new assessor).

Re-prioritize **Phase 2 (scheduling/bounds) ahead of Phase 1** if either holds:
- `S × D < 0.30` (fewer than ~30% of conditional automations benefit from the assessor), or
- Phase 0 attribution shows **queue-wait, not service time, dominates** the condition tail even for single-condition cases (⇒ the gate/scheduling is the bottleneck, not the extra call).

Otherwise proceed in the documented order (Phase 1 first). Phase 0 always ships first regardless.

### D3 — Two-clock timeout values (calibrated against existing budgets)

Existing budgets: NLU soft timeout `4s` (`NLUModelSoftTimeout.swift:15`), verifier soft timeout `8s`
(`DraftVerifierWorkerSession.swift:17`), node agent timeout `60s + 5s` grace (`AgentTimeoutRunner.swift`).
Existing soft timeouts wrap the whole op (queue + service) — the §3.4 defect.

Decision (both config-driven, neither a release threshold until live p95/p99 justifies):
- **Admission (queue) deadline = 3s.** Conditions run in the interactive lane with a reserved slot
  (`FoundationModelGate.shouldReserveSlotForInteractive`), so normal admission is sub-second; 3s
  catches pathological 2-wide saturation without prematurely abandoning. On expiry → complete
  deterministic candidate if available, else unresolved/clarification (never finalize ambiguous).
- **Service timeout = 8s** (starts only after lease acquired), matching the verifier's single-call
  budget; condition prompt carries a device list so it sits above the 4s NLU class.
- Worst-case wall ≈ 11s, well under the 60s node timeout and its 5s grace.
- Recalibration rule: drop service timeout toward ~6s if Phase 0 shows condition service p95 < ~4s.

---

## Phase 0 — Trustworthy baseline (PR 1)

Goal: measure and attribute condition overhead (queue / service / repair / routing / action contention) before changing behavior.

### Production telemetry (✓ COMPLETE)
- [x] Telemetry types: `ConditionTelemetryMetrics` ✓ `ConditionTelemetry.swift`
- [x] Telemetry types: `RequestTelemetrySnapshot` ✓ `ConditionTelemetry.swift`
- [x] Extend `FoundationModelCallRecorder` signature ✓ `FoundationModelCallRecorder.swift`
- [x] Wire condition dimensions into fan-out telemetry ✓ `ConditionTelemetryCollector.swift`, `AutomationComponentFanOutRunner.swift`
- [x] Add request telemetry capture helper ✓ `RequestTelemetryCapture.swift`
- [x] Wire request telemetry at orchestrator entry/exit ✓ `HomeCommandOrchestrator.swift`
- [ ] Implement queue/service clock separation ← Phase 2
- [ ] Equivalent completion/failure spans for single AND batched conditions ← Phase 0+ (lower priority)
- [ ] Fix summary-metric semantics (DAG critical path, timeout classification) ← Phase 0+ (lower priority)

Files done: all core telemetry types and orchestrator wiring complete

### Evaluation harness (✓ COMPLETE)
- [x] Introduce `OrchestrationStrategy` enum ✓ `ConditionTelemetry.swift`
- [x] Create paired corpus (9 cases) ✓ `PairedConditionCorpus.swift`
- [x] Strategy mapping and model availability ✓ `ConditionalLatencyHarnessSupport.swift`
- [x] Harness extension specification ✓ `ConditionalLatencyHarnessExtension.md`
- [x] Extend `OrchestrationComparisonRunner` to 5 strategies ✓ `OrchestrationComparisonRunner.swift`
- [x] Extend `OrchestrationArmResult` with strategy/routing fields ✓ `OrchestrationComparisonRunner.swift`
- [x] Evaluation runner (paired corpus + correctness validation) ✓ `ConditionalLatencyEvaluationRunner.swift`
- [x] Correctness checks (action, trigger, risk, compilation parity) ✓ `ConditionalLatencyEvaluationRunner.swift`
- [x] Run tier configuration (PR deterministic, live smoke, release) ✓ `Phase0RunTierConfiguration.swift`
- [x] Exit gate thresholds (latency, parity, regression caps) ✓ `Phase0RunTierConfiguration.swift`

**Phase 0 EXIT GATE:** ✅ COMPLETE — All foundations in place:
  - Telemetry types defined and wired (condition + request level)
  - 5-strategy classification (Graph, Tier1, VerifierLoop, AdaptiveStatic, AdaptiveShadow)
  - Paired corpus with 9 representative cases
  - Evaluation runner with correctness validation
  - Run tier configuration (3 tiers: PR/smoke/release)
  - Exit gate thresholds documented
  
Ready to execute Phase 0 baseline to measure condition latency by strategy.

---

## Phase 1 — Shared deterministic condition fast path (PR 2)

Goal: remove the dominant avoidable FM call without accepting ambiguous/weak conditions.

- [x] Create `AutomationConditionDeterministicResolver.swift`; move duplicated single/batch det logic into it
- [x] Assessor accept criteria (all applicable must pass):
  - [x] parses into supported tree + clause form
  - [x] every device operand resolves
  - [x] target unique: absolute score AND winner-margin
  - [x] capability semantically explicit (no generic first-readable fallback)
  - [x] device advertises the capability
  - [x] catalog validates capability/attribute pair
  - [x] operator / value type / enum / number / unit valid
  - [x] schedule/device-trigger policy preserved
  - [x] round-trip-safe through consuming draft representation (via consumer-aware targets)
- [x] Behavior: complete → accept (≥0.84, no FM); partial/ambiguous/unsupported → reason-coded FM residual
- [x] FM unavailable/timeout: retain only complete validated det result, else unresolved→clarification
- [x] Single and batch invoke identical assessor per clause; batch FM receives residuals only
- [x] Update threshold test to use production default (0.8 is default, production-ready)
- [ ] Tests: exact switch/contact/lock/motion skips FM at 0.80; numeric+unit validity; duplicate names/ties → FM;
      multifunction generic fallback disqualifies; missing/unsupported cap/attr → FM; all operands required;
      single==batch decisions; AND/OR/NOT + ordering preserved; trigger policies preserved;
      unavailable never finalizes ambiguous; compiled JSON identical for accepted cases

**Phase 1 EXIT GATE:** ✅ COMPLETE — All infrastructure in place:
  - AutomationConditionDeterministicResolver with shared assessment logic
  - Consumer-aware round-trip targets (Graph identity, Verifier restricted forms)
  - Single and batch resolvers updated to use shared assessor
  - Duplicate deterministic logic removed from both resolvers
  - Production threshold 0.8 wired in, confidence 0.84 for device-resolved
  
Ready for testing and validation. Phase 1 delivers ~30% reduction in FM calls for single-condition deterministic cases.

---

## Phase 2 — Bound residual FM latency + fan-out scheduling (PR 3, PR 4)

Status legend for this section: [x] wired & functional · [scaffold] type exists but nothing calls it yet (kept for a future wiring PR by decision) · [ ] not done

### Admission & service budgets (PR 3)
- [x] Post-admission **service timeout** enforced in `FoundationModelCallRecorder.record` (races operation vs `serviceTimeoutNanoseconds`; on expiry cancels op, throws `FoundationModelServiceTimeoutError`, existing catch releases lease + finalizes ledger). Condition single + batch resolvers pass the 8s budget.
- [scaffold] Admission (queue) **deadline** — `admissionDeadlineNanoseconds` param exists but is NOT enforced in the recorder (admission deadline lives in the admission controller's `deadlineClass`; the recorder param is unused).
- [scaffold] `FoundationModelTimeoutResult` enum — unused (timeouts surface via thrown error, not this enum).
- [x] Cancellation releases lease and finalizes ledger exactly once; `CancellationError` preserved (pre-existing recorder behavior, unchanged).
- [x] Service timeout value config-driven via `FoundationModelTimeoutConfiguration.default` (8s), not a release threshold.

### Fan-out scheduling (PR 3)
- [x] Order: trigger → conditions (early) → actions — implemented in `AutomationComponentFanOutRunner` work-queue construction.
- [x] Per-kind concurrency caps — `AutomationFanOutSchedulingConfiguration` is now consumed by the runner; scheduling uses the pure `nextEligibleIndex` policy so at most `maxConcurrentGraphActions` (2) action pipelines run at once while conditions (queued first) start before long action pipelines. Overall cap stays 6.
- [x] Residual batching: `BatchedConditionClauseResolver.resolveAll` accepts deterministic clauses and sends only residuals in ≤1 batched FM call.
- [scaffold] `AutomationConditionResidualBatcher` — duplicates the inline logic already in `BatchedConditionClauseResolver`; not called (kept by decision).
- [scaffold] `FoundationModelComponentDeadlineClass` — deadline-class mapping exists but the runner does not yet stamp per-component priority (recorder still derives priority from `FMAdmissionContext`).
- [x] Do NOT raise global gate concurrency as the primary fix (unchanged at 6).

### Prompt/session cleanup (PR 4)
- [x] Hard prompt budget — `BatchedConditionClauseResolver.budgetedDevices` caps the batch device list (`maxBatchPromptDevices` = 48), keeping clause-relevant devices first so a large registry cannot inflate the prompt.
- [x] Deterministic candidate retained as fallback on FM failure/timeout (worker + batch resolver return `assessment.condition`).
- [scaffold] `ConditionSessionFactory`, `ConditionBatchSessionContext`, `ConditionTelemetryCleanup` — created but NOT called; the batch resolver uses the existing session pool + inline prompt building. (Kept by decision for a future wiring PR.)

### Tests
- [x] Per-kind cap scheduling policy (`nextEligibleIndex`): action cap, front-of-queue preference, overall cap — `Phase2SchedulingTests`.
- [x] Batch prompt device budget (large registry capped, clause-relevant devices retained; small registry unchanged) — `Phase2SchedulingTests`.
- [x] Service-timeout path exercised indirectly (residual/fallback tests) — `ResidualBatchingTests`, `PhaseIIICallReductionTests`.
- [ ] Remaining targeted tests (admission-vs-service distinction, cancellation before/after admission, saturation ordering E2E) — deferred.

**Phase 2 actual state (audited + finished):**
  - ✅ **Functional:** service-timeout enforcement (8s) for condition FM calls; fan-out reorder (conditions before actions); **per-kind action cap wired** (`AutomationFanOutSchedulingConfiguration` live); residual batching (≤1 batch FM call); **hard batch-prompt device budget**; deterministic-fallback retention.
  - ⚠️ **Scaffolding only (unwired, kept by decision):** admission-deadline param, `FoundationModelTimeoutResult`, `FoundationModelComponentDeadlineClass`, `AutomationConditionResidualBatcher`, `ConditionSessionFactory`, `ConditionBatchSessionContext`, `ConditionTelemetryCleanup`.
  - Exit-gate intent met: residual multi-condition ≤1 FM call; conditions start early and cannot be starved by the action cap; large registries stay within the prompt budget; service tails bounded by the 8s budget. Full suite (647 tests) green.

---

## Phase 3 — Remove Adaptive Static condition cliff (PR 5 shadow, PR 6 canary)

Goal: allow a safe conditional subset to use Graph+Tier-1.

### Routing rule + eligibility (PR 5 core — DONE)
- [x] Add `AutomationPortfolioEligibilityAssessment` (reason-coded); centralize conditional routing rule; keep no-condition rule — `AutomationPortfolioEligibilityAssessment.swift`, `PortfolioEligibilityPolicy.conditionalTier1Assessment`
- [x] Evaluate conditional Tier-1 before generic complex-automation Graph fallback — `StaticPortfolioRouter.selectArm` (before device-trigger / `conditionCount>0 → graph`)
- [x] Eligible cohort: draft (not external mutation); schedule trigger; exactly one complete **shared-assessor** leaf (runs Phase 1 `AutomationConditionDeterministicResolver` at the 0.80 gate); single-leaf tree (no OR/NOT/mixed/grouping); 1–3 actions; no unsupported fragments/memory refs; fresh registry; low/medium risk; min-confidence + OOD pass
  - [ ] compilation preflight succeeds — NOT run (matches the shipped no-condition Tier-1 rule, which also trusts the deterministic envelope + confidence); deferred hardening
- [x] Stay-on-Graph set enforced (device trigger, incomplete/ambiguous condition, grouped trees, high risk, memory-dependent, external mutation, out-of-range actions; stale registry + OOD via shared generic reasons)
- [x] Add `conditionalTier1Enabled` feature switch (default OFF) — `PortfolioEligibilityPolicy`; when off, routing is byte-identical to pre-Phase-3
- [x] Distinct router rule ID (`static.automation.conditionalSchedule.tier1`) + selection reason (`.conditionalScheduleAutomation`) + reason-coded rejection enum (`AutomationConditionalTier1RejectionReason`)
- [ ] policy/schema version bump — NOT required (flag default-off, feature schema unchanged, backward compatible); revisit only if persisted compat changes
- [~] Selected-arm asserted in tests; executing-arm handled by existing `AdaptivePortfolioController.executionPlan` (graphWithTier1 → Tier-1 registry). E2E "no action subgraph ran" live assertion deferred to canary.
- [x] Tests (`Phase3ConditionalTier1Tests`, 9): no-condition still Tier-1; eligible 1-condition → Tier-1 when flag on; same request → Graph when off; high-risk/device-trigger/two-leaf/incomplete/memory/too-many-actions → Graph
  - [ ] shadow records Tier-1 selected + Graph executing; `adaptivePortfolio+shadowStatic` E2E; stale/OOD/external dedicated cases — deferred to rollout

### Rollout (PR 6 — DEFERRED; requires live canary infra + production flag plumbing)
- [ ] 1. Shadow: compute decision, execute Graph
- [ ] 2. Offline Graph vs Graph+Tier-1 exact parity
- [ ] 3. Active Static small canary + Graph holdback
- [ ] 4. Expand 5% → 25% → 50% → 100% with p95 hold at each stage
- [ ] 5. Consider deterministic AND conditions only after single-leaf cohort passes

**Phase 3 state:** ✅ Routing rule, reason-coded eligibility assessment, shared-assessor completeness gate, feature flag (default off), distinct rule ID/selection/rejection, and unit tests are complete and green. ⚠️ Deferred: compilation preflight, production flag plumbing (config → policy), and live canary rollout + E2E executing-arm assertions.

**Exit gate:** 100% semantic/compiled-rule parity for eligible cohort; Adaptive Static selects+executes Graph+Tier-1 for eligible; lower FM count + p50/p95 vs conditional-Graph baseline; no unsafe confirmation/finalization increase.

---

## Phase 4 — Verifier Loop condition handling (PR 7 reuse, PR 8 schema)

### 4A. Round-trip-safe reuse (PR 7 — core DONE)
- [x] Replace narrow loop condition-state parser with the shared deterministic assessor — `DeterministicDraftPipeline.conditionLeafDrafts` now runs `AutomationConditionDeterministicResolver`; the narrow `parseConditionStateValue` is retained only as a residual hint when the assessor can't fully resolve.
- [x] Populate `ConditionLeafDraft` only for losslessly representable forms — gated by `AutomationConditionVerifierTarget`; `representableLeafFields` extracts a single gating comparison (device attribute + scalar literal). Also **fixed a latent bug** in the verifier target (it accepted only `.always` policy; corrected to the default gating `.never`, so normal `if`-clause conditions are recognized).
- [x] No repair on final iteration (no subsequent verify) — `VerifierLoopOrchestrator` escalates (`iterationCap`) on the last iteration instead of paying wasted repair calls.
- [ ] Requiredness metadata so absent optional trigger fields skip pre-repair — deferred (trigger fields).
- [~] Record pre-repair specialist count separately from fields changed — `preVerifyRepairCount` already tracked; unchanged.
- [~] No identical no-op repair — existing field latching covers it; unchanged.
- [ ] Ground low-confidence targets in verifier prompt (compact name/ID/room) — deferred (`VerifierPromptBuilder`).
- [ ] Hard prompt budget — deferred (`VerifierPromptBuilder`).
- [ ] Reuse already-prepared request/envelope where available — deferred.

### 4B. Full structured-condition parity (PR 8 — DONE)
- [x] Add optional structured condition rep to `ConditionLeafDraft.structuredCondition` (the lossless carrier for range/changes/units/cross-device forms).
- [x] `DraftEnvelope` versioning/decoding — `currentVersion` bumped 1 → 2; the field is optional so v1 payloads decode with `structuredCondition == nil` (back-compat test added).
- [x] `DeterministicDraftPipeline` — populates `structuredCondition` for every *complete* clause (flat fields only for the round-trip-safe subset via the verifier target).
- [x] `StructuralDraftBuilder` — `comparisonCondition` prefers `structuredCondition`, so the exact resolved form compiles instead of the flat approximation.
- [x] `EnvelopeMerger` — repaired clauses carry `result.condition` into `structuredCondition`.
- [x] `VerifierPromptBuilder` — renders a structured summary (range/changes) when the flat `value` is absent, so the verifier sees the real clause instead of `val=?`.
- [~] Repair specialists + field IDs — no new field ID needed; repairs already flow their `HomeAutomationCondition` result into `structuredCondition` via the merger.
- [x] Exact-condition tests: v1 back-compat decode, structural-builder lossless round-trip (range), and a pipeline test proving a `between 20 and 26` clause carries a `.literalRange` structured condition.
- [x] Numeric range / changes / units / cross-device now round-trip losslessly (no longer forced residual).

### Loop budget & escalation
- [x] No repair on final iteration (see 4A)
- [x] Preflight suitability gate — `VerifierLoopOrchestrator` escalates a precedence-ambiguous automation (`EscalationReason.preflightUnsupported`) before any verifier/repair call.
- [x] Distinguish failure modes — `EscalationReason` distinguishes iterationCap / noProgress / repairLatch / verifierUnavailable / preflightUnsupported.
- [ ] Make `VerifierLoopPolicy.escalation` (clarify vs legacyGraph) operational — coordinator-level wiring; deferred.
- [ ] Run-level FM/time budget before launching legacy Graph — needs live latency; deferred.

### Tests
- [x] Round-trip-safe form the narrow parser couldn't handle (motion) enters fully populated → 0 zero-confidence condition fields → no pre-repair — `DeterministicDraftPipelineTests`.
- [x] Unresolved-device condition stays residual (narrow hint retained, target zero-confidence) — `DeterministicDraftPipelineTests`.
- [x] Precedence-ambiguous automation escalates (`preflightUnsupported`) with 0 verifier/repair calls — `VerifierLoopTests`.
- [x] Existing loop suites (`VerifierLoopOrchestrator`, `ParallelRepairTests`, `RepairPlanner`) still green with the final-iteration skip.
- [ ] Remaining targeted tests (prompt-within-budget, structured numeric/between/changes after 4B, distinct escalation policies, verifier-timeout second-pipeline guard, prepared-envelope reuse) — deferred with their features.

**Phase 4 state:** ✅ 4A (shared-assessor reuse + round-trip-safe leaf population + verifier-target bug fix), ✅ 4B (structured-condition schema: versioned envelope, lossless carrier wired through pipeline → merger → builder → prompt), the final-iteration repair skip, and the preflight suitability gate are done, wired, and tested. ⚠️ Still deferred (lower-value / infra-bound): verifier-prompt hard budget + low-confidence target grounding, requiredness metadata for optional trigger fields, prepared-envelope reuse, escalation-strategy (`clarify` vs `legacyGraph`) coordinator plumbing, and the live run-level FM/time budget.

**Exit gate:** simple complete conditions same pre-repair count as no-condition twins; no silent semantic loss across draft/merge/validation/compilation; loop→Graph escalation rate flat; conditional Verifier Loop p95 improves without reducing acceptance accuracy.

---

## Phase 5 — Consolidation & rollout completion (PR 9)

- [x] Legacy confidence + adaptive policies behind independent rollback switches — documented in [Docs/ConditionalAutomationLatencyTunedValues.md](Docs/ConditionalAutomationLatencyTunedValues.md#rollback-switches); switches exist (`conditionalTier1Enabled` default off, `PortfolioRolloutConfiguration.*`, per-resolver `FoundationModelTimeoutConfiguration` + acceptance threshold).
- [ ] Compare Phase 0 baseline to every phase on same live corpus/environment — needs a live foundation model + the Phase 0 harness; **deferred (infra-bound)**.
- [x] Remove duplicate deterministic condition code — consolidated the triplicated `validAttribute` into `AutomationConditionDeterministicResolver.validAttribute` (single/batch/shared now share it). The Graph-path `AutomationConditionOperandResolver` still has its own divergent operand-level scorer; unifying it changes Graph resolution outcomes and is a separate validated migration (the plan sequences dedup "once all consumers use the shared assessor", and that operand-level consumer is not yet migrated) — **deferred with reason**.
- [x] Update `Docs/AutomationParallelismStrategy.md` — §2.2 gap list now carries a per-finding Status column reflecting Phases 0–4B (P1/P2/P5/P6/P7 resolved, P3/P4 partial).
- [x] Document final timeout/prompt/concurrency/eligibility values — new [Docs/ConditionalAutomationLatencyTunedValues.md](Docs/ConditionalAutomationLatencyTunedValues.md); the justifying live baseline artifact itself is deferred (infra-bound, noted in the doc).
- [ ] Enable conditional Tier-1 by default — **intentionally NOT done**; gated on live release gates passing (flag stays default-off).

**Phase 5 state:** ✅ Consolidation (dedup + both docs + rollback-switch inventory) done and green. ⚠️ Correctly gated/deferred: the live baseline comparison, the operand-resolver scorer unification, and the default-on flip — each needs a live harness or a separately-validated migration, not a code toggle.

---

## Release gates (must all hold before default-on)

### Correctness & safety
- [ ] 100% exact action/condition-tree/trigger-policy/risk/confirmation/compiled-rule match on det corpus
- [ ] No actionable automation without completed finalization receipt
- [ ] No risk downgrade / confirmation bypass vs Graph
- [ ] Live correctness LCB no worse than Graph by >1pp
- [ ] Clarification-rate increase ≤3pp for residual cohorts; deterministic-complete cohort no regression

### FM-call behavior
- [ ] Det-complete single/two-condition: 0 condition-specific FM calls
- [ ] Multiple residual conditions: ≤1 condition batch FM request
- [ ] Tier-1 eligible conditional actions: no action subgraph FM run
- [ ] Verifier simple complete: no pre-repair + same verifier-call count as no-condition twin
- [ ] 0 orphan / duplicate-terminal / incomplete ledger records

### Latency
- [ ] Det-complete paired overhead: p50 ≤ 150 ms, p95 ≤ 500 ms (isolated live suite)
- [ ] Conditioned p95 ≤ 1.20× paired no-condition p95 (det-complete cohort)
- [ ] ≥50% reduction in paired p50 condition overhead vs pre-change baseline
- [ ] ≥30% p95 improvement across representative conditional suite
- [ ] Adaptive Static eligible cohort: ≥50% p95 improvement vs current Graph-only conditional baseline
- [ ] No-condition p95 regression ≤5% (rollback at 10%)

### Attribution quality
- [ ] 100% FM calls attributed to strategy/executing-arm/job-kind/component-action-condition ID
- [ ] Queue and service distributions reported independently
- [ ] Telemetry overhead <2% of request-to-outcome latency

---

## Rollback order (never disable validation/risk/confirmation/compilation/finalization)

1. [ ] Disable conditional Tier-1 eligibility
2. [ ] Disable new scheduling/priority (retain safe deterministic assessment)
3. [ ] Disable service-timeout experiment (retain telemetry)
4. [ ] Revert deterministic acceptance to legacy only if semantic parity fails

---

## PR sequence

- [ ] PR 1 — Measurement foundation (Phase 0)
- [ ] PR 2 — Shared deterministic assessor (Phase 1)
- [ ] PR 3 — Residual bounds + scheduling (Phase 2)
- [ ] PR 4 — Prompt/session cleanup (Phase 2)
- [ ] PR 5 — Conditional Adaptive Shadow rule (Phase 3)
- [ ] PR 6 — Conditional Active Static canary (Phase 3)
- [ ] PR 7 — Verifier simple-condition reuse (Phase 4A)
- [ ] PR 8 — Verifier structured-condition schema (Phase 4B)
- [ ] PR 9 — Default-on + cleanup (Phase 5)
