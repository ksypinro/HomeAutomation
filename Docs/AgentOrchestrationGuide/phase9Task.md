# Phase 9 Task Tracker — Learned Portfolio Router (Offline Only)

Source: `Docs/AgentOrchestrationGuide/implementation-plan.html`, Phase 9.

## Goal

Introduce an offline-trained, fail-closed learned portfolio router path without production exploration or runtime LLM routing. Phase 9 is complete when training rows can be exported, a normalized model artifact can be loaded, learned routing can choose only eligible arms, OOD/schema/low-margin cases fall back to static graph-safe behavior, and router regret can be evaluated offline.

## Implementation tasks

- [x] Add model artifact types for learned portfolio routing.
  - [x] Store artifact version, feature schema, policy version, minimum margin, coefficients, calibration metadata, and OOD policy.
  - [x] Keep artifact deterministic/Codable and reject incompatible schemas.

- [x] Add `LearnedPortfolioRouter`.
  - [x] Score only arms that pass `PortfolioEligibilityPolicy`.
  - [x] Treat safety failures/ineligible arms as hard rejects, not finite penalties.
  - [x] Fall back to `StaticPortfolioRouter` for schema mismatch, missing features, OOD signals, missing arm models, and small utility margins.
  - [x] Avoid runtime LLM routing and production exploration.

- [x] Add portfolio training dataset export support.
  - [x] Create counterfactual rows per case/arm from orchestration comparison reports.
  - [x] Persist feature snapshot, eligibility, correctness, duration, calls, queue wait, escalation, clarification, confirmation, failure, and utility.
  - [x] Keep utility defined outside production as correctness minus weighted latency/calls/escalation/uncertainty.

- [x] Add offline router regret evaluation.
  - [x] Compare selected utility with best eligible per-case oracle.
  - [x] Report mean/max regret and slice by operation, risk, language/OOD, warm/cold, and escalation.
  - [x] Reject unsafe/ineligible choices in evaluation.

- [x] Add CLI entry points.
  - [x] `--export-portfolio-training`
  - [x] `--evaluate-portfolio-router`
  - [x] `--model-artifact-path`
  - [x] `--portfolio-training-path`

- [x] Add tests and inventory/docs updates.
  - [x] Artifact scoring/schema validation tests.
  - [x] Learned router fallback/eligibility tests.
  - [x] Dataset/evaluator regret tests.
  - [x] Coordinator type inventory rows for new structs.

## Notes

- Phase 9 deliberately does not enable active learned routing in production.
- Learned choices remain bounded by the existing hard eligibility policy.
- Static graph-safe behavior remains the default whenever confidence or compatibility is insufficient.
