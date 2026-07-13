# Adaptive Portfolio Phase 1 Task Tracker

Reference: [implementation-plan.html](implementation-plan.html#phase-1)
Phase: 1 — Build one common finalizer
Started: 2026-07-13
Implementation completed: 2026-07-13

## Goal

Make safety and finalization structural before adaptive routing can choose a faster arm. Every actionable direct-command or automation result must pass the same mandatory finalizer gates and produce a finalization receipt.

## Current Status

- [x] Phase 0 source-of-truth reconciliation complete enough to start Phase 1.
- [x] Graph-backed automation metrics now include a typed `ResolutionFinalizationReceipt`.
- [x] Verifier-loop accepted direct-command and automation outputs now run through `ResolutionFinalizer`.
- [x] Finalization graph fragments are defined and validate after seeding.
- [x] `FinalizationSeedBuilder` seeds direct-command and automation proposals from loop envelopes.
- [x] Loop accepted outputs are routed through shared finalizer graphs before an actionable result is emitted.
- [x] Direct-command fallback graph outputs are re-finalized through the direct-command finalizer before emission.
- [x] Verifier accepted verdicts are normalized so disputes, clarification, and understated risk cannot bypass repair/finalization.

## Task Breakdown

### 1. Receipt Substrate

- [x] Add `Finalization/FinalizationReceipt.swift`.
- [x] Define `FinalizationReceiptStatus`.
- [x] Define `FinalizationGateRecord`.
- [x] Define `ResolutionFinalizationReceipt`.
- [x] Add receipt field to `OrchestratorSafetyMetrics`.
- [x] Synthesize automation graph receipts from actual `GraphRunMetrics.nodeStatuses`.
- [x] Add tests proving graph automation has a completed receipt.
- [x] Keep a regression test proving verifier-unavailable escalation remains receipt-less/non-actionable.

### 2. Finalization Graph Fragments

- [x] Add `Finalization/FinalizationGraphFactory.swift`.
- [x] Extract direct-command finalizer fragment:
  `safetyValidation -> parameterValidation -> confirmationPolicy -> executionPlanning -> mockExecution`.
- [x] Extract automation finalizer fragment:
  `automationValidation -> smartThingsCompilation -> smartThingsRuleCreation -> automationResultAssembly`.
- [x] Keep safety gates, confirmation interrupts, and external mutation approval interrupts non-prunable.
- [x] Add graph validation tests for each finalizer fragment.
- [x] Add open-circuit/fail-closed coverage for mandatory finalizer gates through existing scheduler fail-closed tests and receipt hardening tests.

### 3. Finalization Seed Builder

- [x] Add `Finalization/FinalizationSeedBuilder.swift`.
- [x] Seed direct-command proposals from loop envelopes into `ResolutionContextStore`.
- [x] Seed automation proposals from loop envelopes into typed context artifacts.
- [x] Hydrate candidates from the device registry before finalization.
- [x] Preserve selected IDs, aggregation, risk, confidence, creation options, resolved actions, operand records, and rule drafts.
- [x] Add tests for direct-command proposal seeding.
- [x] Add tests for automation proposal seeding.
- [x] Add stale/missing seed fail-closed tests for unsupported operations.

### 4. Resolution Finalizer

- [x] Add `Finalization/ResolutionFinalizer.swift`.
- [x] Run finalizer fragments through `GraphScheduler`.
- [x] Reuse existing policy, circuit breakers, event bus, interrupts, graph validation, and telemetry.
- [x] Return a final `HomeAutomationResolverResult` plus `ResolutionFinalizationReceipt`.
- [x] Log `orchestration.finalizer.completed`.
- [x] Add accepted-loop tests proving receipts contain required gates, observed gate statuses, graph ID, and policy version.
- [x] Add explicit failed-gate and missing-gate receipt tests.

### 5. Loop Integration

- [x] Change loop acceptance to produce a proposal that is finalized before a mutation-capable terminal result is emitted.
- [x] Keep `LoopResultBridge` out of accepted-result runtime emission; it remains only a compatibility/seed-style mapping helper for non-actionable bridge tests and escalations.
- [x] Route accepted loop direct-command proposals through `ResolutionFinalizer`.
- [x] Route accepted loop automation proposals through `ResolutionFinalizer`.
- [x] Preserve graph escalation for `.holisticDraft`, repair latch, no progress, iteration cap, and verifier unavailable.
- [x] Add deterministic tests proving accepted direct-command and automation loop results have completed receipts.
- [x] Add tests proving SmartThings creator spy is never called before validation and approval.

### 6. Verifier Verdict Invariants

- [x] Normalize accepted verifier verdicts.
- [x] Require accepted verdicts to have no disputes.
- [x] Require accepted verdicts to have no clarification request.
- [x] Convert understated risk into a typed risk dispute before finalization.
- [x] Add direct high-risk/memory-derived sensitive-target confirmation coverage.
- [x] Add invalid parameter/range fail-closed coverage through parameter-validation and receipt hardening tests.
- [x] Add memory-derived sensitive-target confirmation parity tests.

### 7. Metrics And Documentation

- [x] Update `implementation-plan.html` with Phase 1 receipt-substrate status.
- [x] Update this tracker as each Phase 1 slice lands.
- [x] Update architecture docs after `ResolutionFinalizer` is active.
- [x] Add finalizer receipt fields to current Phase 1 metrics/source-of-truth docs.

## Verification Commands

Current passing checks:

```bash
swift test --filter HomeAutomationOrchestratorTests.OrchestratorInfrastructureTests
swift test --filter HomeAutomationOrchestratorTests.FinalizationGraphFactoryTests
swift test --filter HomeAutomationOrchestratorTests.AutomationCreationFlowTests
swift test --filter HomeAutomationOrchestratorTests.RuntimeDependencyWiringTests
swift test --filter HomeAutomationOrchestratorTests.Phase3GraphRuntimeTests
swift test --filter HomeAutomationOrchestratorTests.VerifierLoopTests
```

Expected current result:

- `OrchestratorInfrastructureTests`: 30/30 passing.
- `FinalizationGraphFactoryTests`: 8/8 passing.
- `AutomationCreationFlowTests`: 30/30 passing.
- `RuntimeDependencyWiringTests`: 8/8 passing.
- `Phase3GraphRuntimeTests`: 17/17 passing.
- `VerifierLoopTests`: 17/17 passing.

## Phase 1 Exit Criteria

- [x] Graph-backed direct-command actionable results have completed finalization receipts.
- [x] Graph-backed automation actionable results have completed finalization receipts.
- [x] Verifier-loop accepted direct-command results are finalized through the shared finalizer.
- [x] Verifier-loop accepted automation results are finalized through the shared finalizer.
- [x] No mutation-capable result can be emitted from accepted loop/fallback paths without a completed receipt.
- [x] Confirmation and mutation gates remain mandatory and ordered.
- [x] Open circuit, invalid seed, failed validation, and missing/failed receipt gates fail closed or report incomplete/failed receipts.
- [x] Phase 0/baseline comparison is rerun and records receipt coverage for every arm.

## Next Recommended Task

Start Phase 2: record truthful Foundation Model telemetry and latency attribution.
