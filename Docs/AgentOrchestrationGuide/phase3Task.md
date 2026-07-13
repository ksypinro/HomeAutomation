# Adaptive Portfolio Phase 3 Task Tracker

Reference: [implementation-plan.html](implementation-plan.html#phase-3)  
Phase: 3 — Prepare one reusable request and feature snapshot  
Created: 2026-07-13  
Status: Implemented — focused tests green on 2026-07-13

## Goal

Create a deterministic preparation layer that computes request evidence once and carries it forward for later routing, execution, graph escalation, evaluation, and rollout work.

Phase 3 is complete when a `PreparedOrchestrationRequest` can be built without any Foundation Model call, external mutation, prompt/session creation, or model-blocking retrieval, and when its `PortfolioFeatureSnapshot` is stable, versioned, privacy-safe, serializable, and freshness-aware.

## Current Repository Findings

- Phase 2 telemetry is in place, including ledger-backed model-call accounting and the first adaptive metrics container at `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/PortfolioMetrics.swift`.
- The Phase 3 files named by the implementation plan now exist:
  - `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/PreparedOrchestrationRequest.swift`
  - `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/PortfolioFeatureSnapshot.swift`
  - `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/OrchestrationFeatureExtractor.swift`
- `HomeCommandOrchestrator` now prepares a `PreparedOrchestrationRequest` before root routing, stores it in root scoped context via `AdaptiveContextKeys.preparedRequest`, and leaves existing routing behavior unchanged.
- Deterministic parsing and draft paths already exist and should be reused instead of recreated:
  - `HomeAutomationAgents/Fallback/Rule/AgentTextParser.swift`
  - `HomeAutomationAgents/Loop/DeterministicDraftPipeline.swift`
  - `HomeAutomationAgents/Automation/Draft/AutomationPatternParser.swift`
- `DeviceRegistryProtocol` exposes deterministic `allDevices()` and `retrieveCandidates(text:hints:limit:)` seams. Phase 3 needs a stable registry/index snapshot and version/fingerprint on top of these APIs.
- `ResolutionContextStore` already carries memory hints and resolution state. Phase 3 should package the deterministic state for reuse instead of forcing loop or graph escalation to parse/search again.
- Many existing workers create `LanguageModelSession` and call `FoundationModelCallRecorder.record`. The Phase 3 extractor must not call those workers or any code path that creates a session, prompt, model-blocking retrieval, or ledger event.

## Scope Boundaries

### Included

- A reusable prepared-request contract.
- A versioned feature snapshot contract.
- Deterministic extraction of operation, language/OOD, candidate, memory, risk, template, availability, gate-depth, and warm-state signals.
- A stable device-registry/index freshness model.
- Reusable deterministic artifacts for later loop and graph escalation.
- Schema/provenance/missing-value tracking.
- Privacy-safe serialization and contract tests.

### Deferred To Later Phases

- Hard eligibility and static portfolio routing (Phase 4).
- Changing which arm executes a request (Phase 5).
- Refactoring graph/loop arm executors (Phase 5).
- Dependency-minimal graph compilation (Phase 6).
- Frontier scheduling or Foundation Model admission changes (Phase 7).
- Learned routing, model training, active exploration, and rollout decisions (Phases 9–10).

Phase 3 may expose fields needed by those phases, but it must not make routing decisions or alter user-visible orchestration behavior.

## Implementation Order

### P3.1 — Define The Feature Snapshot Contract

Primary file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/PortfolioFeatureSnapshot.swift`

- [x] Define `PortfolioFeatureSnapshot` as `Sendable`, `Codable`, `Equatable`, and `Hashable`.
- [x] Add a fixed `featureSchemaVersion` and document when it must change.
- [x] Represent all features with bounded, privacy-safe values. Do not store raw command text, prompts, model output, device display names, room names, or high-cardinality strings in the feature vector.
- [x] Add missing-value flags so unknown, not-applicable, unavailable, and extraction-failed states are distinguishable from real zeroes.
- [x] Add feature provenance for every field, such as deterministic parser, registry snapshot, memory detector, runtime availability, injected test fixture, or fallback default.
- [x] Include extraction duration in milliseconds, measured outside model queue/service timing.
- [x] Capture the required feature families:
  - operation family and confidence;
  - language/OOD signal;
  - text size bucket;
  - action and condition counts;
  - minimum and quantile field confidence;
  - candidate count and top-two score margin;
  - unsupported-fragment count/bucket;
  - precedence ambiguity;
  - risk floor;
  - memory-reference flag;
  - exact-template match;
  - Foundation Model and RAG availability;
  - gate depth and warm-state hints.
- [x] Keep any numeric feature semantics stable under an existing schema version.

Acceptance:

- [x] Same input fixture and registry fixture produce byte-for-byte stable encoded snapshots.
- [x] Schema version mismatch is detected explicitly in decoding, migration, or comparison helpers.
- [x] Feature snapshots remain privacy-safe under telemetry payload inspection.

### P3.2 — Define The Prepared Request Contract

Primary file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/PreparedOrchestrationRequest.swift`

- [x] Define `PreparedOrchestrationRequest` as the single reusable deterministic preparation result.
- [x] Carry the original request metadata needed by the orchestrator while keeping the feature snapshot privacy-safe.
- [x] Store the `PortfolioFeatureSnapshot`.
- [x] Store the deterministic command/envelope artifact produced by the deterministic draft path.
- [x] Store a stable device snapshot used for candidate and freshness decisions.
- [x] Store memory-reference detection results and any resolved memory hints.
- [x] Store deterministic resolution state so downstream loop and graph escalation can consume it without repeating parsing/search.
- [x] Attach device-registry/index version or fingerprint values captured at preparation time.
- [x] Add a freshness check result that can tell later code to reuse, reprepare, or fall back safely.
- [x] Make the type immutable after construction.

Acceptance:

- [x] Loop and graph-facing code can receive prepared artifacts without needing to parse/search again in later phases.
- [x] A registry/index change invalidates or marks the prepared request stale.
- [x] Prepared request serialization round trips all deterministic fields required by tests.

### P3.3 — Implement The Deterministic Feature Extractor

Primary file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/OrchestrationFeatureExtractor.swift`

- [x] Define an extractor input type that includes request text/metadata, execution preference, registry, optional memory context, runtime availability state, RAG availability, and test seams.
- [x] Reuse deterministic operation/NLU parsing from existing parser utilities instead of invoking model-backed agents.
- [x] Reuse deterministic automation parsing from `AutomationPatternParser` where possible.
- [x] Reuse the deterministic draft pipeline for envelope creation where possible.
- [x] Compute deterministic candidate scores and top-two margin from registry data without calling model-backed candidate workers.
- [x] Detect conversational memory references using `ConversationMemoryReferenceDetector`.
- [x] Carry memory hints from the current memory/context store when available.
- [x] Compute action/condition counts, unsupported fragments, precedence ambiguity, exact-template match, and risk floor using deterministic rules.
- [x] Record FM/RAG availability as observed availability flags only; do not perform retrieval that can block on a model.
- [x] Use an injectable monotonic clock for extraction duration tests.
- [x] Produce no `FoundationModelCallRecorder` events and no ledger entries.
- [x] Do not instantiate `LanguageModelSession`, create `Prompt`, call `session.respond`, mutate external state, or execute device plans.

Acceptance:

- [x] Tests can install a fake recorder/ledger scope and assert zero Foundation Model call events during preparation.
- [ ] Cancellation or extraction failure returns bounded diagnostics without partially mutating registry, context, or devices.
- [x] Extraction is deterministic under repeated runs with the same fixtures.

### P3.4 — Add Device Snapshot Freshness

Primary areas: `DeviceRegistryProtocol` consumers and adaptive preparation support files

- [x] Define a stable device snapshot representation sorted by deterministic keys.
- [x] Include enough registry data for later reuse: device IDs, type/capability summaries, and candidate records needed by execution; keep public feature fields privacy-safe.
- [x] Add or derive a registry/index version or fingerprint.
- [x] Define freshness states, such as `fresh`, `stale`, `unknown`, and `unavailable`.
- [x] Add a check that compares the prepared version/fingerprint with the current registry/index state.
- [x] Define Phase 3 fallback behavior for stale snapshots: mark stale and let later orchestration reprepare or fall back; do not silently use stale evidence.

Acceptance:

- [x] Registry fixtures with reordered devices produce the same snapshot/fingerprint.
- [x] Adding, removing, or materially changing a device invalidates the prepared snapshot.
- [x] Freshness checks do not perform external mutation or model-backed retrieval.

### P3.5 — Integrate Preparation In Shadow/No-Behavior-Change Mode

Primary file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/HomeCommandOrchestrator.swift`

- [x] Add a construction/runtime seam for preparing a request before model-capable routing.
- [x] Keep preparation deterministic and outside Foundation Model service timing.
- [x] Preserve current graph, Tier-1, and verifier-loop behavior.
- [x] Do not select an arm based on the feature snapshot in Phase 3.
- [x] Do not execute a hidden second arm or shadow model path.
- [ ] Add optional metrics wiring for `preparationMs` using the Phase 2 `PortfolioMetrics` nullable field. Current implementation records `adaptivePreparation` in `OrchestratorMetrics.stageDurations`; full `PortfolioMetrics` attachment remains staged for Phase 4/5 metrics composition.
- [x] Ensure existing explicit orchestration modes continue to behave exactly as before when preparation is enabled.

Acceptance:

- [x] Existing focused orchestration tests pass with preparation enabled.
- [x] Model-call counts remain unchanged for Phase 3 focused no-model preparation coverage; broader full-suite verification is tracked below.
- [x] The prepared request is available to later routing/execution code without requiring behavioral activation in Phase 3.

### P3.6 — Add Contract And Regression Tests

Suggested new test files:

- `HomeAutomationCore/Tests/HomeAutomationOrchestratorTests/PortfolioFeatureSnapshotTests.swift`
- `HomeAutomationCore/Tests/HomeAutomationOrchestratorTests/PreparedOrchestrationRequestTests.swift`
- `HomeAutomationCore/Tests/HomeAutomationOrchestratorTests/OrchestrationFeatureExtractorTests.swift`

Tasks:

- [x] Test same input/fixture produces a stable feature vector and encoded payload.
- [x] Test no Foundation Model call recorder events are emitted during preparation.
- [x] Test memory-reference flag and memory hints are preserved.
- [x] Test device-trigger and precedence-ambiguity coverage are encoded.
- [x] Test registry version/fingerprint invalidates stale snapshots.
- [x] Test serialization round trip and schema mismatch behavior.
- [x] Test missing-value flags distinguish unknown/unavailable from zero.
- [x] Test top-two candidate margin for clear, ambiguous, and no-match fixtures.
- [x] Test exact-template match and unsupported-fragment features.
- [x] Test feature privacy by asserting raw command text, prompts, model output, and device names are absent from encoded snapshots.
- [x] Test preparation duration with an injected clock.
- [ ] Test extraction failure returns bounded diagnostics and no mutation.

### P3.7 — Update Documentation And Inventory

- [x] Update `Docs/CoordinatorTypeInventory.md` after adding new source declarations.
- [x] Update adaptive/orchestration documentation to describe deterministic preparation and privacy boundaries.
- [ ] Add a short note in Phase 2 documentation that `preparationMs` is populated by Phase 3.
- [ ] Update `implementation-plan.html` status only after implementation and verification are complete.
- [ ] Document which existing deterministic parser outputs are reused by `OrchestrationFeatureExtractor`.

### P3.8 — Verification Commands

Run focused tests first:

```bash
swift test --filter PortfolioFeatureSnapshotTests
swift test --filter PreparedOrchestrationRequestTests
swift test --filter OrchestrationFeatureExtractorTests
swift test --filter CoordinatorRefactorTests.coordinatorTypeInventoryListsEverySourceDeclaration
```

Then run the broader suite:

```bash
swift test
```

If the full suite still has unrelated known failures, capture the exact failing tests and confirm the Phase 3-focused tests are green.

Verification on 2026-07-13:

- [x] `swift test --filter PortfolioFeatureSnapshotTests` passed: 3 tests.
- [x] `swift test --filter PreparedOrchestrationRequestTests` passed: 3 tests.
- [x] `swift test --filter OrchestrationFeatureExtractorTests` passed: 4 tests.
- [x] `swift test --filter CoordinatorRefactorTests.coordinatorTypeInventoryListsEverySourceDeclaration` passed: 1 test.
- [ ] `swift test` still fails in pre-existing verifier verdict expectations:
  - `DraftVerifierWorkerSessionTests` — “Accepted verdict from mock still clears disputes after constraint”
  - `DraftVerdictTests` — “Accepted verdict clears disputes”
  - Total: 4 expectation issues. Phase 3-focused suites passed inside the broader run.

## Definition Of Done

- [x] The three Phase 3 adaptive source files exist and are covered by focused tests.
- [x] Preparation creates a reusable `PreparedOrchestrationRequest` and `PortfolioFeatureSnapshot`.
- [x] No Foundation Model calls, sessions, prompts, model-blocking retrieval, external mutations, or device executions occur during preparation.
- [x] Feature schema versioning, missing flags, provenance, and extraction duration are implemented.
- [x] Registry/index freshness is explicit and tested.
- [x] Serialization, schema mismatch, privacy, and deterministic stability tests pass.
- [x] Existing orchestration behavior and model-call counts are unchanged for focused Phase 3 coverage; full-suite status is captured in verification output.
- [x] Documentation and type inventory are updated.

## Risks And Watch Points

- Accidentally invoking model-backed worker sessions while trying to reuse existing parsing code.
- Leaking raw user text, prompts, device names, room names, or model output into the feature vector.
- Treating missing/unavailable feature values as zero and training future routers on misleading data.
- Creating an unstable registry fingerprint because device ordering, dictionary ordering, or timestamp-like fields are included.
- Repeating deterministic parsing/search later in loop or graph escalation instead of consuming the prepared artifacts.
- Smuggling Phase 4 behavior into Phase 3 by making eligibility or arm-selection decisions too early.
- Measuring preparation time inside Foundation Model queue/service windows instead of as separate deterministic overhead.
