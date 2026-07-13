# Gap-Closure Implementation Plan — Redesign & Parallelism Docs Audit

> **Status**: Ready for implementation
> **Date**: 2026-07-11
> **Audited docs**: [AutomationCreationRedesign.md](AutomationCreationRedesign.md),
> [AutomationParallelismStrategy.md](AutomationParallelismStrategy.md)
> **Existing trackers**: [task.md](task.md) (verifier loop, Phases A–H),
> [ParallelismTask.md](ParallelismTask.md) (parallelism, Phases I–IV)
> **This plan's tracker**: [GapClosureTask.md](GapClosureTask.md)

## Audit result

Everything in `AutomationParallelismStrategy.md` (Phases I–IV) is implemented and
verified in code — SJF gate lanes, parallel loop repairs, fan-out CPU cap, two-wave
scheduling, clarification short-circuit, batched conditions, session pools with
pre-warming, speculative segmentation, and speculative assembly/compilation.

`AutomationCreationRedesign.md` is implemented except for three gaps, all
concentrated on the loop path and the user-facing confirmation:

| # | Gap | Where verified |
|---|---|---|
| G-1 | **H6 — automation repair specialists unimplemented.** `RepairSpecialistRegistry` returns `nil` for `.trigger`, `.conditionClause`, `.segmentation`, and `.holisticDraft` repair steps, so verifier disputes on those fields can never be repaired — the loop escalates to the legacy graph instead. | `RepairSpecialistRegistry.swift:121` |
| G-2 | **Device triggers unsupported on the loop path (Case D).** `TriggerDraft` retains neither the raw trigger fragment nor a structured device-trigger condition, so `StructuralDraftBuilder.automationCreationPlan(from:)` cannot compile "when the front door opens…" — the loop exits `.unsupported` and only the graph path serves these commands. | task.md H6 note; H2 bridge |
| G-3 | **A-4 half-done — the confirmation card does not render the parenthesized condition interpretation.** The verifier prompt states the chosen boolean reading (A-2/A-5 landed), but `HomeCommandResolution.displaySummary` renders only "Automation drafted with N action(s)". The redesign requires the reading to be user-visible precisely because the parser silently commits to AND-over-OR precedence at 0.90 confidence. | `HomeResolutionModels.swift:67-76`; `VerifierPromptBuilder.treeInterpretation` |

One adjacent item rides along: the shared-verb mis-split limitation
("turn on the AC and the fan" → `["Turn on the AC", "The fan"]`) is *detected* by the
verifier's segmentation-coverage check but cannot be *repaired* until G-1 wires the
`.segmentation` specialist.

Uncommitted work already in the working tree (precedes this plan): Tier 1
mini-pipeline candidate-hydration bugfix + regression tests, orchestrator-mode UI
picker, `makeRAGEnabledCoordinator` factory.

---

## Phase 1 — Envelope: structured triggers (unblocks G-2, prerequisite for G-1 trigger repair)

**Files**: `Sources/HomeAutomationAgents/Loop/DraftEnvelope.swift`,
`DeterministicDraftPipeline.swift`, `StructuralDraftBuilder.swift`

1. Extend `TriggerDraft` with:
   - `rawText: String?` — the trigger fragment as segmented from the user text
     (needed by any repair specialist to re-parse).
   - a structured device-trigger representation (device id/candidates + capability +
     attribute + operator + value — mirror `ConditionLeafDraft`'s shape) alongside the
     existing schedule fields, with a `kind` discriminator (`schedule` | `device`).
2. `DeterministicDraftPipeline.makeAutomationEnvelope` populates both: schedule parses
   as today; device-trigger phrasing ("when the front door opens") fills the structured
   condition via the existing deterministic condition parser, with per-field confidence.
3. `StructuralDraftBuilder.automationCreationPlan(from:)` compiles device triggers into
   `HomeAutomationRuleDraft.trigger = .device(...)` (the graph path already proves the
   rule-model shape; this is a mapping, not new compiler work).
4. Keep `Codable` compatibility: new fields optional/defaulted.

**Checkpoint**: `swift build && swift test --filter "DraftEnvelope|DeterministicDraftPipeline|StructuralDraftBuilder"`.
New tests: device-trigger envelope population; device-trigger plan compilation;
schedule triggers unchanged.

## Phase 2 — Wire the automation repair specialists (G-1, closes H6)

**Files**: `Sources/HomeAutomationOrchestrator/Loop/RepairSpecialistRegistry.swift`,
`Sources/HomeAutomationAgents/Loop/EnvelopeMerger.swift` (+ `RepairResult` cases)

1. `.trigger` → `AutomationTriggerResolutionWorkerSession.resolve` on
   `TriggerDraft.rawText` (fall back to re-segmenting `envelope.userText` when absent);
   merge the resolved trigger back via a new `RepairResult.trigger` case.
2. `.conditionClause` → `AutomationConditionClauseResolutionWorkerSession` (single
   clause) or `BatchedConditionClauseResolver` (≥2 disputed leaves — reuse Phase III
   batching); merge per-leaf.
3. `.segmentation` → `AutomationComponentSegmentationWorkerSession.segment` on the full
   `userText`; on a differing plan, rebuild the affected envelope sections (reuse the
   Phase IV `diffPlans` logic) — this makes the shared-verb mis-split repairable.
4. `.holisticDraft` remains explicitly unsupported (out of scope; document why at the
   call site).
5. All specialists respect the FM gate (`interactive` priority) and the loop's
   per-iteration repair cap — no new budgets.

**Checkpoint**: `swift test --filter "RepairSpecialistRegistry|VerifierLoop"`.
New tests (injected-closure seams, no FM): trigger dispute → repaired trigger merged;
condition dispute → repaired leaf merged; segmentation dispute on a shared-verb
mis-split → corrected action list; unsupported kinds still return nil; loop
end-to-end with a fake verifier disputing a trigger reaches `.accepted` instead of
escalating.

## Phase 3 — Loop-path device-trigger end-to-end (completes G-2 / Case D)

**Files**: `Sources/HomeAutomationOrchestrator/Loop/LoopResultBridge.swift`, tests

1. Remove the `.unsupported("device triggers…")` early-exit in the H2 bridge now that
   Phase 1 compiles them.
2. End-to-end test: "When the front door opens after 10 PM, turn on the porch light"
   under `orchestrationMode: .verifierLoop` with FM `{ false }` →
   deterministic envelope → bridge → `automationDrafted` with a device trigger,
   asserting parity with the graph arm's output for the same command.
3. Add the command to the `OrchestrationComparisonRunner` corpus so Case D parity is
   gated in CI (the three-arm harness exists; the corpus just never exercised it).

**Checkpoint**: `swift test` + `--compare-orchestration` run: verifierLoop arm no
longer reports `unsupported` for device-trigger cases; exit gates hold.

## Phase 4 — Render the condition interpretation in the confirmation (G-3, completes A-4)

**Files**: `Sources/HomeAutomationCore/HomeAutomation/HomeResolutionModels.swift`
(or a dedicated formatter next to `HomeAutomationCreationPlan`), shared tree renderer

1. Extract the verifier's `treeInterpretation`/`describeTree` rendering into a shared
   helper on the core rule model (`HomeAutomationCondition.parenthesizedDescription(deviceNames:)`)
   so both the verifier prompt and the summary use one renderer.
2. `displaySummary` for `.automationDrafted` / `.automationRequiresConfirmation`
   appends the reading when a condition exists, e.g.
   `"… if (Light is on AND Fan is off) OR TV is off"`. Always rendered — not only when
   ambiguous — per A-4's rationale (the reading is never silently committed).
3. UI: no change needed — the app already displays `displaySummary`.

**Checkpoint**: unit tests on the renderer (nested or/and, not, changes); snapshot
assertions in `AutomationCreationFlowTests` that the summary contains the
parenthesized reading for the nested-tree canonical case.

## Phase 5 — Bookkeeping

1. Commit the pending working-tree fixes (Tier 1 hydration fix + regression tests, UI
   picker, RAG coordinator factory) as their own commit before this plan's work.
2. Tick H6 in [task.md](task.md) when Phase 2 lands; keep [GapClosureTask.md](GapClosureTask.md)
   as the tracker for this plan.
3. `CoordinatorTypeInventory.md` for any new types (inventory metatest enforces this).

---

## Explicitly out of scope

- `.holisticDraft` repair (no specialist exists by design — escalation covers it).
- Raising `FoundationModelGate.maxConcurrent`, further subgraph parallelism, cross-run
  batching (all "What Not To Do", AutomationParallelismStrategy §7).
- Any change to graph-mode behavior — it remains the reference arm.

## Exit criteria

- Zero `RepairSpecialistRegistry` dispute kinds that silently return `nil` except
  `.holisticDraft` (documented).
- Case D (device trigger) passes on all three arms in `--compare-orchestration`.
- Confirmation summary shows the parenthesized condition reading for every drafted
  automation with a condition tree.
- All existing gates hold: accuracy ≥ baseline, clarification delta ≤ 3 pts,
  safety-gate parity, `swift test` green.
