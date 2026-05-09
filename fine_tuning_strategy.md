# Multi-Agent Fine-Tuning & Debugging Strategy

## Executive Summary

This document lays out a **4-phase strategy** to take our 25-agent HomeAutomation orchestrator from "architecture complete" to "production-accurate." The core idea is to treat every agent as a trainable unit—generate massive synthetic datasets from the mock registry, evaluate each agent in isolation, tune deterministic rules and FM prompts, then train LoRA adapters for the Foundation Model sessions.

---

## Phase 1: Synthetic Data Generation Pipeline

### 1.1 Output-First Generation (Registry → Draft)

We have **24+ devices** in `MockHomeDeviceRegistry.defaultDevices`, each with capabilities, commands, modes, and state. We can enumerate every valid `(device, capability, command, parameter)` tuple.

**Combinatorial explosion from the registry:**

| Dimension | Count | Example |
|-----------|-------|---------|
| Devices | 24 | `bedroom_ac`, `front_door_lock` |
| Capabilities per device | 2–9 | `switch`, `thermostatCoolingSetpoint` |
| Commands per capability | 1–5 | `on`, `off`, `setLevel`, `increaseValue` |
| Parameter values | 5–20 | `50%`, `24°C`, `cool`, `auto` |
| Rooms | 12 | `bedroom`, `kitchen`, `living room` |
| **Total valid tuples** | **~50,000+** | |

**Step 1: Write a `SyntheticDataGenerator`** that walks `HomeCapabilityRegistry` and `MockHomeDeviceRegistry` to emit every valid `HomeCommandDraft`:

```swift
struct SyntheticOutputRecord: Codable {
    let id: String
    let device: HomeCandidateRecord
    let draft: HomeCommandDraft
    let expectedNLU: ExpectedNLULabels
}

struct ExpectedNLULabels: Codable {
    let language: HomeLanguageDetectionResult
    let domain: HomeDomainClassificationResult
    let intentFamily: HomeIntentFamilyResult
    let deviceType: HomeDeviceTypeResult
    let slots: HomeSlotExtractionResult
    let risk: HomeRiskClassificationResult
}
```

**Step 2: Reverse-generate user inputs using LLMs.** For each `SyntheticOutputRecord`, call Claude/GPT with a prompt like:

```
Given this smart-home command output:
- Device: "Bedroom AC" (airConditioner, bedroom)
- Intent: setValue
- Capability: thermostatCoolingSetpoint
- Command: setCoolingSetpoint
- Parameter: value=22, unit=celsius

Generate 10 diverse natural language commands a user might say.
Include: casual, formal, multilingual (Bengali+English), abbreviated, 
with typos, with room context, without room context, relative ("lower 
the AC by 2 degrees"), and status-query variants.
```

This gives us **10 × 50,000 = 500,000 labeled pairs** minimum.

### 1.2 Data Categories

| Category | Purpose | Example |
|----------|---------|---------|
| **Happy Path** | Correct device + command | "Turn on the bedroom lamp" |
| **Ambiguous** | Multiple matching devices | "Turn on the light" (4 lights exist) |
| **Negative** | Non-home commands | "What's the weather?" |
| **Multilingual** | Bengali, mixed bn_en | "বেডরুমের লাইট বন্ধ কর" |
| **Adversarial** | Typos, slang, abbreviations | "dim da livin rm lite 2 50" |
| **Multi-step** | Compound commands | "Turn off all lights and lock the door" |
| **Relative** | Delta-based values | "Make it 3 degrees cooler" |
| **Context-dependent** | Pronoun resolution | "Turn it off" (after "turn on the lamp") |

### 1.3 Output Format (JSONL)

```jsonl
{"id":"syn_001","input":"Set the bedroom AC to 22 degrees","expected_draft":{...},"expected_nlu":{...},"tags":["happy_path","temperature","en"]}
```

---

## Phase 2: Per-Agent Evaluation Harness

### 2.1 Agent Testing Architecture

Each of the 25 agents gets its own evaluation harness. The key insight: **test each agent in isolation** with known inputs and expected outputs.

```
┌─────────────────────────────────────────────────┐
│           Per-Agent Evaluation Runner            │
├─────────────────────────────────────────────────┤
│  Load JSONL dataset for agent                    │
│  For each test case:                             │
│    1. Construct agent input from test case       │
│    2. Run agent.run(input, context)              │
│    3. Compare output to expected                 │
│    4. Record accuracy metrics                    │
│  Emit: accuracy, precision, recall, confusion    │
└─────────────────────────────────────────────────┘
```

### 2.2 Agent-Specific Metrics

#### NLU Agents (6 agents)

| Agent | Metric | Target |
|-------|--------|--------|
| LanguageAgent | Language code exact match | ≥ 95% |
| DomainAgent | Domain enum match | ≥ 98% |
| IntentFamilyAgent | Top-1 family match | ≥ 90% |
| DeviceTypeAgent | Device type in top-3 | ≥ 92% |
| SlotExtractionAgent | Room F1 / Nickname F1 | ≥ 85% / ≥ 80% |
| RiskClassificationAgent | Risk level exact match | ≥ 95% |

#### Candidate Agents (4 agents)

| Agent | Metric | Target |
|-------|--------|--------|
| CandidateRetrieval | Target device in retrieved set | ≥ 95% |
| CandidateRanking | Target device is rank-1 | ≥ 85% |
| CandidateShard | Target device in shard winners | ≥ 90% |
| CandidateHydration | All selected IDs hydrated | 100% |

#### Draft Agents (4 agents)

| Agent | Metric | Target |
|-------|--------|--------|
| InstructionComposer | Package within token budget | 100% |
| DraftGeneration | Full draft field match | ≥ 80% |
| DraftRepair | Recovery rate on initial failures | ≥ 70% |
| AgentDraftResolver | Final draft match after retries | ≥ 85% |

#### Safety / Execution / Response Agents

| Agent | Metric | Target |
|-------|--------|--------|
| SafetyValidation | False-positive rate | ≤ 2% |
| ParameterValidation | Invalid parameter catch rate | ≥ 98% |
| ConfirmationPolicy | Correct confirmation gating | ≥ 99% |
| ExecutionPlanning | Plan step correctness | ≥ 95% |
| ResultSummary | User-facing text quality | Manual review |
| ClarificationAgent | Triggers on true ambiguity | ≥ 90% |

### 2.3 Confusion Matrix per NLU Agent

For classification agents (Domain, IntentFamily, Risk), build confusion matrices:

```
                    Predicted
              power  temp  brightness  ...
Actual power   450     3      12      ...
       temp     2    380       0      ...
  brightness    8      0     420      ...
```

This immediately tells us where the model confuses intent families.

---

## Phase 3: Tuning Strategy (Per-Agent)

### 3.1 Deterministic Layer Tuning

**Priority: Tune these FIRST before touching FM prompts.** The deterministic layer (`AgentTextParser`, `NLUModelCallPolicy`, `MockHomeDeviceRegistry.score()`, `HomeCandidateResolverSupport.deterministicAggregation()`) handles the majority of cases.

#### 3.1.1 `AgentTextParser` Keyword Expansion

Current keyword rules in `AgentTextParser` are limited. Use the synthetic dataset to:

1. **Mine frequent n-grams** from user inputs per intent family
2. **Expand keyword dictionaries** with discovered patterns
3. **Add multilingual keyword maps** (Bengali, Spanish, etc.)

Example improvement:
```swift
// Before: only matches "turn on", "switch on"
// After: also matches "চালু কর", "encender", "lite up", "power on"
```

#### 3.1.2 `NLUModelCallPolicy` Threshold Tuning

Current thresholds are hand-picked defaults. Use the evaluation harness to find optimal values:

```
For each threshold in [0.50, 0.55, 0.60, ..., 0.95]:
  Run NLU agent with threshold
  Measure: accuracy when using deterministic vs FM
  Find: threshold where FM adds ≤1% accuracy but saves 40%+ calls
```

| Current | Recommendation |
|---------|---------------|
| language: 0.90 | Keep (language detection is deterministic-strong) |
| domain: 0.80 | May lower to 0.75 (domain is usually obvious) |
| intentFamily: 0.78 | May lower to 0.70 (keyword rules are good for common intents) |
| deviceType: 0.78 | Keep (device type extraction benefits from FM) |
| slotExtraction: 0.78 | May raise to 0.82 (slots are complex, FM helps more) |
| risk: 0.85 | Keep (safety-critical, deterministic is preferred) |

#### 3.1.3 Candidate Scoring Weights

`HomeCandidateResolverSupport.deterministicAggregation()` uses hand-tuned scoring. Optimize via grid search:

```
Current: label match = 20, type match = 8, room match = 8, ...
Sweep:   label match ∈ [15..25], type match ∈ [5..12], room match ∈ [5..12]
Metric:  % of cases where correct device is rank-1
```

### 3.2 Foundation Model Prompt Tuning

For each NLU `WorkerSession` and the Draft resolver, systematically improve prompts:

#### 3.2.1 Few-Shot Examples in System Instructions

Current NLU prompts are zero-shot. Add 2-3 few-shot examples from the synthetic dataset:

```swift
let instructionsText = """
Classify the command into smart-home intent families.

Examples:
- "Turn on the light" → [.power]
- "Set temperature to 22" → [.temperature]
- "Dim the bedroom lamp to 50%" → [.brightness]

\(NLUInstructionContextProvider.intentFamilyContext(for: text))
"""
```

#### 3.2.2 Prompt A/B Testing Framework

```swift
struct PromptVariant: Identifiable {
    let id: String
    let systemInstructions: String
    let fewShotExamples: [String]
}

// Run each variant against the eval dataset
// Pick the one with highest accuracy
```

#### 3.2.3 `@Guide` Annotation Improvements

Review and tighten `@Guide` descriptions on all `@Generable` types. E.g.:

```swift
// Before
@Guide(description: "Selected device ID from the hydrated candidates only.")
public let targetDeviceID: String?

// After - more specific constraint
@Guide(description: "Exact device ID string from the hydrated candidate list. Must match one of the provided candidate IDs verbatim. Never generate a new ID.")
public let targetDeviceID: String?
```

### 3.3 LoRA Adapter Training

The existing `HomeAdapterTrainingExporter` already supports JSONL export. Extend it:

#### 3.3.1 Per-Task Adapter Training

```
Dataset split: 80% train / 10% validation / 10% holdout

Task-specific adapters:
1. adapter-draft-v1.mlpackage     → Draft generation
2. adapter-nlu-intent-v1.mlpackage → Intent family classification
3. adapter-nlu-slots-v1.mlpackage  → Slot extraction
```

#### 3.3.2 Training Data Pipeline

```
Registry → SyntheticDataGenerator → 50K output records
         → LLM reverse generation → 500K input-output pairs
         → HomeAdapterTrainingExporter.makeTaskJSONL()
         → Apple Create ML / fine-tuning pipeline
         → .mlpackage adapter files
```

#### 3.3.3 Adapter Evaluation Loop

```swift
// Use existing HomeAdapterTrainingExporter.evaluateHoldout()
let holdout = loadHoldoutCases()
let result = HomeAdapterTrainingExporter.evaluateHoldout(holdout)
assert(result.isPassing)
```

---

## Phase 4: CI/CD Accuracy Regression Suite

### 4.1 Automated Test Tiers

```
Tier 1 (Every PR):     100 golden test cases, must pass 95%+
Tier 2 (Nightly):      5,000 synthetic cases, accuracy dashboard
Tier 3 (Weekly):       Full 500K dataset, per-agent breakdown
```

### 4.2 Golden Test Cases

Hand-curated cases covering every device × intent combination:

```swift
// In Tests/HomeAutomationAgentTests/GoldenTests.swift
struct GoldenTestCase: Codable {
    let input: String
    let expectedDeviceID: String
    let expectedIntent: HomeAutomationIntent
    let expectedCapability: String
    let expectedCommand: String
    let tags: [String]
}
```

### 4.3 Accuracy Dashboard Metrics

```
┌──────────────────────────────────────────────────────┐
│  Agent Accuracy Dashboard (Nightly Run)              │
├──────────────────────────────────────────────────────┤
│  NLU.LanguageAgent:      97.2% (▲ +0.3%)            │
│  NLU.DomainAgent:        99.1% (━ 0.0%)             │
│  NLU.IntentFamilyAgent:  88.4% (▼ -1.2%) ⚠️         │
│  NLU.DeviceTypeAgent:    91.7% (▲ +2.1%)            │
│  NLU.SlotExtraction:     82.3% (▲ +0.8%)            │
│  NLU.RiskClassification: 96.8% (▲ +0.5%)            │
│  Candidates.Ranking:     84.1% (▲ +3.2%)            │
│  Draft.Generation:       78.9% (▲ +5.4%)            │
│  E2E.FullPipeline:       72.3% (▲ +8.1%)            │
└──────────────────────────────────────────────────────┘
```

---

## Implementation Roadmap

### Sprint 1 (Week 1-2): Data Generation Infrastructure

| Task | Priority | Effort |
|------|----------|--------|
| Build `SyntheticDataGenerator` from registry | P0 | 3 days |
| Write LLM prompt templates for reverse generation | P0 | 2 days |
| Generate 1,000 golden test cases (hand-verified) | P0 | 3 days |
| Implement JSONL import/export for test cases | P1 | 1 day |

### Sprint 2 (Week 3-4): Per-Agent Evaluation

| Task | Priority | Effort |
|------|----------|--------|
| Build `AgentEvaluationRunner` harness | P0 | 2 days |
| Implement NLU agent evaluators (6 agents) | P0 | 3 days |
| Implement Candidate agent evaluators | P0 | 2 days |
| Implement Draft agent evaluators | P0 | 2 days |
| Build confusion matrix reporting | P1 | 1 day |

### Sprint 3 (Week 5-6): Deterministic Tuning

| Task | Priority | Effort |
|------|----------|--------|
| Expand `AgentTextParser` keyword dictionaries | P0 | 3 days |
| Grid search `NLUModelCallPolicy` thresholds | P0 | 2 days |
| Optimize candidate scoring weights | P0 | 2 days |
| Add few-shot examples to FM prompts | P1 | 2 days |
| Tighten `@Guide` annotations | P1 | 1 day |

### Sprint 4 (Week 7-8): Adapter Training & CI

| Task | Priority | Effort |
|------|----------|--------|
| Generate 500K synthetic training pairs | P0 | 3 days |
| Train draft generation adapter | P0 | 3 days |
| Train NLU task adapters | P1 | 3 days |
| Set up CI golden test suite | P0 | 1 day |
| Build accuracy dashboard | P2 | 2 days |

---

## Quick Wins (Start Today)

> [!TIP]
> These can be done immediately without any infrastructure changes:

1. **Add 3-5 few-shot examples** to each NLU worker's system instructions
2. **Tighten `@Guide` descriptions** on `HomeCommandDraft` fields
3. **Expand `AgentTextParser` keyword maps** with 20-30 more patterns
4. **Lower `intentFamily` threshold** from 0.78 to 0.70 to let more cases use FM
5. **Add `DynamicGenerationSchema`** constraints to Draft generation (restrict `targetDeviceID` to actual candidate IDs)

---

## Key Insight: The Accuracy Bottleneck Chain

```
User Input → NLU (6 agents) → Candidates → Draft → Safety → Output
              ↓ 90%              ↓ 85%       ↓ 80%   ↓ 99%
              
E2E accuracy = 0.90 × 0.85 × 0.80 × 0.99 = 60.6%
```

> [!IMPORTANT]
> Even if each stage is 85-90% accurate, the **multiplicative effect** drops E2E to ~60%. This is why per-agent tuning is critical—improving any single agent by 5% lifts the entire pipeline.

**Priority order for maximum impact:**
1. **SlotExtraction** (lowest accuracy, feeds into candidate matching)
2. **IntentFamily** (misclassification cascades to wrong candidates)
3. **CandidateRanking** (wrong device = wrong everything)
4. **DraftGeneration** (final output quality)
