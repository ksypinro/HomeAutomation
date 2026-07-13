# Phase 10 Task Tracker — Evaluate, Canary, and Roll Out

Source: `Docs/AgentOrchestrationGuide/implementation-plan.html`, Phase 10.

## Goal

Add the operational rollout envelope around the adaptive portfolio work: explicit learned rollout modes, canary/rollback configuration, operator evidence, deterministic gate reports, and documentation/type-inventory coverage. Phase 10 should not remove the graph rollback path or silently enable unsafe learned routing.

## Implementation tasks

- [x] Extend rollout modes.
  - [x] Add `shadowLearned` and `activeLearned`.
  - [x] Record the requested rollout mode in portfolio decisions/metrics.
  - [x] Execute selected arms only for active modes.

- [x] Add independent rollout/rollback configuration.
  - [x] Separate adaptive routing, frontier scheduling, residual batching, and prewarm/session-affinity switches.
  - [x] Add arm/risk allowlists, canary percentage, graph holdback, and policy/model/config version fields.
  - [x] Make safety/latency/artifact/scheduler rollback reasons force new runs to graph-safe behavior without an app restart.

- [x] Wire learned rollout safely.
  - [x] Inject optional model artifacts through runtime dependencies.
  - [x] Use `LearnedPortfolioRouter` only for learned rollout modes with an artifact.
  - [x] Fall back to graph/static behavior when learned rollout is requested without a valid artifact.

- [x] Expose operator evidence.
  - [x] Add a JSON/Codable rollout evidence record to metrics.
  - [x] Include selected/executing arm, eligibility/rejection summaries, fallback reason, rollout/config versions, canary decision, switches, and rollback reasons.
  - [x] Show a compact evidence panel in the demo app when metrics are available.

- [x] Add deterministic release gate report support.
  - [x] Add evaluation-side adaptive release gate report model.
  - [x] Add CLI command for gate reports.
  - [x] Cover CI/hardware gate pass/fail status and rollback-drill status.

- [x] Add verification and docs.
  - [x] Unit tests for rollout mode semantics, canary/rollback config, learned wiring, and release gate reports.
  - [x] Update implementation plan Phase 10 status.
  - [x] Update coordinator type inventory.
