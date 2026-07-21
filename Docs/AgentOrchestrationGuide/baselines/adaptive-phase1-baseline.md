# Adaptive Portfolio Phase 1 Baseline

Date: 2026-07-13
Scope: deterministic three-arm comparison after Phase 1 shared finalizer implementation.

## Verification Command

```bash
swift run home-automation-eval --compare-orchestration --output .build/adaptive-phase1-baseline --case-limit 50
```

Generated artifacts:

- `HomeAutomationCore/.build/adaptive-phase1-baseline/orchestration-comparison.md`
- `HomeAutomationCore/.build/adaptive-phase1-baseline/orchestration-comparison.json`

## Result

The deterministic comparison completed successfully with all exit criteria passing.

| Arm | Accuracy | Mean FM calls | p95 duration | Finalization receipt coverage | Completed receipt rate | Actionable without completed receipt |
|---|---:|---:|---:|---:|---:|---:|
| graph | 76.9% | 0.00 | 637.2 ms | 100.0% | 100.0% | 0 |
| graph + Tier-1 | 76.9% | 0.00 | 746.1 ms | 100.0% | 100.0% | 0 |
| verifier loop | 76.9% | 0.00 | 1072.3 ms | 100.0% | 100.0% | 0 |

Exit criteria: 8/8 passed.

## Receipt Coverage Notes

- Each arm had 12 actionable cases requiring a finalization receipt.
- Each arm recorded 12 completed receipts.
- No actionable result was emitted without a completed receipt.
- Verifier-loop deterministic escalation now finalizes its seeded proposal when live graph/model escalation is unavailable, so the loop arm records receipt coverage instead of bridge-only actionable output.

## Remaining Promotion Boundary

This deterministic baseline is an implementation checkpoint, not a production default-flip approval. A supported-hardware live-model comparison should still be captured before promotion decisions.
