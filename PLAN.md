# Cleanup Plan For A Lean Graph-Only Agent Architecture

## Summary

Clean the project by removing inactive compatibility NLU agents, deleting their tests, consolidating docs around the current graph architecture, removing scratch/unhandled source files, and splitting the largest orchestration files into smaller modules. The final state should reflect the active runtime only: root routing produces operation/language/domain, direct command NLU uses `SemanticNLUAgent + SlotExtractionAgent + RiskClassificationAgent`, and no deleted agents remain in registry, manifests, docs, or tests.

## Key API / Interface Changes

- Remove public standalone compatibility agents:
  - `LanguageAgent`, `DomainAgent`, `IntentFamilyAgent`, `DeviceTypeAgent`
  - their worker sessions
  - their `AgentID` constants: `.language`, `.domain`, `.intentFamily`, `.deviceType`
- Keep context/result fields:
  - `language`, `domain`, `intent`, `deviceType`
  - `HomeLanguageDetectionResult`, `HomeDomainClassificationResult`, `HomeIntentFamilyResult`, `HomeDeviceTypeResult`
- Keep active fused types:
  - `HomeOperationRoutingResult`
  - `HomeSemanticNLUResult`
  - `SemanticNLUAgent`
  - `SemanticNLUWorkerSession`
- Move `AvailableDeviceTypesTool` into shared semantic NLU tooling before deleting the old `DeviceType` folder.

## Phase 1 — Baseline And Active-Agent Inventory

**What to do**
- Record current passing baseline before cleanup.
- Define active vs unused agents from graph reality, not registry history.

**How to do it**
- Treat these graphs as source of truth:
  - `GraphPlanner.rootRoutingGraph()`
  - `GraphPlanner.directCommandGraph()`
  - `GraphPlanner.automationCreationGraph()`
  - `GraphPlanner.fallbackGraph()`
  - `GraphPlanner.unsupportedGraph()`
- Mark these as unused and scheduled for deletion:
  - `LanguageAgent`
  - `DomainAgent`
  - `IntentFamilyAgent`
  - `DeviceTypeAgent`
- Run:
  - `cd HomeAutomationCore`
  - `swift build`
  - `swift test`

**Acceptance criteria**
- Current tests pass before deletion begins.
- Cleanup branch has a written checklist of active graph nodes.
- No implementation decisions remain about which NLU agents are unused.

## Phase 2 — Source Hygiene And SwiftPM Warning Cleanup

**What to do**
- Remove scratch files and package-warning sources.

**How to do it**
- Delete:
  - `HomeAutomationCore/Sources/test.swift`
  - `HomeAutomationCore/Sources/test_operation.swift`
- Move Markdown docs out of `HomeAutomationCore/Sources` into root docs:
  - `HomeAutomationCore/Sources/HomeAutomationAgents/README.md` -> `Docs/HomeAutomationAgents.md`
  - `HomeAutomationCore/Sources/HomeAutomationOrchestrator/README.md` -> `Docs/HomeAutomationOrchestrator.md`
  - `HomeAutomationCore/Sources/HomeAutomationOrchestrator/OrchestratorArchitecture.md` -> `Docs/OrchestratorArchitecture.md`
  - `HomeAutomationCore/Sources/HomeAutomationCore/README.md` -> `Docs/HomeAutomationCore.md`
  - `HomeAutomationCore/Sources/HomeAutomationRAG/README.md` -> `Docs/HomeAutomationRAG.md`
  - `HomeAutomationCore/Sources/HomeAutomationRAG/RAG_Implementation.md` -> `Docs/RAG_Implementation.md`
- Update root `README.md` and `Architecture.md` links to point to `Docs/`.
- Remove tracked `.DS_Store` files from version control and ensure `.gitignore` contains `.DS_Store`.

**Acceptance criteria**
- `swift build` no longer reports unhandled Markdown/source warnings.
- `find HomeAutomationCore/Sources -name 'test*.swift'` returns nothing.
- `find HomeAutomationCore/Sources -name '*.md'` returns nothing.
- `.DS_Store` is ignored and not tracked.

## Phase 3 — Preserve Shared Device-Type Tool

**What to do**
- Move canonical device type lookup out of the soon-deleted `DeviceType` agent folder.

**How to do it**
- Move `AvailableDeviceTypesTool.swift` and related catalog entry types to:
  - `HomeAutomationCore/Sources/HomeAutomationAgents/NLU/Shared/Tools/AvailableDeviceTypesTool.swift`
- Update `SemanticNLUWorkerSession` to use the new location.
- Ensure no active code imports or references `NLU/DeviceType`.

**Acceptance criteria**
- `SemanticNLUWorkerSession` still builds and uses canonical device type IDs.
- `rg "NLU/DeviceType|DeviceTypeAgentWorkerSession" HomeAutomationCore/Sources` only finds files scheduled for deletion before Phase 4.

## Phase 4 — Delete Unused NLU Agents

**What to do**
- Remove inactive standalone NLU agents and worker sessions.

**How to do it**
- Delete folders:
  - `HomeAutomationCore/Sources/HomeAutomationAgents/NLU/Language`
  - `HomeAutomationCore/Sources/HomeAutomationAgents/NLU/Domain`
  - `HomeAutomationCore/Sources/HomeAutomationAgents/NLU/IntentFamily`
  - `HomeAutomationCore/Sources/HomeAutomationAgents/NLU/DeviceType`
- Remove from `AgentID`:
  - `.language`
  - `.domain`
  - `.intentFamily`
  - `.deviceType`
- Remove their cases from `AgentManifestDefaults`.
- Remove their contextual registrations from `DefaultAgentRegistryFactory`.
- Change the NLU module registration to only:
  - `.semanticNLU`
  - `.slotExtraction`
  - `.riskClassification`

**Acceptance criteria**
- `rg "LanguageAgent|DomainAgent|IntentFamilyAgent|DeviceTypeAgent" HomeAutomationCore/Sources` returns nothing except intentionally migrated docs if any.
- `rg "AgentID\\.language|AgentID\\.domain|AgentID\\.intentFamily|AgentID\\.deviceType" HomeAutomationCore/Sources` returns nothing.
- `GraphPlanner.directCommandGraph()` remains:
  - entry nodes: `semanticNLU`, `slotExtraction`, `riskClassification`.

## Phase 5 — Delete Obsolete Tests And Replace With Active-Architecture Tests

**What to do**
- Remove tests that only protect deleted agents.
- Add/keep tests for active fused behavior.

**How to do it**
- Delete or rewrite standalone-agent tests in:
  - `Phase2AgentTests`
  - `FMFirstMigrationTests`
  - `DeviceTypeAgentTests`
  - `Phase5RAGIntegrationTests`
- Remove tests for:
  - `LanguageAgent`
  - `DomainAgent`
  - `IntentFamilyAgent`
  - `DeviceTypeAgent`
  - `LanguageAgentWorkerSession`
  - `DomainAgentWorkerSession`
  - `IntentFamilyAgentWorkerSession`
  - `DeviceTypeAgentWorkerSession`
- Replace with tests for:
  - `OperationDetectionAgent` produces operation, language, and domain.
  - `OperationDetectionWorkerSession` preserves automation-creation safety preference.
  - `SemanticNLUAgent` produces intent and device type together.
  - `SemanticNLUWorkerSession` falls back deterministically when FM unavailable.
  - `SemanticNLUWorkerSession` uses canonical device type tool.
  - Direct command graph excludes deleted agent IDs.
  - Registry contains no deleted NLU agents.
  - Graph validator accepts all default graphs.

**Acceptance criteria**
- No test imports or instantiates deleted agents.
- Test names describe root routing and semantic NLU, not the old six-agent NLU stack.
- `swift test` passes.

## Phase 6 — Clean Training / Evaluation Task Records

**What to do**
- Update any evaluation/export path that still assumes separate language/domain/intent/device agents.

**How to do it**
- Replace old per-agent NLU task records with active task records:
  - `operationRouting`
  - `semanticNLU`
  - `slotExtraction`
  - `riskClassification`
- Keep confidence fields in telemetry/evaluation:
  - `operationConfidence`
  - `languageConfidence`
  - `domainConfidence`
  - `intentConfidence`
  - `deviceTypeConfidence`
  - `slotExtractionConfidence`
  - `riskClassificationConfidence`
- Update adapter-training tests so they assert the new task names.

**Acceptance criteria**
- Evaluation output no longer advertises deleted agents as active tasks.
- Metrics still expose language/domain/intent/device confidence fields.
- Existing JSONL telemetry remains parseable.

## Phase 7 — Split Registry And Adapter Assembly

**What to do**
- Break up `ContextualAgentAdapters.swift`.

**How to do it**
- Extract without behavior changes:
  - `DefaultAgentRegistryFactory.swift`
  - `AgentModuleAssembly.swift`
  - `AgentInputBuilders.swift`
  - `AgentPatchMappers.swift`
  - `AgentTelemetryPayloads.swift`
  - `AutomationAgentAdapters.swift`
- Keep `ContextualHomeAgent` in a focused file.
- Keep all patch keys and context field names unchanged.

**Acceptance criteria**
- No registry/adapter file remains over roughly 500 lines.
- Registry tests still pass.
- Graph behavior is unchanged.

## Phase 8 — Split Graph Scheduler Internals

**What to do**
- Reduce `GraphScheduler.swift` into smaller runtime components.

**How to do it**
- Keep `GraphScheduler` as the public facade.
- Extract:
  - `GraphReadinessEngine`
  - `GraphNodeExecutionLoop`
  - `GraphPatchCommitter`
  - `GraphTransitionCoordinator`
  - `GraphCheckpointCoordinator`
  - `GraphFailurePolicy`
- Preserve event-driven readiness and fail-closed safety behavior.

**Acceptance criteria**
- Existing scheduler tests pass.
- Safety gate tests still fail closed.
- Transition tests still reject unsafe transitions.
- Checkpoint/resume tests still pass.

## Phase 9 — Split Large Domain And Parser Files

**What to do**
- Reduce broad support files into responsibility-focused files.

**How to do it**
- Split `HomeAutomationModels.swift` into:
  - `HomeAutomationEnums.swift`
  - `HomeNLUModels.swift`
  - `HomeCommandDraftModels.swift`
  - `HomeResolutionModels.swift`
  - `HomeCandidateModels.swift`
- Split `CandidateResolverSupport.swift` into:
  - candidate filtering
  - prompt building
  - evidence formatting
  - ranking fallback heuristics
- Split `AutomationPatternParser.swift` into:
  - action extraction
  - trigger extraction
  - condition parsing
  - schedule parsing
  - normalization utilities

**Acceptance criteria**
- Public model names remain available.
- No behavior changes.
- `swift test` passes after each split.

## Phase 10 — Documentation Truth Cleanup

**What to do**
- Remove references to deleted agents and old six-agent NLU topology.

**How to do it**
- Update:
  - root `README.md`
  - `Architecture.md`
  - docs moved under `Docs/`
  - `implementation_plan.md`
  - `improvement_plan.md`
  - `multi_agent_system_deep_review.md`
- Replace old wording:
  - “6 parallel NLU agents”
  - “LanguageAgent/DomainAgent/IntentFamilyAgent/DeviceTypeAgent active”
- With current wording:
  - root routing produces operation/language/domain
  - direct graph runs `SemanticNLUAgent`, `SlotExtractionAgent`, `RiskClassificationAgent`

**Acceptance criteria**
- `rg "6 NLU|six NLU|parallel NLU agents|LanguageAgent|DomainAgent|IntentFamilyAgent|DeviceTypeAgent" .` returns no active-architecture claims.
- Historical docs, if kept, are clearly under `Docs/Historical/`.

## Phase 11 — Final Verification

**What to run**
```bash
cd /Users/samin/Downloads/untitled\ folder/HomeAutomation/HomeAutomationCore
swift build
swift test
```

**Search checks**
```bash
rg "LanguageAgent|DomainAgent|IntentFamilyAgent|DeviceTypeAgent" /Users/samin/Downloads/untitled\ folder/HomeAutomation
rg "AgentID\\.language|AgentID\\.domain|AgentID\\.intentFamily|AgentID\\.deviceType" /Users/samin/Downloads/untitled\ folder/HomeAutomation
rg "6 NLU|six NLU|parallel NLU agents" /Users/samin/Downloads/untitled\ folder/HomeAutomation
find /Users/samin/Downloads/untitled\ folder/HomeAutomation/HomeAutomationCore/Sources -name 'test*.swift' -o -name '*.md' -o -name '.DS_Store'
```

**Acceptance criteria**
- Build passes without SwiftPM unhandled-file warnings.
- Tests pass.
- Deleted agents and deleted agent IDs are gone from source and tests.
- Root routing and semantic NLU tests cover the deleted behavior.
- Docs describe only the cleaned graph-current architecture.

## Assumptions

- Source-breaking cleanup is allowed.
- Removing unused agents means deleting public agent types, worker sessions, registry entries, manifests, tests, and active-doc references.
- Context result models stay because active fused agents still produce their fields.
- `AvailableDeviceTypesTool` is shared active infrastructure, not unused.
- Historical docs may be kept only if moved under `Docs/Historical/` and clearly marked historical.
