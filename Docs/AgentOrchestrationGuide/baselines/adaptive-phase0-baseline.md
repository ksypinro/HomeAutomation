# Adaptive Portfolio Phase 0 Baseline

Date: 2026-07-13
Checkout: `80989c8` (`Merge pull request #22 from ksypinro/feat/gap-closure-device-triggers`)
Scope: source-of-truth reconciliation before adding Adaptive Portfolio runtime types.

## Source Truth

- `RepairSpecialistRegistry` now wires `.trigger`, `.conditionClause`, and `.segmentation` automation repair specialists.
- `.holisticDraft` intentionally remains unsupported and returns `nil` so the verifier loop escalates to the graph for whole-draft regeneration.
- Runtime wiring constructs the verifier loop with trigger, condition, batched-condition, segmentation, capability, target, risk, and operation repair dependencies.
- `Docs/GapClosureTask.md` and `Docs/task.md` are the current tracker truth for H6; older implementation plans are historical unless marked current.

## Verification Commands

```bash
swift test --filter HomeAutomationOrchestratorTests.AutomationRepairSpecialistTests
swift test --filter HomeAutomationOrchestratorTests.RuntimeDependencyWiringTests
swift test --filter HomeAutomationAgentTests.RepairPlannerTests
swift run home-automation-eval --compare-orchestration --output .build/adaptive-phase0-baseline --case-limit 50
```

Expected result: all three suites pass. These prove the advertised loop specialists are callable, runtime dependencies wire them, and disputes route to the intended specialist IDs.

The deterministic three-arm comparison produced report artifacts at:

- `HomeAutomationCore/.build/adaptive-phase0-baseline/orchestration-comparison.md`
- `HomeAutomationCore/.build/adaptive-phase0-baseline/orchestration-comparison.json`

Observed result on 2026-07-13: the comparison command exited non-zero because one exit criterion failed. This is expected Phase 0 evidence, not an adaptive activation approval.

| Arm | Accuracy | Mean FM calls | p95 duration | Escalation rate |
|---|---:|---:|---:|---:|
| graph | 76.9% | 0.00 | 643.6 ms | 0.0% |
| graph + Tier-1 | 76.9% | 0.00 | 748.2 ms | 0.0% |
| verifier loop | 38.5% | 0.00 | 1011.0 ms | 100.0% |

Failed gate: loop end-to-end accuracy was 38.5% against a graph baseline of 76.9%. The loop did pass FM-call, iteration, clarification-delta, and confirmation-rate gates in this deterministic run.

## Adaptive Implementation Boundary

Phase 0 does not add adaptive runtime types. The deterministic baseline is archived for this checkout. A supported-hardware live-model comparison should still be captured before promotion decisions; it must record device, OS, model availability, cold/warm state, and commit hash.
