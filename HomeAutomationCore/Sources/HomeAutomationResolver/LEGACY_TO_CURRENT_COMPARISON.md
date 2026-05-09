# Legacy Resolver to Current Architecture Comparison

`HomeAutomationResolver` is the legacy resolver target. It is still useful for parity tests, migration safety, and historical reference, but the app now runs through `HomeAutomationOrchestrator` and `HomeAutomationAgents`.

This document compares each resolver type with the current architecture component that performs the same job.

## High-Level Shift

| Legacy resolver shape | Current architecture shape |
| --- | --- |
| One end-to-end resolver object owns most pipeline decisions. | `HomeCommandOrchestrator` owns lifecycle, while `AgentPlanner` and `AgentScheduler` plan and execute specialist agents. |
| Pipeline state is assembled inside resolver methods and helper stores. | `ResolutionContextStore` owns mutable state; agents return `ResolutionContextPatch` values. |
| Worker analysis is one partial-safe layer. | Six NLU agents run in parallel: `LanguageAgent`, `DomainAgent`, `IntentFamilyAgent`, `DeviceTypeAgent`, `SlotExtractionAgent`, and `RiskClassificationAgent`. |
| Candidate, draft, safety, and execution logic are direct resolver stages. | Each stage is a dedicated agent group: Candidates, Draft, Safety, Execution, Fallback, and Response. |
| Events and metrics are resolver-level counters and timers. | `AgentEventBus`, `AgentTraceEntry`, `OrchestratorMetrics`, and circuit breaker status provide per-agent observability. |

## Type-by-Type Comparison

### Pipeline Coordination

| Legacy type | What it does | Current equivalent |
| --- | --- | --- |
| `LegacyHomeCommandResolver` | Original top-level resolver. It receives text, streams events, runs rule precheck, checks Foundation Models availability, coordinates worker analysis, candidate ranking, instruction creation, draft generation, validation, execution, fallback, and metrics. | `HomeCommandOrchestrator` owns the command lifecycle. `AgentPlanner` chooses fallback-only or full model plans. `AgentScheduler` runs sequential and parallel phases. `ResolutionContextStore` holds evolving state. |
| `LegacyPipelineOutput` | Private value pairing a resolver result with metrics inside the timed Foundation Models path. | There is no direct object. The current path accumulates context in `ResolutionContextStore`, then `HomeCommandOrchestrator` assembles `HomeAutomationResolverResult` and stores `OrchestratorMetrics`. |
| `LegacyEventCounter` | Private counter for legacy event totals. | Replaced by per-agent events/traces: `AgentEventBus`, `OrchestratorPipelineEvent`, `AgentTraceEntry`, and `OrchestratorMetrics.agentStatuses`. |
| `LegacyPipelineStage` | Enum of fixed legacy pipeline stage names. | Replaced by agent IDs and stage strings emitted through `OrchestratorPipelineEvent`. The plan is represented by `AgentTask`, `AgentPhase`, and `AgentExecutionPlan`. |
| `LegacyPipelineEvent` | Legacy timeline event for UI streaming. | `OrchestratorPipelineEvent` provides run ID, stage, optional agent ID, status, and detail. |
| `LegacyResolverUpdate` | Stream item enum: legacy event or final result. | `OrchestratorUpdate` is the current stream item enum: event or final result. |
| `public extension LegacyHomeCommandResolver` in `LegacyPipelineEvents.swift` | Convenience stream API around the legacy resolver. | `HomeCommandOrchestrator.resolveStream` is the app-facing stream API. |

### Worker and NLU Analysis

| Legacy type | What it does | Current equivalent |
| --- | --- | --- |
| `LegacyPartialWorkerOverrides` | Test injection container for replacing language, domain, intent, device type, slot, and risk workers. | Replaced by per-agent worker-session injection and each NLU agent's closure-based test initializer. |
| `LegacyPartialSafeWorkerSessionLayer` | Runs all NLU worker tasks concurrently and falls back per worker when a model call fails. Produces a combined `HomeResolutionState`. | Split into six specialist NLU agents, each with its own worker session: `LanguageAgentWorkerSession`, `DomainAgentWorkerSession`, `IntentFamilyAgentWorkerSession`, `DeviceTypeAgentWorkerSession`, `SlotExtractionAgentWorkerSession`, and `RiskClassificationAgentWorkerSession`. `AgentPlanner` schedules the agents in one parallel phase, and `ResolutionContextStore.apply` combines their patches into `resolutionState`. |
| `LegacyTimeoutError` | Error emitted by legacy timeout helper. | No direct current equivalent. Agents expose `timeoutNanoseconds`, but current resilience is primarily circuit breakers, fail-closed mandatory gates, and fallback behavior. |
| `LegacyTimeout` | Helper that races work against a timeout using task groups and cancellation. | No direct one-to-one replacement in `AgentScheduler`; scheduling currently focuses on parallelism, circuit breakers, and fail-closed policy. |

### Deterministic Parsing and Rule Fallback

| Legacy type | What it does | Current equivalent |
| --- | --- | --- |
| `LegacyRuleBasedResolver` | Deterministic resolver used for model-unavailable and fallback paths. It parses text, scores devices, builds drafts, validates, plans, and optionally executes low-risk commands. | `AgentRuleBasedResolver` contains the equivalent deterministic resolver and is run by `RuleFallbackAgent` in the fallback-only plan. |
| `LegacyTextParser` | Deterministic multilingual parser for fallback state, rooms, device types, numbers, and mode candidates. | `AgentTextParser` is the extracted current parser used by fallback agents and the per-agent NLU worker-session fallbacks. |
| `String.legacyNormalizedHomeTokenString` | Legacy string normalization for multilingual and token matching. | `String.agentNormalizedHomeTokenString` in the agents fallback parser provides the current normalization. |
| `ScoredDevice` | Private deterministic device ranking record in rule fallback. | `AgentScoredDevice` in `FallbackRuleTypes.swift`. |
| `DraftIntent` | Private normalized intent/capability/command package before creating a draft. | `AgentDraftIntent` in `FallbackRuleTypes.swift`. |
| `CapabilityCommand` | Private capability-command preference used by rule intent matching. | `AgentCapabilityCommand` in `FallbackRuleTypes.swift`. |
| `RuleIntent` | Private parsed deterministic intent, hints, values, and relative-change metadata. | `AgentRuleIntent` plus `AgentSemanticHints` in `FallbackRuleTypes.swift`. |

### Candidate Selection

| Legacy type | What it does | Current equivalent |
| --- | --- | --- |
| `LegacyCandidateResolverMetrics` | Stores last candidate strategy and counts for diagnostics. | `HomeCandidateResolverMetrics` stores current candidate strategy diagnostics. `OrchestratorCandidateMetrics` captures final run-level candidate metrics. |
| `LegacyCandidateResolver` | Selects candidates by direct deterministic ranking, model selection, or shard selection for large candidate lists. | `HomeCandidateResolverSupport` implements the ranking and shard logic. It is used by `CandidateRankingAgent` and `CandidateShardAgent`. |
| `LegacyCandidateContextStore` | Actor cache for retrieved candidates and selected-candidate hydration. | `ResolutionContextStore` stores `retrievedCandidates`, `selectedCandidateIDs`, `aggregation`, and `hydratedCandidates`. `CandidateHydrationAgent` performs final hydration. |
| `LegacyDeviceRegistryProviding` | Abstraction over the device registry used by legacy code. | Current agents use `MockHomeDeviceRegistry` directly through factory wiring and input adapters. The common domain APIs still live in `HomeAutomationCore`. |
| `extension MockHomeDeviceRegistry: LegacyDeviceRegistryProviding` | Makes the mock registry usable through the legacy abstraction. | No current equivalent is needed because the orchestrator factory wires the concrete registry into candidate, tool, fallback, and execution components. |

### Instruction and Tooling

| Legacy type | What it does | Current equivalent |
| --- | --- | --- |
| `LegacyInstructionSetFactory` | Builds the prompt, instruction text, language rules, and tool list from final resolution input. | `AgentInstructionSetFactory` builds `HomeModelInstructionPackage` for `InstructionComposerAgent`. It also integrates RAG-selected context. |
| `LegacyFindDevicesTool` | Foundation Models tool for device search. | `AgentFindDevicesTool`. |
| `LegacyGetCapabilitiesTool` | Foundation Models tool for capability, command, enum, range, and risk lookup. | `AgentGetCapabilitiesTool`. |
| `LegacyGetDeviceStateTool` | Foundation Models tool for current device state lookup. | `AgentGetDeviceStateTool`. |
| `LegacyGetSupportedModesTool` | Foundation Models tool for supported modes and enum values. | `AgentGetSupportedModesTool`. |
| `LegacyValidateCommandTool` | Foundation Models tool for command support and risk hints. | `AgentValidateCommandTool`. |
| `LegacyHydrateCandidatesTool` | Foundation Models tool for candidate hydration. | `AgentHydrateCandidatesTool`. |
| `LegacyToolProvider` | Selects which tools are available to draft generation. | `AgentToolProvider`. |
| `LegacyToolFormatting` | JSON-lines formatting helper for tool output. | `AgentToolFormatting`. |

### Draft Generation

| Legacy type | What it does | Current equivalent |
| --- | --- | --- |
| `LegacyDraftAttemptReport` | Diagnostic record for one draft-generation attempt. | `AgentDraftAttemptReport`. |
| `LegacyDraftResolutionReport` | Aggregate diagnostic report across draft attempts. | `AgentDraftResolutionReport`. |
| `LegacyDraftResolutionOutput` | Draft plus draft-resolution report. | `AgentDraftResolutionOutput`. |
| `LegacyDraftResolverMetrics` | Stores the latest draft report. | `AgentDraftResolverMetrics`, with run-level visibility through orchestrator metrics. |
| `LegacyDraftResolver` | Retry wrapper that tries base/full, adapter/full, base/simplified, and adapter/simplified packages. | `AgentDraftResolver` is the extracted retry wrapper. `DraftGenerationAgent` runs the primary draft path; `DraftRepairAgent` handles repair/lower-confidence recovery. |
| `LegacyDraftPackageAttempt` | Private description of one draft attempt. | `AgentDraftPackageAttempt` in the current draft resolver. |

### Safety and Execution

| Legacy type | What it does | Current equivalent |
| --- | --- | --- |
| `LegacyCommandValidator` | Deterministic validator for target, capability, command, risk, parameters, and execution eligibility. | `AgentCommandValidator`, wrapped by mandatory safety agents: `SafetyValidationAgent`, `ParameterValidationAgent`, and `ConfirmationPolicyAgent`. |
| `LegacyExecutionPlanner` | Converts valid drafts into execution plans, including read-plus-command plans for relative changes. | `AgentExecutionPlanner`, wrapped by mandatory `ExecutionPlanningAgent`. |
| `LegacyPlanExecutor` | Executes allowed low-risk command steps against the mock registry. | `AgentPlanExecutor`, wrapped by mandatory `MockExecutionAgent`. |

### Bixby Fallback

| Legacy type | What it does | Current equivalent |
| --- | --- | --- |
| `LegacyBixbyDraftMatch` | Holds a Bixby-derived draft match, matched device, source command, and score. | `AgentBixbyDraftMatch`. |
| `LegacyBixbyFallbackMapper` | Maps Bixby catalog utterances and source capabilities into local command drafts. | `AgentBixbyFallbackMapper`, run through `BixbyFallbackAgent`. |
| `LegacyBixbyCommandMapping` | Private normalized mapping record for Bixby command matching. | `AgentBixbyCommandMapping`. |

### Metrics and Observability

| Legacy type | What it does | Current equivalent |
| --- | --- | --- |
| `LegacyResolutionMetrics` | Legacy metrics payload with model/fallback flags, timings, candidate strategy, confidence, risk, adapter diagnostics, and stage durations. | `OrchestratorMetrics`, `OrchestratorContextMetrics`, `OrchestratorSafetyMetrics`, and `OrchestratorCandidateMetrics`. |
| `LegacyMetricsCollector` | Actor storing and serializing the latest legacy metrics. | `OrchestratorMetricsCollector`. |
| `LegacyStageTimer` | Small helper for measuring elapsed stage durations. | Current metrics derive timings from `AgentTraceEntry` start/end times plus orchestrator run timestamps. |

### Adapter, Export, and Deployment Support

| Legacy type | What it does | Current equivalent |
| --- | --- | --- |
| `LegacyAdapterTrainingExample` | Compact generated-example row for adapter training export. | No current production equivalent. Generated examples now primarily support RAG retrieval and tests through `HomeAutomationKnowledgeBase`, `DocumentChunker`, and `CommandExampleAgent`. |
| `LegacyAdapterTrainingExporter` | Exports generated dataset examples as values or JSONL. | No current agent equivalent. This remains legacy/offline tooling. |
| `LegacyAdapterCompatibility` | Expected and installed adapter compatibility record. | No current orchestrator component. Adapter diagnostics are not central to the agent runtime. |
| `LegacyDeploymentChecklist` | Static checklist for running the legacy resolver safely. | Safety rules are now encoded in `OrchestratorPolicyEngine`, mandatory safety agents, and architecture documentation. |

## Current Architecture Components With No Legacy Peer

These are new capabilities introduced by the orchestrator/agent architecture rather than direct ports of legacy classes.

| Current component | Why it exists now |
| --- | --- |
| `AgentID`, `AgentCapability`, `HomeAgent`, `AnyHomeAgent` | Provide stable identity, capability metadata, and type-erased scheduling for specialist agents. |
| `AgentPlanner`, `AgentTask`, `AgentPhase`, `AgentExecutionPlan` | Make the command flow explicit as sequential and parallel phases. |
| `AgentScheduler` | Centralizes execution, patch application, event emission, circuit checks, and mandatory-gate fail-closed behavior. |
| `ResolutionContext`, `ResolutionContextPatch`, `ResolutionContextStore` | Replace in-method mutable pipeline state with typed context snapshots and patches. |
| `CircuitBreakerRegistry` and `AgentCircuitBreaker` | Add per-agent resilience and skip/fail-closed behavior. |
| `ConversationMemory` and `MemoryHint` | Add prior-turn hints for follow-up commands without bypassing validation. |
| `CapabilityKnowledgeAgent`, `BixbyKnowledgeAgent`, `CommandExampleAgent`, `AgentRAGSupport` | Add RAG-backed context selection before candidate ranking and draft generation. |
| `KnowledgeIndexer`, `ContextRetriever`, `VectorStore`, `VectorIndexCache` | Provide reusable retrieval infrastructure and disk-backed vector-index persistence. |
| `ClarificationAgent` and `ResultSummaryAgent` | Separate user-facing response shaping from core resolution logic. |

## Migration Guidance

- New production behavior should be added to `HomeAutomationAgents` or `HomeAutomationOrchestrator`, not to `HomeAutomationResolver`.
- Keep `HomeAutomationResolver` changes limited to parity tests, regression coverage, and compatibility cleanup.
- When touching legacy code, check whether the current equivalent already exists in agents. If it does, prefer updating the current equivalent first and using resolver tests only as a safety reference.
- If a legacy helper has no current equivalent, decide whether it is still useful offline tooling or whether it should be retired in a separate cleanup.
