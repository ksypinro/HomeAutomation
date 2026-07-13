# Adaptive Portfolio Phase 8 Task Tracker

Reference: [implementation-plan.html](implementation-plan.html#phase-8)  
Phase: 8 — Add explicit residual batching and correct session lifecycle  
Created: 2026-07-13  
Status: Implemented and verified

## Implementation Summary

Implemented in this phase:

- Added `FoundationModelBatchItemID`, `FoundationModelBatchCompatibilityKey`, `FoundationModelBatchContext`, and TaskLocal batch telemetry propagation into `FoundationModelCallRecorder`.
- Hardened `BatchedConditionClauseResolver` so batch outputs echo and map by typed `itemID`, not position. Missing, duplicate, and unknown output IDs fall back per item.
- Added `BatchedActionCapabilityResolver` and `BatchedActionCapabilityRequest` as an explicit action-capability-only batch seam with item IDs and per-item fallback.
- Added `FoundationModelBatchCoalescer` with deterministic bounded-window decisions and zero-slack/safety/clarification bypass.
- Added `FoundationModelSessionFactory` and converted `FoundationModelSessionPool` into a compatibility facade that creates fresh sessions, discards released/failed sessions, and performs real `prewarm(promptPrefix:)` instrumentation instead of retaining stateful transcripts.
- Updated condition/trigger/segmentation worker sessions to discard failed pooled/factory sessions.
- Added `ResidualBatchingTests` covering item-ID mapping, per-item fallback, action capability batch fallback, no transcript retention, real prewarm metadata, and coalescing bypass.
- Updated Phase III session tests to assert the new Phase 8 lifecycle contract.

The optional fused front-end NLU work remains shadow-only by design; no active runtime route was switched to a fused NLU path in this phase.

## Goal

Reduce actual Foundation Model calls only where batching is explicitly safe, schema-compatible, and independently recoverable per item, while fixing session lifecycle semantics so stateful `LanguageModelSession` transcripts never cross unrelated requests.

Phase 8 is complete when residual batching preserves typed item identity, one bad batch item cannot poison siblings, prewarming uses real immutable prompt prefixes instead of merely constructing sessions, failed/overflowed sessions are discarded, and session reuse is limited to an intentional run-local scope such as the verifier loop.

## Current Repository Findings

- `BatchedConditionClauseResolver` already batches low-confidence condition clause residuals after deterministic τ-gating.
  - It falls back to deterministic per-item results when FM is unavailable or batch inference throws.
  - It currently maps returned batch outputs by array position (`fmOutput.items[index]`) rather than a typed item ID, which Phase 8 should correct.
- `BatchedConditionClauseFMOutput` / `BatchedConditionClauseItemOutput` exist for condition clause batch schema.
- `AutomationComponentFanOutRunner` already chooses batched condition resolution when a `BatchedConditionClauseResolver` is configured and there are at least two conditions.
- `AutomationActionResolver.resolveAll(...)` resolves action descriptions concurrently and preserves input order.
- `AutomationActionMiniPipeline` runs deterministic draft parsing and calls `CapabilityResolutionWorker` when field confidence is low.
- `CapabilityResolutionWorker` is the current FM-backed capability decision seam for action capability ambiguity.
- `FoundationModelSessionPool` currently pools `LanguageModelSession` instances by `SessionKind`.
  - This is risky for Phase 8 because Apple `LanguageModelSession` is stateful and carries transcript history.
  - Its `prewarm(kinds:)` currently constructs sessions and stores them in the pool; it does not call `LanguageModelSession.prewarm(promptPrefix:)`.
- `HomeCommandResolutionSupport` already has real prewarm hooks:
  - `prewarmSmartHomeSession(... promptPrefix:)`
  - `prewarmDefaultSession(promptPrefix:)`
  - both call `session.prewarm(promptPrefix:)`.
- `FoundationModelCallRecorder` already records session reuse (`FoundationModelSessionReuse`) and Phase 7 lease/scheduler telemetry. Phase 8 should extend this with prewarm label/version and batch size metadata where applicable.
- `OrchestrationComparisonRunner` and CLI already carry a `prewarmMode` label, but Phase 8 needs a concrete session/prewarm implementation behind the label.
- Existing tests cover Phase III call reduction/session pool behavior and condition batching, but not Phase 8 identity-mapped residual batching, real prewarm instrumentation, failed-session discard, or no-cross-run transcript assertions.

## Scope Boundaries

### Included

- Explicit residual batch adapters only for known-compatible work.
- Preserve and harden existing batched condition clause resolution.
- Add batched low-confidence automation action capability resolution.
- Optional shadow-only fused front-end NLU design, but active implementation should wait until prompt/schema parity passes.
- Bounded coalescing window for compatible residuals.
- Session lifecycle fix: no cross-request transcript pooling.
- Run-local verifier session reuse where intentionally scoped.
- Real prefix prewarm using `prewarm(promptPrefix:)`.
- Failed/overflowed session discard and lifecycle telemetry.
- Tests, docs, and type inventory updates.

### Deferred To Later Phases

- Learned portfolio routing (Phase 9).
- Production canary rollout switches (Phase 10), except lightweight configuration seams needed for Phase 8 tests.
- Arbitrary frontier-job batching.
- Remote/custom model provider continuous batching.
- Automatic capacity changes based on queue pressure.

## Existing Behavior To Preserve

- Existing callers of `AutomationActionResolver.resolveAll(...)` and `BatchedConditionClauseResolver.resolveAll(...)` should continue to compile.
- Condition batching must remain disabled unless a `BatchedConditionClauseResolver` is injected.
- Deterministic τ-gates remain first: high-confidence condition/action items should avoid FM calls.
- Output order must continue to match input order for public APIs.
- Safety/finalization gates must not be batched or bypassed.
- Missing batch metadata, incompatible schemas, overdue work, or FM unavailability must fall back to unbatched/deterministic behavior.

## Implementation Order

### P8.1 — Define Batch Compatibility And Typed Item Identity

Primary new file: `HomeAutomationCore/Sources/HomeAutomationCore/Telemetry/FoundationModelBatching.swift`

Primary modified files:

- `HomeAutomationCore/Sources/HomeAutomationAgents/Automation/ConditionClauseResolution/BatchedConditionClauseFMOutput.swift`
- `HomeAutomationCore/Sources/HomeAutomationAgents/Automation/ConditionClauseResolution/BatchedConditionClauseResolver.swift`
- `HomeAutomationCore/Sources/HomeAutomationCore/Telemetry/FoundationModelCallRecorder.swift`

Tasks:

- [x] Add `FoundationModelBatchCompatibilityKey` with:
  - run ID;
  - model/provider identifier;
  - immutable instruction digest;
  - response schema digest;
  - tool-set digest;
  - locale;
  - policy version;
  - privacy class;
  - workflow scope ID.
- [x] Add `FoundationModelBatchItemID` or use stable typed string IDs in every batch prompt/schema.
- [x] Add `FoundationModelBatchContext` TaskLocal or explicit recorder metadata with batch ID, item count, compatibility key digest, and coalescing delay.
- [x] Extend `FoundationModelCallRecorder.record(...)` telemetry with privacy-safe `fmBatchID`, `fmBatchSize`, and `fmBatchCompatibilityDigest` fields.
- [x] Ensure no raw prompt, device name, or user text enters compatibility telemetry.

Acceptance:

- [x] Batch item identity is explicit and stable.
- [x] Batch compatibility can be compared deterministically in tests.
- [x] Recorder telemetry exposes batch size/digest without sensitive text.

### P8.2 — Harden Existing Batched Condition Resolution

Primary modified files:

- `BatchedConditionClauseResolver.swift`
- `BatchedConditionClauseFMOutput.swift`
- `PhaseIIICallReductionTests.swift` or new `ResidualBatchingTests.swift`

Tasks:

- [x] Add `itemID` to `BatchedConditionClauseItemOutput`.
- [x] Update the batch prompt to require each output item to echo the typed input `itemID`.
- [x] Map FM outputs by `itemID`, never array index.
- [x] Treat missing/duplicate/unknown item IDs as per-item failure, not whole-batch failure.
- [x] Preserve deterministic fallback per failed item.
- [x] Keep public `resolveAll` output order identical to input order.
- [x] Add tests for reordered FM outputs, missing output, duplicate output, unknown item ID, and one bad item among good siblings.

Acceptance:

- [x] Batch output preserves item identity and input order.
- [x] One bad item does not poison siblings.
- [x] Existing deterministic condition batching tests still pass.

### P8.3 — Add Batched Low-Confidence Action Capability Resolution

Primary new file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Automation/BatchedActionCapabilityResolver.swift`

Primary modified files:

- `AutomationActionMiniPipeline.swift`
- `AutomationActionResolver.swift`
- `HomeAutomationCoordinator.swift`
- `DefaultAgentRegistryFactory.swift`

Tasks:

- [x] Identify action items whose deterministic mini-pipeline confidence is below the capability threshold.
- [x] Create a batch adapter for capability decisions only; do not batch full action resolution or safety validation.
- [x] Use one response schema with typed action item IDs.
- [x] Map batched capability outputs by typed item ID.
- [x] Fall back per item to existing `CapabilityResolutionWorker.resolve(...)` or deterministic unsupported/clarification.
- [x] Preserve action result order and subgraph/run attribution.
- [x] Expose the batched action capability resolver through coordinator-owned dependencies.

Acceptance:

- [x] Batching reduces actual capability FM calls for multi-action low-confidence cases.
- [x] One failed action-capability item falls back independently.
- [x] Resolved action output order and `actionID` telemetry remain stable.
- [x] Safety/finalization validation still runs per action.

### P8.4 — Add Bounded Coalescing Window

Primary new file: `HomeAutomationCore/Sources/HomeAutomationCore/Telemetry/FoundationModelBatchCoalescer.swift`

Primary modified files:

- `BatchedConditionClauseResolver.swift`
- `BatchedActionCapabilityResolver.swift`
- Phase 7 admission context/critical-path metadata integration if needed.

Tasks:

- [x] Add a small configurable coalescing window for compatible residuals.
- [x] Coalesce only work already imminent within the same run/workflow scope.
- [x] Do not wait when critical-path slack is zero/negative, the job is overdue, clarification is pending, or a safety/finalization job is involved.
- [x] Record coalescing delay in telemetry.
- [x] Keep deterministic test clocks or injectable sleep strategy.

Acceptance:

- [x] Compatible near-simultaneous residuals batch together.
- [x] Zero-slack or overdue work bypasses the window.
- [x] Coalescing delay is bounded and observable.

### P8.5 — Replace Cross-Request Session Pooling With Session Factory

Primary new file: `HomeAutomationCore/Sources/HomeAutomationCore/Telemetry/FoundationModelSessionFactory.swift`

Primary modified files:

- `FoundationModelSessionPool.swift`
- all worker sessions currently taking `FoundationModelSessionPool?`
- `HomeAutomationCoordinator.swift`
- `PhaseIIICallReductionTests.swift`

Tasks:

- [x] Introduce a `FoundationModelSessionFactory` that creates fresh instruction-scoped sessions by default.
- [x] Replace general cross-request `LanguageModelSession` pooling with immutable prefix prewarm/cache metadata, not transcript reuse.
- [x] Keep only explicitly run-local reusable sessions where safe (for example verifier loop session reuse inside one loop run).
- [x] Add run ID/session owner assertions to prevent transcript reuse across run IDs.
- [x] Update `FoundationModelSessionPool` tests or retire/rename the pool if the type becomes a prewarm registry.
- [x] Preserve current worker initialization API where practical by adapting pool/factory behind a protocol.

Acceptance:

- [x] No `LanguageModelSession` transcript crosses unrelated run IDs.
- [x] Fresh session is used for unrelated requests even with same instructions.
- [x] Verifier loop can intentionally reuse a run-local session only inside one loop run.

### P8.6 — Implement Real Prefix Prewarming

Primary modified/new files:

- `FoundationModelSessionFactory.swift`
- `HomeCommandResolutionSupport.swift`
- `HomeAutomationCoordinator.swift`
- `OrchestrationComparisonRunner.swift`
- CLI prewarm mode handling

Tasks:

- [x] Call `LanguageModelSession.prewarm(promptPrefix:)` with the actual immutable prompt prefix.
- [x] Track prefix version/digest, prewarm hit/miss, prewarm lead time, and session freshness.
- [x] Distinguish `created`, `fresh`, `prewarmed`, and `withinRunReuse` in telemetry.
- [x] Ensure session construction alone is not labeled as prewarm.
- [x] Add tests with a mock/fake prewarm adapter so real prewarm calls are observable without requiring hardware.

Acceptance:

- [x] Prewarm instrumentation proves `prewarm(promptPrefix:)` was invoked.
- [x] Prewarm labels are accurate and not inferred from pool fill.
- [x] Evaluation reports carry prewarm mode/version labels.

### P8.7 — Discard Failed Or Overflowed Sessions

Primary modified files:

- `FoundationModelSessionFactory.swift`
- worker sessions using Foundation Model sessions
- `FoundationModelCallRecorder.swift`

Tasks:

- [x] Add session lifecycle accounting with `defer`.
- [x] Mark sessions failed/overflowed when generation throws, transcript grows beyond configured bounds, or schema decoding fails after an FM response.
- [x] Never return failed/overflowed sessions to any reusable scope.
- [x] Record failure/discard reason in telemetry.
- [x] Add tests proving failed sessions are discarded and good run-local sessions can still be reused when allowed.

Acceptance:

- [x] Failed sessions are not reused.
- [x] Overflow/session-discard metrics are visible.
- [x] Existing ledger failure counts remain correct.

### P8.8 — Optional Shadow-Only Unified Front-End NLU

Primary optional new file: `HomeAutomationCore/Sources/HomeAutomationAgents/NLU/UnifiedFrontEndNLUWorkerSession.swift`

Tasks:

- [x] Design a fused NLU prompt/schema for operation, semantic parse, slot extraction, and risk only in shadow mode.
- [x] Run existing individual workers as source of truth.
- [x] Emit a prompt/schema parity report comparing fused shadow output to current workers.
- [x] Do not route active execution through fused NLU until parity is accepted.

Acceptance:

- [x] Shadow report is deterministic and privacy-bounded.
- [x] Active runtime remains unchanged unless a later phase explicitly promotes it.

### P8.9 — Tests

Suggested new test file:

- `HomeAutomationCore/Tests/HomeAutomationOrchestratorTests/ResidualBatchingTests.swift`

Suggested extended test files:

- `PhaseIIICallReductionTests.swift`
- `AutomationTier1Tests.swift`
- `CapabilityResolutionWorkerTests.swift`
- `FoundationModelUsageLedgerTests.swift`
- `RuntimeDependencyWiringTests.swift`
- `CoordinatorRefactorTests.swift`

Tasks:

- [x] Test condition batch output maps by item ID, not position.
- [x] Test missing/duplicate/unknown batch item IDs fall back per item.
- [x] Test one bad batch item does not poison siblings.
- [x] Test batched action capability resolution preserves input/action ID order.
- [x] Test batched action capability per-item fallback.
- [x] Test no cross-run `LanguageModelSession` transcript reuse.
- [x] Test verifier loop run-local reuse, if implemented.
- [x] Test real prewarm invocation through fake adapter/factory.
- [x] Test failed/overflowed session discard.
- [x] Test batching reduces actual FM calls without changing deterministic accepted items.
- [x] Test coalescing window bounds and zero-slack bypass.

### P8.10 — Documentation And Inventory

Tasks:

- [x] Update `Docs/CoordinatorTypeInventory.md` for every new source declaration.
- [x] Update `Docs/AgentOrchestrationGuide/implementation-plan.html` with Phase 8 implementation status after verification.
- [x] Update this tracker as Phase 8 slices land.
- [x] Document batch compatibility rules, item-ID mapping, session lifecycle policy, prewarm labels, and known hardware benchmark requirements.
- [x] Record any full-suite blockers separately from Phase 8-focused verification.

## Verification Commands

Run focused Phase 8 tests first:

```bash
swift test --filter ResidualBatchingTests
swift test --filter PhaseIIICallReductionTests
swift test --filter CapabilityResolutionWorkerTests
swift test --filter AutomationTier1Tests
```

Then run targeted telemetry/session regressions:

```bash
swift test --filter FoundationModelUsageLedgerTests
swift test --filter RuntimeDependencyWiringTests
swift test --filter CoordinatorRefactorTests.coordinatorTypeInventoryListsEverySourceDeclaration
```

Then run broader graph/automation regressions:

```bash
swift test --filter AutomationRepairSpecialistTests
swift test --filter Phase7FanOutTests
swift test --filter OrchestratorInfrastructureTests
```

Then run broader package tests:

```bash
swift test
```

Known historical full-suite blocker from earlier phases:

- `AutomationActionResolverTests.directGraphActionResolutionSeedsRoutingState` has previously failed reproducibly with `result.isResolved == false` and `Safety validation blocked: mandatory gate failed`. Re-check before Phase 8 implementation; track separately unless Phase 8 changes that path.

## Definition Of Done

- [x] Batch compatibility is explicit and privacy-safe.
- [x] Batched condition outputs map by typed item ID.
- [x] Batched action capability resolution exists for low-confidence action residuals.
- [x] Public output ordering is stable.
- [x] One bad batch item falls back independently.
- [x] Coalescing window is bounded and bypassed for zero-slack/overdue/safety work.
- [x] Cross-request `LanguageModelSession` pooling is removed or made impossible.
- [x] Any session reuse is run-local and explicitly asserted.
- [x] Real `prewarm(promptPrefix:)` calls are instrumented and tested with fakes.
- [x] Failed/overflowed sessions are discarded.
- [x] Focused and targeted regression tests pass.
- [x] Documentation and type inventory are updated.

## Risks And Watch Points

- Accidentally batching incompatible schemas or privacy classes.
- Mapping batch results by position and corrupting item identity.
- A malformed item causing whole-batch failure instead of per-item fallback.
- Reusing a stateful transcript across unrelated requests.
- Calling session construction “prewarm” without invoking `prewarm(promptPrefix:)`.
- Letting prefix affinity or batching delay safety/finalization work.
- Hiding queue/coalescing delay inside model service time.
- Breaking existing deterministic τ-gates while adding action capability batching.
