# Conditional Automation Latency — Tuned Values & Rollback Switches

Status: reference (Phases 0–4B shipped; live release gates and default-on pending)

This is the single reference for every tuned value introduced by the
[Conditional Automation Latency plan](ConditionalAutomationLatencyImplementationPlan.md) and the
independent switches used to roll each behavior back. All values are **configuration-driven, not
release thresholds** — none is a committed SLO until a live baseline artifact justifies it (see
[§ Baseline artifact](#baseline-artifact)).

---

## Deterministic condition acceptance (Phase 1)

| Value | Setting | Where |
|---|---|---|
| Acceptance gate | `0.80` | `AutomationConditionClauseResolutionWorkerSession.deterministicAcceptThreshold`, `BatchedConditionClauseResolver.deterministicAcceptThreshold` |
| Device-resolved confidence | `0.84` | `AutomationConditionDeterministicResolver.assess` |
| Parsed-but-unresolved confidence | `0.72` | same |
| Parse failure | `0.0`, completeness `.unsupported` | same |

A clause is accepted deterministically (no FM) only when the shared assessor returns
`completeness == .complete` **and** it round-trips through the consuming target (`isSafeToAccept`).
Confidence alone is never the safety proof.

## FM timeouts — two clocks (Phase 2, D3)

| Value | Default | Where |
|---|---|---|
| Admission (queue) deadline | `3000 ms` | `FoundationModelTimeoutConfiguration.admissionDeadlineMs` |
| Post-admission service timeout | `8000 ms` | `FoundationModelTimeoutConfiguration.serviceTimeoutMs` |

The service timeout is enforced in `FoundationModelCallRecorder.record` (races the operation, cancels
on expiry, releases the lease, finalizes the ledger once). Condition single + batch resolvers pass
the 8 s budget. The admission-deadline parameter exists but enforcement lives in the admission
controller's `deadlineClass`; recalibrate the service timeout toward ~6 s if live condition-service
p95 < ~4 s.

## Fan-out concurrency caps (Phase 2)

| Value | Default | Where |
|---|---|---|
| Overall component cap | `6` | `AutomationComponentFanOutRunner.defaultMaxConcurrentComponents` |
| Concurrent Graph action pipelines | `2` | `AutomationFanOutSchedulingConfiguration.maxConcurrentGraphActions` |
| Tier-1 mini-pipeline actions | `4` | `AutomationFanOutSchedulingConfiguration.maxConcurrentTier1Actions` |
| Condition batches per automation | `1` | `AutomationFanOutSchedulingConfiguration.maxConcurrentConditions` |
| Global FM gate concurrency | `2` | `FoundationModelGate` (unchanged — **not** raised as a fix) |

Scheduling order is trigger → conditions → actions, so conditions start before long action pipelines.

## Batch condition prompt budget (Phase 2)

| Value | Default | Where |
|---|---|---|
| Max devices in a batch prompt | `48` | `BatchedConditionClauseResolver.maxBatchPromptDevices` |
| Prompt character budget | `8000` | `ConditionBatchSessionContext.maxPromptCharacters` |

Clause-relevant devices are kept first, then stable-filled to the cap, so a large registry cannot
inflate the prompt.

## Conditional Tier-1 eligibility (Phase 3)

Cohort (all must hold): draft (non-external) creation; schedule trigger; exactly one **complete,
single-leaf, shared-assessor** condition; 1–3 actions; no unsupported fragments / memory refs / OR /
NOT / mixed-precedence; low or medium risk; in-domain; op-confidence ≥ 0.80, min-field ≥ 0.50; fresh
registry. Reason-coded by `AutomationConditionalTier1RejectionReason`. Rule ID
`static.automation.conditionalSchedule.tier1`.

## Verifier loop condition handling (Phase 4)

- Loop condition clauses use the shared assessor; complete clauses enter fully populated (no
  pre-repair). Lossless forms (range/`.changes`/units/cross-device) are carried in
  `ConditionLeafDraft.structuredCondition` (envelope schema **v2**) and compile exactly.
- No repair on the final iteration; precedence-ambiguous automations escalate at preflight.
- `VerifierLoopPolicy`: `maxIterations = 3`, `maxRepairCallsPerIteration = 3`.

<a name="rollback-switches"></a>
## Independent rollback switches

Each behavior can be disabled without reverting unrelated telemetry (rollback order: conditional
Tier-1 → scheduling/priority → service-timeout → deterministic acceptance; never disable
validation/risk/confirmation/compilation/finalization).

| Switch | Default | Effect when disabled |
|---|---|---|
| `PortfolioEligibilityPolicy.conditionalTier1Enabled` | `false` | Conditional automations never route to Tier-1 (byte-identical to pre-Phase-3). |
| `PortfolioRolloutConfiguration.adaptiveRoutingEnabled` | `true` | Forces graph; disables adaptive routing entirely. |
| `PortfolioRolloutConfiguration.frontierSchedulingEnabled` | `true` | Disables frontier scheduling. |
| `PortfolioRolloutConfiguration.residualBatchingEnabled` | `true` | Disables residual batching. |
| `PortfolioRolloutConfiguration.rollbackReasons` | `[]` | Any entry forces graph rollback. |
| `FoundationModelTimeoutConfiguration` (per resolver) | 3 s / 8 s | Pass a larger/zero service timeout to relax enforcement. |
| Deterministic acceptance threshold (per resolver) | `0.80` | Raise to `1.0` to force every clause through FM. |

<a name="baseline-artifact"></a>
## Baseline artifact & default-on (pending)

Enabling `conditionalTier1Enabled` by default, and treating any latency number above as a release
threshold, is **gated on a checked-in live baseline** produced by the Phase 0 harness
(`OrchestrationComparisonRunner` five-strategy paired runs + `Phase0RunTierConfiguration`). That
requires a live foundation model and is tracked as the remaining Phase 5 rollout step.
