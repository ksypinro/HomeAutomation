# Phase 0 Harness Extension: 5-Strategy Support

## Status
Specification for extending OrchestrationComparisonRunner to support 5 strategies (Graph, Graph+Tier-1, Verifier Loop, Adaptive Static, Adaptive Shadow) and the ConditionalLatencyV1Corpus.

## Required Changes

### 1. Extend OrchestrationArm enum
Current: `graph`, `graphWithTier1`, `verifierLoop`
Extend to: add `adaptiveStatic`, `adaptiveShadow` (or rename to `StrategyVariant` and use OrchestrationStrategy instead)

### 2. Create strategy selection logic
Map from (operation, features) → strategy:
- **Adaptive Static**: uses `AdaptivePortfolioController` with `PortfolioRolloutMode.activeStatic`
- **Adaptive Shadow**: uses `AdaptivePortfolioController` with `PortfolioRolloutMode.shadowStatic`
- Others: use static orchestration mode or explicit graph/verifier selection

### 3. Extend OrchestrationArmResult to capture:
- `strategy: OrchestrationStrategy` (the selected strategy, distinct from executing arm)
- `rootRoutingSource: String` ("normal", "adaptive", "prepared")
- `selectedArm: String` (may differ from executing arm in shadow mode)
- `routerRuleID: String?` (for routing decision audit trail)
- `conditionMetrics: [ConditionTelemetryMetrics]?` (aggregated condition telemetry)

### 4. Paired corpus integration
- Use `ConditionalLatencyV1Corpus.cases` to populate test suite
- For each case, generate paired runs: base command + conditioned command on same fixture
- Collect results in aligned pairs for latency comparison
- Tag runs with dimensions: condition count, form, resolution, tree, action count, trigger, risk

### 5. Run configuration
- **PR deterministic tier**: 1 warmup + 3 measured reps per arm, no wall-clock gate
- **Live smoke tier**: 1 warmup + 5 measured reps per strategy (only if model available)
- **Release tier**: ≥8 paired families, warm+cold profiles, ≥10 reps, Latin-square arm order

### 6. Live model gate
Require explicit opt-in and `.available` status check:
```swift
guard SystemLanguageModel.default.isAvailable else {
    throw EvaluationError.modelUnavailable("Foundation model not available for live evaluation")
}
```

Exit and fail the artifact if availability is lost during the run.

### 7. Correctness checks
Before latency comparison, verify:
- Action count and targets match expected
- Condition tree structure and ordering exact
- Device ID, capability, attribute, operator, value, units match
- Trigger policy preserved
- Risk and confirmation decision unchanged
- Canonical compiled SmartThings JSON identical (if automation)

## Priority for Phase 0
1. Extend OrchestrationArm and add strategy/routing attribution to results ← **START HERE**
2. Integrate ConditionalLatencyV1Corpus into test harness
3. Add paired-run collection and comparison logic
4. Implement live model gate and correctness checks
5. Create run tier wiring (deterministic / smoke / release)

## Files to modify/create
- `OrchestrationComparisonRunner.swift`: extend arm selection logic, strategy routing
- `OrchestrationArmResult`: add strategy, rootRoutingSource, selectedArm, routerRuleID, conditionMetrics
- `EvaluationRunner.swift`: integrate paired corpus, run tier logic, correctness checks
- New: `ConditionalLatencyHarnessSupport.swift` (helper for strategy selection and metrics aggregation)

## Deferred to Phase 0 Part 2b
- Cold vs. warm coordinator lifecycle
- Monotonic external timing integration
- Raw JSONL + JSON + Markdown report generation
- Critical path analysis (simplified to "all conditions" for Part 2a)
