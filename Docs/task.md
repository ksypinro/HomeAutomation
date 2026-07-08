# Verifier-Loop Orchestration — Implementation Tracker

Reference: [LoopOrchestrationImplementationPlan.md](LoopOrchestrationImplementationPlan.md)

## Phase A — Quick wins
> Independently shippable, no architecture change.

- [x] A1: Semantic NLU timeout parity
- [x] A2: Configurable NLU soft-timeout budget (`NLUSoftTimeoutBudget`)
- [x] A3: Scoped NLU policy override → threshold-gate automation action subgraph
- [x] A4: Skip RAG few-shot enrichment for short/confident inputs
- [x] A5: `FoundationModelGate` — global FM admission + queue-wait telemetry
- [x] A6: Remove mandated tool round-trip from semantic NLU
- [x] A7: Close the `windowShade` verb gap deterministically
- [x] A8: Cap automation fan-out concurrency

**Commit:** `d0b1649` — `feat: implement Phase A quick wins (A1-A8)`

---

## Phase B — DraftEnvelope + DeterministicDraftPipeline
> Typed envelope architecture and deterministic-first pipeline.

- [x] B1: Envelope types (`DraftEnvelope`, `FieldID`, `FieldProvenance`, sections)
- [x] B2: Envelope artifact key + `AgentID` entries
- [x] B3: `DeterministicDraftPipeline` — direct command (`makeCommandEnvelope`)
- [x] B4: `DeterministicDraftPipeline` — automation (`makeAutomationEnvelope`)
- [x] B5: Tests (22 tests: 10 envelope, 12 pipeline)

**Commit:** `265321b` — `feat: implement Phase B — DraftEnvelope types and DeterministicDraftPipeline`

---

## Phase C — Verifier (shadow mode)
> FM-backed draft verifier with shadow evaluation.

- [x] C1: Verdict types (`DraftVerdict`, `DraftDispute`, `DisputeKind`, `DraftVerdictSchema`)
- [x] C2: `VerifierPromptBuilder` (initial + delta prompts, budget enforcement)
- [x] C3: `DraftVerifierWorkerSession` (mock closure, FM gate, recorder, soft timeout, post-constraints)
- [x] C4: Shadow-mode evaluation (`VerifierShadowRunner`, `--shadow-verify` CLI)
- [x] C5: Tests (18 tests: 8 verdict, 6 prompt builder, 4 worker session)

**Commit:** `e0726c0` — `feat: implement Phase C — DraftVerifier shadow mode (C1-C4)`

---

## Phase D — Repair layer
> Specialist agents that fix disputed fields.

- [x] D1: `RepairPlanner` — deterministic plan from disputes → ordered repair steps
- [x] D2: `FragmentNLUWorkerSession` — merged NLU specialist for action fragments
- [x] D3: `ActionTargetResolver` — re-resolve target device for disputed actions
- [x] D4: `StructuralDraftBuilder` — envelope→draft builder (pure, no FM)
- [x] D5: `AutomationRiskAssessor` — deterministic risk re-assessment
- [x] D6: `EnvelopeMerger` + `RepairResult` — merge repair results back into the envelope
- [x] D7: Tests (35 tests: 11 planner, 4 fragment NLU, 4 target resolver, 6 draft builder, 6 risk assessor, 14 merger) + inventory update

**Commit:** pending

---

## Phase E — Loop orchestrator + wiring
> Wire verifier + repair into a bounded loop with runtime mode flag.

- [x] E1: Policy & exit types (`VerifierLoopPolicy`, `LoopExit`, `EscalationReason`, `LoopRunMetrics`)
- [x] E2: `VerifierLoopOrchestrator` + `RepairSpecialistRegistry` — bounded verify→repair loop (max 3 iterations)
- [x] E3: `LoopResultBridge` — envelope → `HomeAutomationResolverResult` bridge + context seeding
- [x] E4: `OrchestrationMode` + wiring into `HomeAutomationRuntimeDependencies` and `HomeCommandOrchestrator`
- [x] E5: Loop metrics (`LoopRunMetrics` on `OrchestratorMetrics`)
- [x] E6: Escalation to legacy graph (fallback when loop can't converge — `.escalated` falls through to graph path)
- [x] E7: Tests (13 tests: accept-on-first, dispute-repair-accept, noProgress, latch, iterationCap, clarification, verifierUnavailable, metrics, codable, registry, policy defaults, bridge accepted, bridge clarification) + inventory update

---

## Phase F — Automation Tier 1 (parallel to C–E)
> Graph-runtime automation pipeline, no loop dependency.

- [x] F1: Automation action mini-pipeline (`AutomationActionMiniPipeline`, `AutomationActionResolver` dispatch)
- [x] F2: τ-gate segmentation / trigger / condition workers (deterministic accept thresholds)
- [x] F3: Rule-level risk assessment (`assessFromActions` on `AutomationRiskAssessor`)
- [x] F4: Provider flag (`useMiniPipeline` on `AutomationCoordinator`, threaded to `makeActionResolver`)
- [x] F5: Tests (13 tests: mini-pipeline resolve, zero-FM, gibberish, resolver dispatch, segmentation τ-gate, segmentation FM-fallback, trigger τ-gate, condition τ-gate, risk safe/security/empty, coordinator flag on/off) + inventory update

---

## Phase G — Evaluation & rollout
> A/B evaluation and production rollout gating.

- [x] G1: A/B comparison runner (`OrchestrationComparisonRunner`, `OrchestrationArm`, `OrchestrationArmResult`, `OrchestrationArmSummary`, `OrchestrationComparisonReport`) + CLI `--compare-orchestration` flag
- [x] G2: Exit criteria (`OrchestrationExitCriteria`, `ExitCriterionResult`) — 7 gates: accuracy, FM calls, p95 iterations, clarification delta, safety-gate
- [x] G3: Tests (13 tests: arm summary stats ×6, exit criteria ×5, report structure ×2) + inventory update

---

## Notes

- All code targets Swift 6.1 strict concurrency, iOS/macOS 26.0.
- Tests use Swift Testing (`@Suite`, `@Test`, `#expect`).
- Package root: `HomeAutomationCore/`, tests run via `swift test`.
- `CoordinatorTypeInventory.md` must be updated for every new struct/actor/class.
- `productionDependencyConstructionIsCoordinatorBounded` test enforces that `MockHomeDeviceRegistry()` is only constructed in the coordinator file.
