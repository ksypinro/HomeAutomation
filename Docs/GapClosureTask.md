# Gap Closure — Implementation Tracker

Reference: [GapClosureImplementationPlan.md](GapClosureImplementationPlan.md)
Audit basis: [AutomationCreationRedesign.md](AutomationCreationRedesign.md) + [AutomationParallelismStrategy.md](AutomationParallelismStrategy.md)

> Named `GapClosureTask.md` because `Docs/task.md` already exists and macOS's
> case-insensitive filesystem cannot hold a separate `Task.md`.

## Audit summary (2026-07-11)

- **AutomationParallelismStrategy.md Phases I–IV: fully implemented** ✅ (verified in code; see ParallelismTask.md)
- **AutomationCreationRedesign.md: fully implemented for the audited G-1/G-2/G-3 gap set** ✅

---

## Phase 1 — Envelope: structured triggers ✅

- [x] 1.1: `TriggerDraft.rawText` + a structured device-trigger condition, Codable-compatible (new optional fields default to `nil`). **Deviation:** instead of mirroring `ConditionLeafDraft`'s discrete field shape, the structured condition is stored as a resolved `HomeAutomationCondition` (`deviceCondition`) — directly compilable, repairable, and consistent with the graph model. The `schedule | device` discriminator already existed as `TriggerDraft.type`.
- [x] 1.2: `DeterministicDraftPipeline.makeAutomationEnvelope` populates the device condition by reusing the condition-clause worker (FM off), the same robust device/capability/attribute matching the graph arm uses. Also drops the redundant trigger-derived condition leaf when there is no explicit `if` clause.
- [x] 1.3: `StructuralDraftBuilder.automationTrigger` compiles device triggers to `HomeAutomationRuleDraft.trigger = .device(...)`.
- [x] 1.4: Tests (device-trigger envelope population, device-trigger compilation, schedule regression + `rawText`). No new public types → no inventory update needed.

## Phase 2 — Automation repair specialists (closes task.md H6) ✅

- [x] 2.1: `.trigger` specialist → `AutomationTriggerResolutionWorkerSession` (+ device-condition resolution) → `RepairResult.trigger` merge (merge updated to carry `rawText`/`deviceCondition`).
- [x] 2.2: `.conditionClause` specialist → single clause worker, or `BatchedConditionClauseResolver` for ≥2 disputed leaves via the new `RepairResult.conditionClauses` merge.
- [x] 2.3: `.segmentation` specialist → `AutomationComponentSegmentationWorkerSession`; shared-verb mis-split becomes repairable (reuses the existing `mergeSegmentation`).
- [x] 2.4: `.holisticDraft` documented as intentionally unsupported (returns `nil`, comment at the call site).
- [x] 2.5: Tests (`AutomationRepairSpecialists`: trigger/condition/batched/segmentation merges, unsupported-kind + missing-worker nil, end-to-end loop accepts instead of escalating). No new public types → no inventory update needed.
- [x] 2.6: Ticked H6 in [task.md](task.md).

## Phase 3 — Loop-path device triggers end-to-end (Case D) ✅

- [x] 3.1: No explicit early-exit existed in `LoopResultBridge`; the `.unsupported` path was compiler-derived. Phase 1's device-trigger compilation removes it; the now-accurate comment was updated.
- [x] 3.2: End-to-end test (`deviceTriggerDraftsUnderVerifierLoopWithGraphParity`): device-trigger command drafts under `.verifierLoop` with graph-arm parity (both compile a rule resolving the same sensor).
- [x] 3.3: Added `trigger-resolution.device-contact-open` to the corpus (`EvaluationCorpus.defaultCases`).

## Phase 4 — Confirmation renders condition interpretation (completes A-4) ✅

- [x] 4.1: Shared `HomeAutomationCondition.parenthesizedDescription(deviceNames:)` renderer on the core rule model. **Deviation:** the verifier prompt was left rendering `ConditionTreeDraft` over raw leaf text — a different (pre-resolution) representation — so it was not switched to this renderer; forcing a single renderer across the two models would be churn that risks changing verifier snapshot output for no functional gain.
- [x] 4.2: `displaySummary` appends `" if <reading>"` for `.automationDrafted` / `.automationRequiresConfirmation` whenever a condition exists.
- [x] 4.3: Renderer unit tests (`ConditionReadingRenderer`, 5) + summary assertions in `AutomationCreationFlowTests`.

## Phase 5 — Bookkeeping

- [x] 5.1: The pending fixes (Tier-1 mini-pipeline bugfix + `AutomationTier1Tests`, UI orchestrator picker in `HomeAutomationView`/`ViewModel`, `HomeCommandOrchestrator`) were consolidated and later merged with the gap-closure work in PR #22 (`80989c8`).
- [x] 5.2: No new public/coordinator types were added (only fields, an enum case, extension methods, and init params), so `CoordinatorTypeInventory.md` needs no entries; the inventory metatest stays green.

---

## Exit criteria

- [x] No silently-nil dispute kinds in `RepairSpecialistRegistry` except documented `.holisticDraft`.
- [x] Case D (`trigger-resolution.device-contact-open`) drafts on **all three arms** — graph, graphWithTier1, and verifierLoop. The loop previously reported `unsupported`; the Tier-1 arm previously failed every automation case until its mini-pipeline fix was consolidated into this worktree (Phase 5.1). Verified by running the full corpus across all three arms.
- [x] Parenthesized condition reading visible in every drafted-automation summary with a condition.
- [x] `swift test` green (all targets, 225+ tests). Accuracy/clarification/safety deltas are gated by the `--compare-orchestration` CI run.
