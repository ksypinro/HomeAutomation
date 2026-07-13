# Remaining Implementation Task Tracker

Source audit: `implementation-plan.html` plus `phase2Task.md` and `phase5Task.md`.

## Scope

This tracker separates remaining code work from external release evidence. Code work can be completed in this repository; hardware/live-model baselines require supported Apple Foundation Models hardware and should be archived as release evidence rather than fabricated locally.

## Code-side remaining work

- [x] Add a focused remaining-requirements tracker.

- [x] Complete the Phase 5 structural extraction in behavior-preserving slices.
  - [x] Move common run setup in `HomeCommandOrchestrator.resolveStream` behind an `OrchestrationRunContext` construction helper.
  - [x] Add run-context helpers for publishing input/outcome events and selected per-run scoped state.
  - [x] Add typed arm-executor outputs for graph, verifier-loop accepted/finalized, non-actionable, and escalation exits.
  - [x] Ensure direct-command, automation-creation, and unsupported graph paths are invokable through graph-arm executor methods.
  - [x] Ensure verifier-loop clarification/unsupported/non-actionable exits and escalations return typed outputs to the top-level flow.
  - [x] Preserve one run ID, one event bus, one ledger, one metrics record, and one terminal outcome event per request.

- [x] Add bounded automation action strategy state.
  - [x] Introduce `AutomationActionResolutionStrategy`.
  - [x] Store selected strategy in root scoped context based on the executing portfolio arm.
  - [x] Let automation action resolution expose the typed context value for graph/mini-pipeline strategy consumers.
  - [x] Preserve explicit `useMiniPipeline` behavior.

- [ ] Add loop escalation evidence.
  - [ ] Carry prepared artifacts and escalation chain through graph/finalization paths.
  - [ ] Add deterministic tests that escalation keeps one ledger/run and records `[verifierLoop, graph]` or `[verifierLoop, finalization]`.

- [ ] Add missing adaptive integration tests.
  - [ ] Active static direct-command parity with explicit graph/verifier modes.
  - [ ] Device trigger/complex condition/memory/OOD/high-risk graph fallback.
    - [x] High-risk active adaptive graph fallback covered.
  - [ ] Low-confidence/OOD root-routing or fail-closed behavior.
  - [ ] Finalization receipt invariants for active adaptive direct command and automation creation.
    - [x] Active adaptive direct-command finalization receipt covered.

## External release evidence

- [ ] Archive supported-hardware Phase 2 live baseline.
- [ ] Archive real on-device Phase 7 capacity benchmark for TTFT, p50/p95, queue wait, cancellation, accuracy, and safety.
- [ ] Run Phase 10 release gates with real hardware gate evidence, rollback drill evidence, and router-regret report from a production candidate artifact.

## Current implementation notes

- Phases 6–10 have deterministic/local code paths implemented and tested in focused suites.
- Phase 5 active static routing exists. This cleanup pass moved run ID/event bus/ledger construction behind `OrchestrationRunContext.make`, centralized input/outcome event publication and terminal completion through run-context helpers, added typed graph/verifier arm-execution outputs, and stored the per-run automation action strategy in scoped context.
- Hardware/live evidence remains external by design.
