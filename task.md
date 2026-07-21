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

### Production telemetry
- [x] Telemetry types: `ConditionTelemetryMetrics` (leaf/tree/depth/shape, completeness, confidence, residual reasons, resolution mode, prompt/output, queue/service/total timing, critical-path flag, component ID) ✓ `ConditionTelemetry.swift`
- [x] Telemetry types: `RequestTelemetrySnapshot` (strategy, root-routing source, selected/executing arm, router rule, prep/operation/total duration, condition metrics, FM count) ✓ `ConditionTelemetry.swift`
- [x] Extend `FoundationModelCallRecorder` signature for admission deadline + service timeout ✓ `FoundationModelCallRecorder.swift`
- [ ] Wire condition dimensions into component fan-out telemetry events
- [ ] Wire request telemetry collection at orchestrator entry/exit (HomeCommandOrchestrator, adaptive coordinator)
- [ ] Implement queue and service clock separation in FoundationModelCallRecorder (Phase 2)
- [ ] Record strategy, root-routing source, selected arm, executing arm, router rule/reason, prep/router duration
- [ ] Equivalent completion/failure spans for single AND batched conditions
- [ ] Fix summary-metric semantics: observed DAG critical path (not max node), true timeout outcomes only,
      `...Ms` unit correctness, separate leaf / tree-node / device-trigger counts

Files: `FoundationModelUsageLedger.swift`, `FoundationModelCallRecorder.swift` (✓ started), `AutomationComponentFanOutRunner.swift`, `HomeCommandOrchestrator.swift`, `OrchestratorMetrics.swift`, `OrchestratorMetricsV2.swift`

### Evaluation harness
- [x] Introduce `OrchestrationStrategy` enum (graph, graphWithTier1, verifierLoop, adaptiveStatic, adaptiveShadow) ✓ `ConditionTelemetry.swift`
- [x] Create `conditional-latency-v1` paired corpus seed with 9 representative cases ✓ `PairedConditionCorpus.swift`
- [ ] Extend `OrchestrationComparisonRunner` to 5 strategies: Graph, Graph+Tier-1, Verifier Loop, Adaptive Static (`adaptivePortfolio`+`activeStatic`), Adaptive Shadow (`adaptivePortfolio`+`shadowStatic`)
- [ ] Require explicit live-model opt-in + `.available`; fail artifact if availability lost / ledger nonterminal
- [ ] Configure (not just label) gate capacity and prewarm lifecycle
- [ ] Support cold coordinators AND production-like retained warm coordinators
- [ ] External monotonic end-to-end timing
- [ ] Raw JSONL per run + JSON + Markdown summaries
- [ ] Compare only correct paired runs for latency; report correctness failures separately
- [ ] Expand corpus dimensions: condition count 0–3, forms (state/numeric/range/changes), resolution (unique/ambiguous/missing/unsupported), tree (leaf/AND/OR/NOT/mixed), actions 1–3, trigger (schedule/device), risk, registry size
- [ ] Correctness checks: action count/targets, exact condition tree+order, device/cap/attr/operator/value/units, trigger policy, risk+confirmation, canonical compiled SmartThings JSON
- [ ] Run tiers wired: PR deterministic (3 reps, no wall-clock gate), Live smoke (5 reps), Release (≥8 families, warm+cold, ≥10 reps, Latin-square order)

**Exit gate:** checked-in live baseline proving model availability, nonzero condition FM usage where expected, all 5 strategies covered, exact condition/compiled-rule correctness.

---

## Phase 1 — Shared deterministic condition fast path (PR 2)

Goal: remove the dominant avoidable FM call without accepting ambiguous/weak conditions.

- [ ] Create `AutomationConditionDeterministicResolver.swift`; move duplicated single/batch det logic into it
- [ ] Assessor accept criteria (all applicable must pass):
  - [ ] parses into supported tree + clause form
  - [ ] every device operand resolves
  - [ ] target unique: absolute score AND winner-margin
  - [ ] capability semantically explicit (no generic first-readable fallback)
  - [ ] device advertises the capability
  - [ ] catalog validates capability/attribute pair
  - [ ] operator / value type / enum / number / unit valid
  - [ ] schedule/device-trigger policy preserved
  - [ ] round-trip-safe through consuming draft representation
- [ ] Behavior: complete → accept (≥0.84, no FM); partial/ambiguous/unsupported → reason-coded FM residual
- [ ] FM unavailable/timeout: retain only complete validated det result, else unresolved→clarification
- [ ] Single and batch invoke identical assessor per clause; batch FM receives residuals only
- [ ] Update threshold test to use production default (remove 0.70 masking)
- [ ] Tests: exact switch/contact/lock/motion skips FM at 0.80; numeric+unit validity; duplicate names/ties → FM;
      multifunction generic fallback disqualifies; missing/unsupported cap/attr → FM; all operands required;
      single==batch decisions; AND/OR/NOT + ordering preserved; trigger policies preserved;
      unavailable never finalizes ambiguous; compiled JSON identical for accepted cases

**Exit gate:** complete det conditions → 0 condition-specific FM calls; ambiguous/incomplete still FM/clarify; 100% tree + compiled-rule parity on deterministic corpus.

---

## Phase 2 — Bound residual FM latency + fan-out scheduling (PR 3, PR 4)

### Admission & service budgets (PR 3)
- [ ] Extend `FoundationModelCallRecorder`/dependency: admission deadline, post-admission service timeout, explicit job kind + effective priority
- [ ] Typed timeout result; cancellation releases lease and finalizes ledger exactly once; preserve `CancellationError`
- [ ] Calibrate values from Phase 0 (service timeout config-driven, not a release threshold)

### Fan-out scheduling (PR 3)
- [ ] Order: trigger → condition group early (residuals batched) → actions under per-kind caps → keep overall cap
- [ ] Caps: Graph action pipelines = 2 concurrent; Tier-1 mini-pipelines may use wider cap; one condition batch/automation; overall = 6 until benchmarks justify change
- [ ] FM priorities: conditions/verifier = interactive; nested Graph action subgraphs = pipeline; derive default from `FMAdmissionContext` (stop hard-coding interactive)
- [ ] Do NOT raise global gate concurrency as the primary fix

### Prompt/session cleanup (PR 4)
- [ ] Single and batch share session-factory dependencies
- [ ] Distinct condition-batch job/session kind
- [ ] Batch context = union of per-clause relevant devices with hard prompt budget
- [ ] Retain each det candidate; close ambiguity alternatives
- [ ] Remove tool-selection telemetry for unattached tools
- [ ] Prewarm lazy/idempotent, residual session kinds only; record prewarm/reuse state

- [ ] Tests: delayed admission doesn't consume service budget; admission vs service timeout distinct;
      cancel before/after admission frees resources; conditions start before long action pipelines under saturation;
      no action exceeds Graph action cap; early clarification cancels safely; ≥1 residual → ≤1 condition FM request;
      large registry within prompt budget; result order + condition IDs stable after batching

**Exit gate:** no orphan/nonterminal ledger calls or leaked leases; residual multi-condition ≤ 1 batch FM call; condition queue/service tails bounded; no-condition p95 regression ≤ 5% in isolated release runs.

---

## Phase 3 — Remove Adaptive Static condition cliff (PR 5 shadow, PR 6 canary)

Goal: allow a safe conditional subset to use Graph+Tier-1.

- [ ] Add `AutomationPortfolioEligibilityAssessment`; centralize conditional routing rule; keep no-condition rule
- [ ] Evaluate conditional Tier-1 before generic complex-automation Graph fallback
- [ ] Eligible cohort: draft (not external mutation); schedule trigger; exactly one complete shared-assessor leaf;
      no OR/NOT/mixed/grouping ambiguity; 1–3 Tier-1-resolvable actions; no unsupported fragments/memory refs;
      fresh registry; low/medium risk; min-confidence + OOD pass; compilation preflight succeeds
- [ ] Stay-on-Graph set enforced (device trigger, ambiguous/unsupported/non-round-trip condition, grouped trees, high risk, stale registry, memory-dependent, external mutation, non-Tier-1 action)
- [ ] Add `conditionalTier1Enabled` feature switch (default OFF)
- [ ] Distinct router rule ID + rejection reason; policy/schema version bump if persisted compat requires
- [ ] Selected-arm and executing-arm assertions; E2E assertion that Tier-1 conditional action ran no action subgraph
- [ ] Tests: no-condition still Tier-1; eligible 1-condition → Tier-1 when flag on; same request → Graph when off;
      ambiguous/unsupported/grouped/device-trigger/memory/high-risk/OOD/stale/external → Graph;
      active uses mini pipeline; shadow records Tier-1 selected + Graph executing;
      `adaptivePortfolio+shadowStatic` covered; old learned-router artifacts fail compat safely → static

### Rollout
- [ ] 1. Shadow: compute decision, execute Graph
- [ ] 2. Offline Graph vs Graph+Tier-1 exact parity
- [ ] 3. Active Static small canary + Graph holdback
- [ ] 4. Expand 5% → 25% → 50% → 100% with p95 hold at each stage
- [ ] 5. Consider deterministic AND conditions only after single-leaf cohort passes

**Exit gate:** 100% semantic/compiled-rule parity for eligible cohort; Adaptive Static selects+executes Graph+Tier-1 for eligible; lower FM count + p50/p95 vs conditional-Graph baseline; no unsafe confirmation/finalization increase.

---

## Phase 4 — Verifier Loop condition handling (PR 7 reuse, PR 8 schema)

### 4A. Round-trip-safe reuse (PR 7)
- [ ] Replace narrow loop condition-state parser with shared assessor
- [ ] Populate `ConditionLeafDraft` only for losslessly representable forms
- [ ] Requiredness metadata so absent optional trigger fields skip pre-repair
- [ ] Record pre-repair specialist count separately from fields changed
- [ ] No identical no-op repair; no repair on final iteration (no subsequent verify)
- [ ] Ground low-confidence targets in verifier prompt (compact name/ID/room)
- [ ] Hard prompt budget (preserve user text, disputed fields, conditions, safety first)
- [ ] Reuse already-prepared request/envelope where available

### 4B. Full structured-condition parity (PR 8)
- [ ] Add optional structured condition rep to `ConditionLeafDraft` (versioned envelope field)
- [ ] Update: `DraftEnvelope` versioning/decoding, `DeterministicDraftPipeline`, `StructuralDraftBuilder`, `EnvelopeMerger`, `VerifierPromptBuilder`, repair specialists + field IDs, exact tree tests
- [ ] Do NOT mark numeric range / changes / complex right operands / mixed trees complete until 4B done

### Loop budget & escalation
- [ ] Make `VerifierLoopPolicy.escalation` operational
- [ ] Distinguish: model unavailable / verifier timeout / no-progress / repair exhaustion / iteration cap
- [ ] Run-level FM/time budget before launching legacy Graph
- [ ] Preflight suitability gate: structurally unsupported / precedence-ambiguous → Graph directly

- [ ] Tests: complete simple → 0 pre-repair + 1 verifier call; incomplete single → 1 repair then verify;
      multiple incomplete → 1 batched repair; disputed → 1 material repair then re-verify;
      final iteration no unverified repair; optional absent no pre-repair; prompt within budget;
      structured numeric/between/changes round-trip after 4B; escalation policies distinct;
      verifier timeout can't launch unlimited 2nd pipeline; prepared envelope avoids rebuild

**Exit gate:** simple complete conditions same pre-repair count as no-condition twins; no silent semantic loss across draft/merge/validation/compilation; loop→Graph escalation rate flat; conditional Verifier Loop p95 improves without reducing acceptance accuracy.

---

## Phase 5 — Consolidation & rollout completion (PR 9)

- [ ] Legacy confidence + adaptive policies behind independent rollback switches during rollout
- [ ] Compare Phase 0 baseline to every phase on same live corpus/environment
- [ ] Remove duplicate deterministic condition code once all consumers use shared assessor
- [ ] Update `Docs/AutomationParallelismStrategy.md` (current-state gap list is stale)
- [ ] Document final timeout/prompt/concurrency/eligibility values + justifying baseline artifact
- [ ] Enable conditional Tier-1 by default only after full release gates pass

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
