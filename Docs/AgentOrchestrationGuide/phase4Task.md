# Adaptive Portfolio Phase 4 Task Tracker

Reference: [implementation-plan.html](implementation-plan.html#phase-4)  
Phase: 4 — Ship hard eligibility and a static router in shadow  
Created: 2026-07-13  
Status: Implemented — focused tests green on 2026-07-13

## Goal

Add the first portfolio routing layer without changing runtime behavior. Phase 4 should consume the Phase 3 `PreparedOrchestrationRequest` and `PortfolioFeatureSnapshot`, evaluate hard eligibility for each candidate arm, compute an auditable static routing decision, log/report what the router would have selected, and then continue through the currently configured arm exactly as before.

Phase 4 is complete when the system can answer “which arm would the static portfolio router choose, and why?” for every prepared request, while proving that shadow mode does not change results, model-call counts, event ordering, device mutations, or selected execution paths.

## Current Repository Findings

- Phase 3 is implemented and committed. `HomeCommandOrchestrator` prepares a `PreparedOrchestrationRequest` before root routing and stores it in root scoped context via `AdaptiveContextKeys.preparedRequest`.
- `PortfolioFeatureSnapshot` already exposes Phase 4 inputs: operation/confidence, language/OOD signal, text size, action/condition counts, field confidence, candidate margin, unsupported fragments, precedence ambiguity, risk floor, memory reference, exact-template match, FM/RAG availability, gate depth, and warm-state hints.
- `PreparedOrchestrationRequest` carries deterministic envelope, device snapshot, memory hints, resolution state, candidate IDs, and registry version/fingerprint.
- `PortfolioMetrics` already has nullable Phase 4+ fields such as `routerMs`, `eligibleArms`, and predicted/observed utility, but `OrchestratorMetrics` does not yet attach a full `PortfolioMetrics` value. Phase 3 currently records `adaptivePreparation` in `stageDurations`.
- The Phase 4 files named by the implementation plan now exist:
  - `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/PortfolioEligibilityPolicy.swift`
  - `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/StaticPortfolioRouter.swift`
  - `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/PortfolioDecision.swift`
  - `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/PortfolioRolloutMode.swift`
- Current explicit execution arms are represented by `FoundationModelCallArm`: `.graph`, `.graphWithTier1`, `.verifierLoop`, plus non-routing labels such as `.exactTemplate`, `.evaluation`, and `.unknown`.
- Existing supported orchestration modes remain `.graph` and `.verifierLoop`; Phase 4 must not introduce active `adaptivePortfolio` execution. That belongs to Phase 5.
- Full `swift test` is known to fail on unrelated verifier verdict expectations:
  - `DraftVerifierWorkerSessionTests` — “Accepted verdict from mock still clears disputes after constraint”
  - `DraftVerdictTests` — “Accepted verdict clears disputes”

## Scope Boundaries

### Included

- Hard eligibility policy for candidate portfolio arms.
- Static, auditable shadow routing rules.
- Complete decision record with selected arm, rejected arms, reasons, rule ID, utility components, uncertainty, policy version, and safe fallback.
- `PortfolioRolloutMode.shadowStatic` or equivalent runtime/configuration seam that computes decisions in shadow only.
- Compact decision explanations suitable for telemetry, metrics, and future UI display.
- Focused tests proving safety properties and no behavior change.

### Deferred To Later Phases

- Executing the selected portfolio arm (Phase 5).
- Adding `adaptivePortfolio` as an active orchestration mode (Phase 5).
- Refactoring graph/loop arm executors (Phase 5).
- Skipping root routing based on prepared deterministic evidence (Phase 5).
- Dependency-minimal graph compilation (Phase 6).
- Frontier scheduling or Foundation Model admission changes (Phase 7).
- Learned utility models and production rollout decisions (Phases 9–10).

Phase 4 should produce decisions, not act on them.

## Candidate Arms For Phase 4

Use a bounded portfolio-arm vocabulary and avoid treating every `FoundationModelCallArm` case as executable:

- `graph`: current graph orchestration path.
- `graphWithTier1`: graph path with Tier-1 mini-pipeline action resolution available.
- `verifierLoop`: verifier-loop-first path with graph/finalizer fallback.

Non-executable labels such as `evaluation`, `exactTemplate`, and `unknown` may appear in telemetry but should not be eligible selected execution arms in Phase 4.

## Implementation Order

### P4.1 — Define Rollout Mode

Primary file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/PortfolioRolloutMode.swift`

- [x] Define a bounded `PortfolioRolloutMode` enum, initially including at least:
  - `disabled`
  - `shadowStatic`
- [x] Make it `Sendable`, `Codable`, `Hashable`, and stable for metrics/report decoding.
- [x] Add clear semantics:
  - `disabled`: do not compute portfolio decisions.
  - `shadowStatic`: compute and log decision, then continue current configured arm.
- [x] Keep active portfolio execution modes out of Phase 4, or define them as unavailable placeholders only if needed for decoding.
- [x] Add a runtime-dependency seam to configure the rollout mode without changing default behavior.

Acceptance:

- [x] Default construction preserves current behavior and does not compute a decision unless explicitly enabled.
- [x] `shadowStatic` cannot alter the executing arm.

### P4.2 — Define Portfolio Decision Contract

Primary file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/PortfolioDecision.swift`

- [x] Define `PortfolioDecision` as `Sendable`, `Codable`, `Equatable`, and `Hashable`.
- [x] Include:
  - decision ID or stable request-local identifier;
  - policy version;
  - rollout mode;
  - selected arm;
  - safe fallback arm;
  - rule ID;
  - concise explanation;
  - eligible arm records;
  - rejected arm records;
  - utility components;
  - uncertainty;
  - feature schema version;
  - registry version/freshness when available.
- [x] Define bounded reason codes for rejection and selection. Avoid free-form strings as the canonical contract.
- [x] Define a compact `PortfolioArmDecisionRecord` for every considered arm with eligibility, reasons, and utility components.
- [x] Define `PortfolioUtilityComponents`, starting with static components such as correctness prior, latency prior, model-call prior, escalation risk, uncertainty, and safety penalty.
- [x] Keep all fields privacy-safe: no raw user text, prompts, model output, device names, room names, or unbounded identifiers beyond existing internal IDs/version strings.

Acceptance:

- [x] Decision JSON round trips deterministically.
- [x] Every considered arm appears exactly once as eligible or rejected.
- [x] Selected arm is always in the eligible set.
- [x] Empty eligible set produces a graph/fallback decision with explicit reason.

### P4.3 — Implement Hard Eligibility Policy

Primary file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/PortfolioEligibilityPolicy.swift`

- [x] Define a policy object with a stable `policyVersion`.
- [x] Evaluate each candidate arm against the prepared request and feature snapshot.
- [x] Reject arms for hard blockers:
  - model unavailable where the arm requires a model;
  - unsupported operation;
  - missing specialist coverage;
  - high/critical risk policy;
  - external mutation requirements;
  - memory-reference unsupported by the arm;
  - OOD or high uncertainty;
  - stale/unknown registry snapshot when freshness is required;
  - finalizer readiness gaps.
- [x] Distinguish hard rejection from soft utility preference.
- [x] Preserve graph/fallback as the fail-closed option when uncertainty is high or eligibility cannot be proven.
- [x] Treat mutation/high-risk traffic conservatively: it must not be explored or routed to a less-proven arm in Phase 4 decisions.
- [x] Avoid using raw text; consume `PortfolioFeatureSnapshot`, `PreparedOrchestrationRequest`, and bounded metadata.

Initial policy assumptions to encode:

- `graph` is the safest fallback for supported operations when models are available or when fallback graph behavior is already supported.
- `graphWithTier1` requires automation creation, no memory reference, low/medium risk, enough action coverage, no unsupported fragments, no complex/device-trigger condition gap, and MiniPipeline availability.
- `verifierLoop` requires supported operation coverage, low risk for direct commands, no unsupported language/OOD, and finalizer availability.

Acceptance:

- [x] Unsupported operation rejects non-fallback arms.
- [x] High/critical risk rejects exploratory/static shortcuts.
- [x] Memory reference rejects arms that do not support memory safely.
- [x] OOD/low-confidence requests fall back to graph.
- [x] Missing feature values fail closed rather than being treated as zero.

### P4.4 — Implement Static Portfolio Router

Primary file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/Adaptive/StaticPortfolioRouter.swift`

- [x] Define `StaticPortfolioRouter` that consumes `PreparedOrchestrationRequest` and `PortfolioEligibilityPolicy`.
- [x] Encode auditable static rules:
  - strong low-risk direct command → verifier loop;
  - confident simple schedule automation → `graphWithTier1`;
  - device trigger → graph;
  - complex condition or precedence ambiguity → graph;
  - OOD/unsupported language/unsupported domain → graph/fallback;
  - memory reference → graph until coverage gates say otherwise;
  - predicted loop escalation → graph directly.
- [x] Assign stable rule IDs, for example:
  - `static.direct.lowRisk.verifierLoop`
  - `static.automation.simpleSchedule.tier1`
  - `static.automation.deviceTrigger.graph`
  - `static.uncertain.graphFallback`
  - `static.noEligible.graphFallback`
- [x] Compute bounded utility components for each eligible arm.
- [x] Compute uncertainty and use a minimum margin threshold; if utility margin is too small, choose graph fallback.
- [x] Return a complete `PortfolioDecision` even when all arms are rejected.
- [x] Never execute an arm or call an orchestrator from the router.

Acceptance:

- [x] Selected arm ∈ eligible arms for all normal decisions.
- [x] Empty eligible set produces graph/fallback with explicit diagnostics.
- [x] High uncertainty chooses graph/fallback.
- [x] Static rules are deterministic for identical prepared fixtures.
- [x] Decision explanation is compact and bounded.

### P4.5 — Integrate Shadow Static Mode

Primary file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/HomeCommandOrchestrator.swift`  
Likely supporting file: `HomeAutomationCore/Sources/HomeAutomationOrchestrator/HomeAutomationCoordinator.swift`

- [x] Add portfolio rollout mode and router dependencies to runtime construction.
- [x] In `shadowStatic`, call `StaticPortfolioRouter` after Phase 3 preparation and before current root routing.
- [x] Store the decision in scoped context through a typed adaptive context key.
- [x] Log a portfolio decision telemetry event with bounded payload:
  - rollout mode;
  - selected arm;
  - executing/current arm;
  - eligible/rejected arms;
  - rule ID;
  - explanation;
  - policy version;
  - feature schema version;
  - router duration.
- [x] Continue through the current configured arm regardless of the shadow decision.
- [x] Do not create a hidden second execution, model call, graph run, verifier-loop run, or device mutation.
- [x] Do not reorder existing input/root-routing/outcome event sequence except for an additive, clearly named shadow decision event.
- [x] Record `routerMs`, `eligibleArms`, and decision summary into metrics in a backwards-compatible way.

Acceptance:

- [x] Shadow mode never changes result, selected execution path, model-call count, or device mutation behavior.
- [x] Shadow decision appears in telemetry/metrics.
- [x] Disabled mode preserves Phase 3 behavior and does not compute router decisions.

### P4.6 — Build Decision Explanations

Primary files: `PortfolioDecision.swift`, `StaticPortfolioRouter.swift`

- [x] Add a compact explanation builder using bounded phrases and numeric buckets.
- [x] Include the most important selection reasons, for example:
  - “would choose Tier-1: simple schedule, 2 confident actions, no memory, low risk”
  - “would choose graph: device trigger and precedence ambiguity”
  - “would choose graph: unsupported/OOD or missing required features”
- [x] Ensure explanations are safe for telemetry/UI: no raw command text, device names, room names, or prompts.
- [x] Include rejected-arm reason summaries for diagnostics.

Acceptance:

- [x] Explanations are stable for fixture decisions.
- [x] Explanations are concise and privacy-safe.

### P4.7 — Tests

Suggested new test files:

- `HomeAutomationCore/Tests/HomeAutomationOrchestratorTests/PortfolioEligibilityPolicyTests.swift`
- `HomeAutomationCore/Tests/HomeAutomationOrchestratorTests/StaticPortfolioRouterTests.swift`
- `HomeAutomationCore/Tests/HomeAutomationOrchestratorTests/PortfolioDecisionTests.swift`
- `HomeAutomationCore/Tests/HomeAutomationOrchestratorTests/PortfolioShadowModeTests.swift`

Tasks:

- [x] Test decision serialization round trip and schema/policy version fields.
- [x] Test every considered arm is eligible or rejected exactly once.
- [x] Test selected arm is always eligible.
- [x] Test empty eligible set returns graph/fallback decision.
- [x] Test high uncertainty routes to graph.
- [x] Test unsupported operation rejects non-fallback arms.
- [x] Test high/critical risk rejects exploratory/static shortcuts.
- [x] Test memory reference routes to graph until support is explicit.
- [x] Test strong low-risk direct command would choose verifier loop.
- [x] Test confident simple schedule automation would choose Tier-1.
- [x] Test device trigger and precedence ambiguity would choose graph.
- [x] Test missing feature values fail closed.
- [x] Test explanation text contains bounded reason phrases and no raw command/device text.
- [x] Test shadow mode stores/logs decision but preserves current result and model-call count.
- [x] Test disabled mode does not compute/log portfolio decision.

### P4.8 — Documentation And Inventory

- [x] Update `Docs/CoordinatorTypeInventory.md` after adding new source declarations.
- [x] Update this tracker as each slice lands.
- [x] Add Phase 4 verification notes after implementation.
- [ ] Update `phase3Task.md` only if Phase 4 changes the way `PortfolioMetrics` consumes `preparationMs`.
- [ ] Update `implementation-plan.html` status only after implementation and verification are complete.

Verification notes, 2026-07-13:

- Focused Phase 4 tests passed:
  - `swift test --filter PortfolioDecisionTests`
  - `swift test --filter PortfolioEligibilityPolicyTests`
  - `swift test --filter StaticPortfolioRouterTests`
  - `swift test --filter PortfolioShadowModeTests`
- Targeted regression tests passed:
  - `swift test --filter CoordinatorRefactorTests.coordinatorTypeInventoryListsEverySourceDeclaration`
  - `swift test --filter RuntimeDependencyWiringTests`
  - `swift test --filter OrchestrationFeatureExtractorTests`
  - `swift test --filter OrchestratorInfrastructureTests`
- Full `swift test` still fails in pre-existing verifier/verdict expectations outside the Phase 4 router surface:
  - `DraftVerifierWorkerSessionTests` — “Accepted verdict from mock still clears disputes after constraint”
  - `DraftVerdictTests` — “Accepted verdict clears disputes”

### P4.9 — Verification Commands

Run focused tests first:

```bash
swift test --filter PortfolioDecisionTests
swift test --filter PortfolioEligibilityPolicyTests
swift test --filter StaticPortfolioRouterTests
swift test --filter PortfolioShadowModeTests
swift test --filter CoordinatorRefactorTests.coordinatorTypeInventoryListsEverySourceDeclaration
```

Then run targeted regression around current execution behavior:

```bash
swift test --filter RuntimeDependencyWiringTests
swift test --filter OrchestratorInfrastructureTests
swift test --filter OrchestrationFeatureExtractorTests
```

Then run the broader suite:

```bash
swift test
```

If the full suite still has unrelated verifier verdict failures, capture the exact failing tests and confirm all Phase 4-focused tests are green.

## Definition Of Done

- [x] Phase 4 adaptive files exist and are covered by focused tests.
- [x] Hard eligibility rejects unsafe or unsupported arms with bounded reasons.
- [x] Static router returns complete deterministic `PortfolioDecision` records.
- [x] Every normal decision has selected arm ∈ eligible arms.
- [x] Empty/uncertain decisions fail closed to graph/fallback with explicit diagnostics.
- [x] `PortfolioRolloutMode.shadowStatic` computes/logs decisions but does not alter execution.
- [x] Shadow mode does not change result, event ordering, model-call count, or device mutation behavior.
- [x] Decision explanations are compact and privacy-safe.
- [x] Metrics/telemetry expose router decision and duration without misleading Phase 5 fields.
- [x] Documentation and coordinator inventory are updated.

## Risks And Watch Points

- Accidentally activating the static router instead of keeping it shadow-only.
- Treating `.exactTemplate`, `.evaluation`, or `.unknown` telemetry labels as executable portfolio arms.
- Allowing missing feature values to look like safe zeroes.
- Routing high-risk or mutation-capable requests toward shortcuts before Phase 5 executor/finalizer safety is proven.
- Logging raw command text, device names, room names, prompts, or model output in decision explanations.
- Recomputing deterministic preparation inside the router instead of consuming the Phase 3 prepared request.
- Introducing a hidden second execution in the name of “shadow” comparison.
- Writing utility fields that look learned/calibrated before Phase 9 training exists.
