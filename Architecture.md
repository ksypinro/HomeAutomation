# Unified HomeAutomation Architecture

This document is the canonical architecture reference for `HomeAutomation`. It merges the historical resolver architecture from `ARCHITECTURE.md` with the implemented multi-agent/orchestrator design, and it describes both the high-level runtime shape and the low-level component responsibilities.

## 1. Executive Summary

`HomeAutomation` is a SwiftUI demo app that resolves natural-language smart-home commands into structured home-automation actions. The app is now orchestrator-first:

1. The SwiftUI app collects a command and streams orchestrator updates.
2. `HomeCommandOrchestrator` creates a `ResolutionContext`, plans work, schedules agents, records metrics, and returns a `HomeAutomationResolverResult`.
3. `HomeAutomationAgents` contains specialized agents for NLU, knowledge lookup, candidate selection, draft generation, safety validation, execution planning, fallback, and response formatting.
4. `HomeAutomationRAG` retrieves compact, relevant context from canonical catalogs, examples, Bixby commands, and device records.
5. `HomeAutomationCore` remains the source of truth for models, registries, catalogs, policies, generated resources, and Foundation Models support.
6. `HomeAutomationResolver` keeps the legacy resolver for compatibility and parity testing.

The central safety rule is that model output and memory hints are advisory. Deterministic validation, parameter checks, confirmation policy, and execution planning must pass before a command can mutate the mock device registry.

## 2. Design Principles

1. Models suggest; agents specialize; orchestrator policy and deterministic safety agents decide.
2. Canonical catalogs stay authoritative for capabilities, supported commands, enum values, numeric ranges, Bixby mappings, and risk.
3. RAG selects relevant context; it does not replace source-of-truth registries.
4. Each agent is independently testable and observable.
5. Context flows through typed patches instead of shared mutable state.
6. Mandatory safety gates fail closed to confirmation, clarification, ready-without-mutation, or unsupported outcomes.
7. Conversation memory provides low-priority hints only and never grants execution authority.
8. The legacy resolver remains isolated behind its own package target.

## 3. High-Level Architecture

```mermaid
flowchart TB
    User["User"]
    App["SwiftUI App Target<br/>HomeAutomation"]
    View["HomeAutomationView"]
    VM["HomeAutomationViewModel"]
    Orchestrator["HomeCommandOrchestrator"]

    subgraph OrchestratorLayer["HomeAutomationOrchestrator"]
        Planner["AgentPlanner"]
        Scheduler["AgentScheduler"]
        Registry["AgentRegistry"]
        ContextStore["ResolutionContextStore"]
        EventBus["AgentEventBus"]
        Metrics["OrchestratorMetricsCollector"]
        Policy["OrchestratorPolicyEngine"]
        Breakers["CircuitBreakerRegistry"]
        Memory["ConversationMemory"]
    end

    subgraph AgentLayer["HomeAutomationAgents — 26 Specialist Agents"]
        subgraph NLU["NLU Agents"]
            LanguageAgent["LanguageAgent"]
            DomainAgent["DomainAgent"]
            IntentFamilyAgent["IntentFamilyAgent"]
            DeviceTypeAgent["DeviceTypeAgent"]
            SlotExtractionAgent["SlotExtractionAgent"]
            RiskClassificationAgent["RiskClassificationAgent"]
        end
        subgraph Knowledge["Knowledge Agents"]
            CapabilityKnowledgeAgent["CapabilityKnowledgeAgent"]
            BixbyKnowledgeAgent["BixbyKnowledgeAgent"]
            CommandExampleAgent["CommandExampleAgent"]
        end
        subgraph Candidates["Candidate Agents"]
            CandidateRetrievalAgent["CandidateRetrievalAgent"]
            CandidateRankingAgent["CandidateRankingAgent"]
            CandidateShardAgent["CandidateShardAgent"]
            CandidateHydrationAgent["CandidateHydrationAgent"]
        end
        subgraph Draft["Draft Agents"]
            InstructionComposerAgent["InstructionComposerAgent"]
            DraftGenerationAgent["DraftGenerationAgent"]
            DraftRepairAgent["DraftRepairAgent"]
        end
        subgraph Safety["Safety Agents"]
            SafetyValidationAgent["SafetyValidationAgent"]
            ParameterValidationAgent["ParameterValidationAgent"]
            ConfirmationPolicyAgent["ConfirmationPolicyAgent"]
        end
        subgraph Execution["Execution Agents"]
            ExecutionPlanningAgent["ExecutionPlanningAgent"]
            MockExecutionAgent["MockExecutionAgent"]
        end
        subgraph Fallback["Fallback Agents"]
            RuleFallbackAgent["RuleFallbackAgent"]
            BixbyFallbackAgent["BixbyFallbackAgent"]
            UnsupportedCommandAgent["UnsupportedCommandAgent"]
        end
        subgraph Response["Response Agents"]
            ClarificationAgent["ClarificationAgent"]
            ResultSummaryAgent["ResultSummaryAgent"]
        end
    end

    subgraph RAGLayer["HomeAutomationRAG"]
        Indexer["KnowledgeIndexer"]
        Retriever["ContextRetriever"]
        Store["VectorStore"]
        Embedder["EmbeddingProvider"]
        Chunker["DocumentChunker"]
    end

    subgraph CoreLayer["HomeAutomationCore"]
        Models["Domain Models"]
        DeviceRegistry["MockHomeDeviceRegistry"]
        CapabilityRegistry["HomeCapabilityRegistry"]
        KnowledgeBase["HomeAutomationKnowledgeBase"]
        BixbyCatalog["HomeBixbyCommandCatalog"]
        SafetyPolicy["HomeRiskPolicy + HomeParameterValidator"]
        FoundationModels["Foundation Models Session Support"]
    end

    User --> App --> View --> VM --> Orchestrator
    Orchestrator --> Planner
    Orchestrator --> Scheduler
    Orchestrator --> ContextStore
    Orchestrator --> EventBus
    Orchestrator --> Metrics
    Orchestrator --> Policy
    Orchestrator --> Breakers
    Orchestrator --> Memory
    Scheduler --> Registry
    Registry --> AgentLayer
    CapabilityKnowledgeAgent --> RAGLayer
    BixbyKnowledgeAgent --> RAGLayer
    CommandExampleAgent --> RAGLayer
    CandidateRetrievalAgent --> RAGLayer
    NLU --> RAGLayer
    AgentLayer --> CoreLayer
    Indexer --> Chunker --> Embedder --> Store
    Retriever --> Store
    CoreLayer --> Indexer
    SafetyValidationAgent --> SafetyPolicy
    ParameterValidationAgent --> SafetyPolicy
    ConfirmationPolicyAgent --> SafetyPolicy
    ExecutionPlanningAgent --> DeviceRegistry
    MockExecutionAgent --> DeviceRegistry
```

## 4. Package and Dependency Architecture

```mermaid
flowchart LR
    Xcode["HomeAutomation.xcodeproj"]
    AppTarget["HomeAutomation App Target"]
    Package["Swift Package<br/>HomeAutomationCore"]

    Core["HomeAutomationCore"]
    RAG["HomeAutomationRAG"]
    Agents["HomeAutomationAgents"]
    Orchestrator["HomeAutomationOrchestrator"]
    Resolver["HomeAutomationResolver"]

    Xcode --> AppTarget
    AppTarget --> Core
    AppTarget --> Orchestrator

    Package --> Core
    Package --> RAG
    Package --> Agents
    Package --> Orchestrator
    Package --> Resolver

    RAG --> Core
    Agents --> Core
    Agents --> RAG
    Orchestrator --> Core
    Orchestrator --> RAG
    Orchestrator --> Agents
    Resolver --> Core
```

Dependency direction:

```text
HomeAutomationRAG -> HomeAutomationCore
HomeAutomationAgents -> HomeAutomationCore + HomeAutomationRAG
HomeAutomationOrchestrator -> HomeAutomationCore + HomeAutomationRAG + HomeAutomationAgents
HomeAutomationResolver -> HomeAutomationCore
HomeAutomation app target -> HomeAutomationCore + HomeAutomationOrchestrator
```

`HomeAutomationResolver` is retained for legacy parity and fallback comparison. New orchestrator code does not depend on that target.

## 5. Detailed Command Flow

```mermaid
flowchart TD
    A["User enters command"] --> B["HomeAutomationViewModel.resolveCommand"]
    B --> C["HomeCommandOrchestrator.resolveStream"]
    C --> D["Create CommandRequest and ResolutionContextStore"]
    D --> E["Attach ConversationMemory hint when text references prior context"]
    E --> F["Emit input event"]
    F --> G{"Foundation Models available?"}

    G -->|No| H["Fallback-only plan"]
    H --> H1["RuleFallbackAgent"]
    H1 --> H2["BixbyFallbackAgent"]
    H2 --> H3["UnsupportedCommandAgent if needed"]

    G -->|Yes| I["Full agent plan"]
    I --> J["Run NLU agents in parallel"]
    J --> K["Merge language, domain, intent, device type, slot, and risk patches"]
    K --> L["Run knowledge agents and candidate retrieval in parallel"]
    L --> M["CandidateRankingAgent"]
    M --> N{"Needs clarification?"}
    N -->|Yes| O["ClarificationAgent or clarification resolution"]
    N -->|No| P["CandidateHydrationAgent"]
    P --> Q["InstructionComposerAgent"]
    Q --> R["DraftGenerationAgent"]
    R --> S["SafetyValidationAgent"]
    S --> T["ParameterValidationAgent"]
    T --> U["ConfirmationPolicyAgent"]
    U --> V["ExecutionPlanningAgent"]
    V --> W{"Can execute low-risk commands?"}
    W -->|Yes| X["MockExecutionAgent"]
    W -->|No| Y["Return ready/confirmation/query result"]

    H3 --> Z["Assemble resolver result"]
    O --> Z
    X --> Z
    Y --> Z
    Z --> AA["Store metrics, append memory turn, emit outcome"]
```

## 6. Runtime Data Flow

```mermaid
sequenceDiagram
    participant User
    participant View as HomeAutomationView
    participant VM as HomeAutomationViewModel
    participant Orch as HomeCommandOrchestrator
    participant Scheduler as AgentScheduler
    participant Agents as Specialist Agents
    participant Core as Core Registries and Policies
    participant RAG as ContextRetriever
    participant Metrics as OrchestratorMetricsCollector

    User->>View: Submit natural-language command
    View->>VM: resolveCommand()
    VM->>Orch: resolveStream(text, executeLowRiskCommands)
    Orch-->>VM: OrchestratorPipelineEvent(input)
    Orch->>Scheduler: execute(AgentExecutionPlan)
    Scheduler->>Agents: Run sequential/parallel agent phases
    Agents->>RAG: Retrieve relevant examples, capabilities, devices, or Bixby context
    Agents->>Core: Hydrate canonical devices, capabilities, commands, risk, and parameters
    Agents-->>Scheduler: ResolutionContextPatch or terminal result
    Scheduler-->>Orch: Final exit or completed plan
    Orch->>Metrics: store(OrchestratorMetrics)
    Orch-->>VM: OrchestratorPipelineEvent(outcome)
    Orch-->>VM: HomeAutomationResolverResult
    VM-->>View: Render result, timeline, metrics, devices, and agent dashboard
```

## 7. Context Model

`ResolutionContext` is the central mutable-by-patch state object. Agents do not mutate it directly; they return `ResolutionContextPatch` values and `AgentScheduler` applies those patches through `ResolutionContextStore`.

| Field | Purpose |
| --- | --- |
| `request` | Original command text and execution toggle. |
| `language`, `domain`, `intent`, `deviceType`, `slots`, `risk` | NLU outputs produced by parallel agents. |
| `resolutionState` | Bundled worker state for compatibility with existing resolver contracts. |
| `retrievedCandidates` | Device/routine candidates from registry and semantic retrieval. |
| `selectedCandidateIDs`, `aggregation` | Ranked candidate IDs and clarification metadata. |
| `hydratedCandidates` | Full candidate records used by draft, safety, and execution stages. |
| `knowledgeSnippets` | Canonical and RAG-selected context for prompts and fallback. |
| `ragChunks` | Per-agent retrieved chunk trace. |
| `instructionPackage` | Foundation Models prompt, instructions, tools, and mode. |
| `draft` | Model or fallback-produced command draft. |
| `executionPlan` | Deterministic execution plan. |
| `resolution` | Final or intermediate command resolution. |
| `errors` | Agent failures captured for observability. |
| `trace` | Per-agent timing and result trace. |
| `memoryHints` | Low-priority hints from previous turns. |

## 8. Agent Inventory

The implemented system has 26 specialist agents.

| # | Agent | Group | Role |
| --- | --- | --- | --- |
| 1 | `LanguageAgent` | NLU | Detects language and mixed-language state, with deterministic fallback support. |
| 2 | `DomainAgent` | NLU | Classifies whether text belongs to home automation or another domain. |
| 3 | `IntentFamilyAgent` | NLU | Identifies broad intent families such as power, temperature, brightness, media, lock, routine, or status. |
| 4 | `DeviceTypeAgent` | NLU | Extracts normalized device-type hints. |
| 5 | `SlotExtractionAgent` | NLU | Extracts rooms, nicknames, values, units, modes, and durations. |
| 6 | `RiskClassificationAgent` | NLU | Produces an initial risk estimate and reason. |
| 7 | `CapabilityKnowledgeAgent` | Knowledge | Retrieves relevant capability facts, then hydrates source-of-truth definitions from `HomeCapabilityRegistry`. |
| 8 | `BixbyKnowledgeAgent` | Knowledge | Retrieves and hydrates relevant Bixby voice-command snippets. |
| 9 | `CommandExampleAgent` | Knowledge | Retrieves similar generated command examples for few-shot context. |
| 10 | `CandidateRetrievalAgent` | Candidates | Retrieves device/routine candidates from `MockHomeDeviceRegistry`, enhanced with semantic device hints. |
| 11 | `CandidateRankingAgent` | Candidates | Ranks retrieved candidates and decides whether clarification is needed. |
| 12 | `CandidateShardAgent` | Candidates | Supports shard-level candidate selection for large candidate sets. |
| 13 | `CandidateHydrationAgent` | Candidates | Hydrates selected candidate IDs into full `HomeCandidateRecord` values. |
| 14 | `InstructionComposerAgent` | Draft | Builds `HomeModelInstructionPackage` using canonical data plus selected RAG slices. |
| 15 | `DraftGenerationAgent` | Draft | Produces a `HomeCommandDraft` through the draft resolver. |
| 16 | `DraftRepairAgent` | Draft | Attempts draft repair or lower-confidence fallback draft selection. |
| 17 | `SafetyValidationAgent` | Safety | Validates target, capability, command, risk, and plan eligibility. Mandatory fail-closed gate. |
| 18 | `ParameterValidationAgent` | Safety | Checks enum values, ranges, and required parameters. Mandatory fail-closed gate. |
| 19 | `ConfirmationPolicyAgent` | Safety | Enforces high-risk and memory-derived-target confirmation. Mandatory fail-closed gate. |
| 20 | `ExecutionPlanningAgent` | Execution | Converts valid drafts into deterministic execution plans. Mandatory fail-closed gate. |
| 21 | `MockExecutionAgent` | Execution | Mutates `MockHomeDeviceRegistry` for allowed low-risk command steps only. Mandatory fail-closed gate. |
| 22 | `RuleFallbackAgent` | Fallback | Runs deterministic rule-based resolution when models are unavailable or fallback is selected. |
| 23 | `BixbyFallbackAgent` | Fallback | Maps Bixby-style voice intents or catalog utterances to drafts. |
| 24 | `UnsupportedCommandAgent` | Fallback | Produces a clear unsupported result when no route can resolve safely. |
| 25 | `ClarificationAgent` | Response | Converts ambiguity into a user-facing clarification result. |
| 26 | `ResultSummaryAgent` | Response | Formats final result summaries from `HomeCommandResolution`. |

## 9. Agent Execution Plan

`AgentPlanner` builds one of two plan shapes:

```text
Fallback-only:
RuleFallbackAgent -> BixbyFallbackAgent -> UnsupportedCommandAgent

Full model path:
Parallel NLU group
-> Parallel knowledge/candidate retrieval group
-> CandidateRankingAgent
-> CandidateHydrationAgent
-> InstructionComposerAgent
-> DraftGenerationAgent
-> SafetyValidationAgent
-> ParameterValidationAgent
-> ConfirmationPolicyAgent
-> ExecutionPlanningAgent
-> MockExecutionAgent when policy permits execution
```

The full plan can still reach fallback or terminal results through agent outputs, policy checks, and deterministic safety behavior.

## 10. RAG Architecture

```mermaid
flowchart LR
    subgraph Ingestion["Indexing at launch"]
        Cap["Capability Catalog"] --> Chunker["DocumentChunker"]
        Examples["Generated NL Dataset"] --> Chunker
        Bixby["Bixby Command Catalog"] --> Chunker
        Devices["Mock Device Registry"] --> Chunker
        Chunker --> Embedder["TFIDF / Semantic / Fallback Embeddings"]
        Embedder --> Store["VectorStore"]
    end

    subgraph Query["Per-agent retrieval"]
        Agent["Agent"] --> Retriever["ContextRetriever"]
        Retriever --> Store
        Store --> Results["ScoredChunk values"]
        Results --> Agent
    end
```

| Component | Role |
| --- | --- |
| `DocumentChunk` | Identifiable knowledge unit with content, source, and metadata. |
| `KnowledgeSource` | Source enum: capability, generated command dataset, Bixby command, or device. |
| `MetadataFilter` | Restricts retrieval by source and metadata keys. |
| `ScoredChunk` | Retrieval result with chunk plus similarity score. |
| `DocumentChunker` | Converts canonical catalogs, generated examples, Bixby commands, and device records into chunks. |
| `EmbeddingProviding` | Protocol for text embedding providers. |
| `CorpusAwareEmbeddingProviding` | Embedding protocol that can prepare itself from a known corpus. |
| `TFIDFEmbeddingProvider` | Deterministic local embedding implementation. |
| `SemanticEmbeddingProvider` | Production-grade semantic embedding wrapper that can drive retrieval ranking when configured. |
| `FallbackEmbeddingProvider` | Uses semantic embeddings when available and falls back to TF-IDF when semantic vectors are empty. |
| `VectorStore` | Actor-backed in-memory vector index with cosine similarity search and metadata filtering. |
| `KnowledgeIndexer` | Builds the full index from canonical knowledge at app launch. |
| `ContextRetriever` | Public retrieval API used by agents. |

## 11. Safety Architecture

```mermaid
flowchart TD
    Draft["HomeCommandDraft"]
    Hydrated["Hydrated candidate records"]
    Safety["SafetyValidationAgent"]
    Params["ParameterValidationAgent"]
    Confirm["ConfirmationPolicyAgent"]
    Plan["ExecutionPlanningAgent"]
    Execute["MockExecutionAgent"]
    Stop["Confirmation / Clarification / Unsupported"]
    Ready["Ready to execute without mutation"]
    Done["Executed result"]

    Draft --> Safety
    Hydrated --> Safety
    Safety -->|invalid or high risk| Stop
    Safety -->|valid| Params
    Params -->|invalid or missing| Stop
    Params -->|valid| Confirm
    Confirm -->|confirmation required| Stop
    Confirm -->|allowed| Plan
    Plan -->|cannot plan| Stop
    Plan -->|query or execution disabled| Ready
    Plan -->|low-risk command and enabled| Execute
    Execute --> Done
```

Mandatory fail-closed agents:

| Agent | Fail-closed behavior |
| --- | --- |
| `SafetyValidationAgent` | Requires confirmation when a draft exists; otherwise unsupported. |
| `ParameterValidationAgent` | Returns clarification for invalid or missing values. |
| `ConfirmationPolicyAgent` | Requires confirmation when draft exists; otherwise asks for confirmation. |
| `ExecutionPlanningAgent` | Blocks execution and returns unsupported. |
| `MockExecutionAgent` | Returns `.readyToExecute` with the validated plan instead of mutating state. |

## 12. Conversation Memory

`ConversationMemory` stores recent turns as `ConversationTurn` values. `ConversationMemoryReferenceDetector` checks whether a new command likely refers to prior context, such as "make it warmer" or "turn it off".

Memory rules:

- Memory hints are written to `ResolutionContext.memoryHints`.
- Candidate retrieval and ranking may use them as low-priority hints.
- Candidate hydration, safety validation, parameter validation, confirmation policy, and execution planning always rerun.
- Security-sensitive and high-risk operations must not execute from pronouns or prior context without explicit target confirmation.

## 13. Circuit Breakers and Resilience

`CircuitBreakerRegistry` creates an `AgentCircuitBreaker` per agent. Each breaker moves through `closed`, `open`, and `halfOpen` states.

| Case | Behavior |
| --- | --- |
| Non-mandatory agent unavailable or open | Scheduler skips the agent and lets fallback or later stages continue. |
| Mandatory safety gate unavailable or open | Scheduler calls `OrchestratorPolicyEngine.failClosedResult`. |
| Agent success | Breaker records success. |
| Agent retryable or terminal failure | Breaker records failure. |

`AgentTraceEntry` records timing and result state for every attempted agent, and `OrchestratorMetrics` captures circuit states, evaluation fields, fallback usage, and final outcome.

## 14. Folder Structure

```text
HomeAutomation/
|-- README.md
|-- Architecture.md
|-- HomeAutomation.xcodeproj/
|-- HomeAutomationApp/
|   |-- HomeAutomationApp.swift
|   |-- HomeAutomationView.swift
|   `-- HomeAutomationViewModel.swift
|-- HomeAutomationCore/
|   |-- Package.swift
|   |-- Sources/
|   |   |-- HomeAutomationCore/
|   |   |   |-- Errors/
|   |   |   |-- HomeAutomation/
|   |   |   `-- Resources/
|   |   |-- HomeAutomationRAG/
|   |   |-- HomeAutomationAgents/
|   |   |   |-- Protocols/
|   |   |   |   |-- AgentCapability.swift
|   |   |   |   |-- AgentError.swift
|   |   |   |   |-- AgentOutput.swift
|   |   |   |   |-- HomeAgent.swift
|   |   |   |   `-- ResolutionContext.swift
|   |   |   |-- NLU/
|   |   |   |   |-- LanguageAgent.swift
|   |   |   |   |-- DomainAgent.swift
|   |   |   |   |-- IntentFamilyAgent.swift
|   |   |   |   |-- DeviceTypeAgent.swift
|   |   |   |   |-- SlotExtractionAgent.swift
|   |   |   |   |-- RiskClassificationAgent.swift
|   |   |   |   `-- WorkerSessionSupport.swift
|   |   |   |-- Knowledge/
|   |   |   |   |-- KnowledgeInputs.swift
|   |   |   |   |-- CapabilityKnowledgeAgent.swift
|   |   |   |   |-- BixbyKnowledgeAgent.swift
|   |   |   |   `-- CommandExampleAgent.swift
|   |   |   |-- Candidates/
|   |   |   |   |-- CandidateInputs.swift
|   |   |   |   |-- CandidateResolverSupport.swift
|   |   |   |   |-- CandidateRetrievalAgent.swift
|   |   |   |   |-- CandidateRankingAgent.swift
|   |   |   |   |-- CandidateShardAgent.swift
|   |   |   |   `-- CandidateHydrationAgent.swift
|   |   |   |-- Draft/
|   |   |   |   |-- AgentTools.swift
|   |   |   |   |-- DraftTypes.swift
|   |   |   |   |-- AgentInstructionSetFactory.swift
|   |   |   |   |-- AgentDraftResolver.swift
|   |   |   |   |-- InstructionComposerAgent.swift
|   |   |   |   |-- DraftGenerationAgent.swift
|   |   |   |   `-- DraftRepairAgent.swift
|   |   |   |-- Safety/
|   |   |   |   |-- SafetyInputs.swift
|   |   |   |   |-- AgentCommandValidator.swift
|   |   |   |   |-- SafetyValidationAgent.swift
|   |   |   |   |-- ParameterValidationAgent.swift
|   |   |   |   `-- ConfirmationPolicyAgent.swift
|   |   |   |-- Execution/
|   |   |   |   |-- ExecutionSupport.swift
|   |   |   |   |-- ExecutionPlanningAgent.swift
|   |   |   |   `-- MockExecutionAgent.swift
|   |   |   |-- Fallback/
|   |   |   |   |-- AgentTextParser.swift
|   |   |   |   |-- BixbyFallbackAgent.swift
|   |   |   |   |-- FallbackInputs.swift
|   |   |   |   |-- FallbackRuleTypes.swift
|   |   |   |   |-- AgentRuleBasedResolver.swift
|   |   |   |   |-- RuleFallbackAgent.swift
|   |   |   |   `-- UnsupportedCommandAgent.swift
|   |   |   |-- Response/
|   |   |   |   |-- ClarificationAgent.swift
|   |   |   |   `-- ResultSummaryAgent.swift
|   |   |   `-- RAG/
|   |   |       `-- AgentRAGSupport.swift
|   |   |-- HomeAutomationOrchestrator/
|   |   `-- HomeAutomationResolver/
|   `-- Tests/
|       |-- HomeAutomationRAGTests/
|       |-- HomeAutomationAgentTests/
|       |-- HomeAutomationOrchestratorTests/
|       `-- HomeAutomationResolverTests/
```

## 15. Low-Level Component Description: App Layer

| Component | File | Role |
| --- | --- | --- |
| `HomeAutomationApp` | `HomeAutomationApp.swift` | SwiftUI `App` entry point that presents `HomeAutomationView`. |
| `HomeAutomationView` | `HomeAutomationView.swift` | Main UI composition for input, samples, execution toggle, result output, pipeline timeline, metrics, agent dashboard, device cards, registry preview, and command history. |
| `DeviceTile` | `HomeAutomationView.swift` | Private device dashboard card. |
| `OutputPanel` | `HomeAutomationView.swift` | Private reusable monospaced output container. |
| `HomeAutomationViewModel` | `HomeAutomationViewModel.swift` | `@MainActor @Observable` coordinator. Owns UI state, initializes RAG-enabled orchestrator, streams updates, formats results, refreshes metrics, and tracks command history. |
| `HomePipelineEventStatus` | `HomeAutomationViewModel.swift` | UI status enum for timeline rows. |
| `HomePipelineEventItem` | `HomeAutomationViewModel.swift` | UI projection of an `OrchestratorPipelineEvent`. |
| `HomeDeviceDashboardItem` | `HomeAutomationViewModel.swift` | UI projection of a device record. |
| `HomeCommandHistoryItem` | `HomeAutomationViewModel.swift` | UI history entry for previous commands. |
| `AgentDashboardItem` | `HomeAutomationViewModel.swift` | UI projection of agent status, duration, and circuit state. |

## 16. Low-Level Component Description: Core Domain

| Component | Role |
| --- | --- |
| `FoundationLabCoreError` | Shared typed errors for invalid requests, provider failures, unavailable functionality, and unsupported cases. |
| `HomeCommandResolving` | Main resolver abstraction implemented by orchestrator, rule fallback, and legacy resolver. |
| `HomeCommandDraftResolving` | Draft-generation abstraction for Foundation Models and test doubles. |
| `HomeCandidateResolving` | Candidate selection abstraction. |
| `HomeWorkerSessionAnalyzing` | Worker-analysis abstraction for language/domain/intent/device/slot/risk extraction. |
| `HomeAutomationCommandDomain` | Domain classification output. |
| `HomeAutomationIntentFamily` | Broad intent family used for routing, prompts, candidates, and safety. |
| `HomeAutomationRiskLevel` | Shared low/medium/high/critical risk scale. |
| `HomeAutomationIntent` | Final normalized user intent. |
| `HomeLanguageDetectionResult` | Language worker output. |
| `HomeDomainClassificationResult` | Domain worker output. |
| `HomeIntentFamilyResult` | Intent-family worker output. |
| `HomeDeviceTypeResult` | Device-type worker output. |
| `HomeExtractedSlot` | Single extracted slot. |
| `HomeSlotExtractionResult` | Aggregated slot output. |
| `HomeRiskClassificationResult` | Risk worker output. |
| `HomeResolutionState` | Bundled worker state shared by candidates, draft, validation, and UI. |
| `HomeCandidateType` | Device, group, or routine candidate kind. |
| `HomeCandidateRecord` | Full device/routine record. |
| `HomeCompactCandidateView` | Compact projection for ranking. |
| `HomeCandidateShardSelection` | Candidate shard result. |
| `HomeCandidateAggregationResult` | Final candidate selection result and clarification metadata. |
| `HomeResolvedParameter` | Normalized command parameter. |
| `HomeCommandDraft` | Pre-validation command draft. |
| `HomeAutomationExecutionStep` | One read/query/command step. |
| `HomeAutomationExecutionPlan` | Ordered execution steps and confirmation flag. |
| `HomeCommandResolution` | Final result: ready, executed, confirmation, clarification, or unsupported. |
| `HomeFinalResolutionInput` | Compound input for draft resolution and validation. |
| `HomeAutomationResolverResult` | Top-level resolver output. |
| `HomeGenerationMode` | Foundation Models generation mode. |
| `HomeModelInstructionPackage` | Prompt, instructions, tools, adapter flag, and generation mode. |

## 17. Low-Level Component Description: Core Catalogs, Policies, Registry

| Component | Role |
| --- | --- |
| `HomeCapabilityDefinition` | In-memory capability definition with commands, attributes, ranges, enum values, and risk. |
| `HomeCapabilityRegistry` | Canonical capability lookup and command/mode/risk helper namespace. |
| `HomeAutomationKnowledgeBase` | Loads generated capability catalog and command dataset through `Bundle.module`. |
| `HomeGeneratedCommandDataset` | Decodes generated natural-language command examples. |
| `HomeGeneratedCommandExample` | One generated command example with expected output data. |
| `HomeGeneratedCommandParameter` | Generated parameter shape. |
| `HomeGeneratedCommandExpectation` | Expected domain/device/capability/command/confirmation metadata. |
| `HomeCatalogSourceNote` | Catalog source metadata. |
| `HomeCatalogCapability` | JSON capability record. |
| `HomeCatalogCapabilityPlatformMappings` | Platform mapping metadata for capabilities. |
| `HomeCatalogDeviceType` | JSON device type record. |
| `HomeCatalogDevicePlatformMappings` | Platform mapping metadata for device types. |
| `HomeRiskPolicy` | Deterministic confirmation and risk policy. |
| `HomeParameterValidator` | Deterministic parameter range and enum validator. |
| `MockHomeDeviceRegistry` | Actor-backed mock registry for device listing, candidate retrieval, and low-risk plan execution. |
| `HomeCandidateContextStore` | Thread-safe candidate cache and hydration support. |
| `shardHomeCandidates` | Utility for splitting large candidate sets into shards. |
| `HomeBixbyVoiceCommand` | Embedded Bixby voice command record. |
| `HomeBixbyCommandCatalog` | Bixby command catalog, lookup, metadata, and summaries. |
| `HomeBixbyLinkedVoiceIntentPair` | Link between local capability and Bixby source intent. |
| `HomeBixbyCommandMapper` | Converts Bixby voice intents into `HomeCommandDraft` values. |
| `FoundationHomeCommandDraftResolver` | Concrete Foundation Models draft resolver. |
| `HomeAdapterModelDiagnostic` | Adapter load diagnostic record. |
| `HomeAdapterModelDiagnosticsStore` | Thread-safe last-diagnostic store. |
| `HomeAdapterModelProvider` | Creates Foundation Models sessions with optional adapter configuration. |

## 18. Low-Level Component Description: Agent Protocols

| Component | Role |
| --- | --- |
| `AgentID` | Stable identity for each specialist agent. |
| `AgentCapability` | Capability enum used by registry and planner. |
| `HomeAgent` | Strongly typed agent protocol with associated input/output. |
| `AnyHomeAgent` | Type-erased agent protocol used by scheduler. |
| `AgentFailure` | Structured failure with agent ID, reason, and retryability. |
| `AgentTraceEntry` | Timing and result trace for one agent call. |
| `ResolutionContextPatch` | Patch returned by an agent. |
| `AnySendableValue` | Sendable value box used in context patches. |
| `AgentRunResult` | Agent result: success, clarification, unsupported, retryable failure, or terminal failure. |
| `ResolutionContext` | Shared orchestration context. |
| `CommandRequest` | User text plus execution toggle. |
| `KnowledgeSnippet` | Agent-level knowledge snippet. |
| `MemoryHint` | Low-priority candidate hint from conversation memory. |

## 19. Low-Level Component Description: Agent Implementations

| Component | Role |
| --- | --- |
| `HomeAgentWorkerOverrides` | Injection container for replacing worker functions in tests. |
| `HomeAgentWorkerSessionSupport` | Foundation Models worker support with deterministic fallback. |
| `AgentRAGSupport` | Internal helper for retrieving RAG context for agents. |
| `CapabilityKnowledgeAgent` | Retrieves and hydrates capability knowledge. |
| `BixbyKnowledgeAgent` | Retrieves and hydrates Bixby command knowledge. |
| `CommandExampleAgent` | Retrieves generated command examples. |
| `CandidateRetrievalInput` | Input for candidate retrieval. |
| `CandidateRankingInput` | Input for candidate ranking. |
| `CandidateShardInput` | Input for shard-level candidate ranking. |
| `CandidateHydrationInput` | Input for candidate hydration. |
| `HomeCandidateResolverMetrics` | Stores candidate resolver metrics for tests and diagnostics. |
| `HomeCandidateResolverSupport` | Candidate ranking and shard support. |
| `CandidateRetrievalAgent` | Retrieves candidates from registry and RAG hints. |
| `CandidateRankingAgent` | Selects final candidates or clarification. |
| `CandidateShardAgent` | Selects candidates from one shard. |
| `CandidateHydrationAgent` | Hydrates final candidate IDs. |
| `AgentToolProvider` | Builds Foundation Models tools for draft generation. |
| `AgentFindDevicesTool` | Tool for device search. |
| `AgentGetCapabilitiesTool` | Tool for capability lookup. |
| `AgentGetDeviceStateTool` | Tool for reading device state. |
| `AgentGetSupportedModesTool` | Tool for enum/mode lookup. |
| `AgentValidateCommandTool` | Tool for command support and risk validation. |
| `AgentHydrateCandidatesTool` | Tool for full candidate hydration. |
| `AgentInstructionSetFactory` | Builds prompt/instruction packages with canonical data and RAG-selected context. |
| `AgentDraftAttemptReport` | One draft attempt report. |
| `AgentDraftResolutionReport` | Aggregated draft attempt report. |
| `AgentDraftResolutionOutput` | Draft plus report output. |
| `AgentDraftResolverMetrics` | Stores latest draft report. |
| `AgentDraftResolver` | Retry wrapper around draft generation. |
| `InstructionComposerAgent` | Produces `HomeModelInstructionPackage`. |
| `DraftGenerationAgent` | Produces initial `HomeCommandDraft`. |
| `DraftRepairAgent` | Produces repaired draft output. |
| `SafetyValidationInput` | Input for safety validation. |
| `ParameterValidationInput` | Input for parameter validation. |
| `ConfirmationPolicyInput` | Input for confirmation policy. |
| `AgentCommandValidator` | Deterministic draft validator. |
| `SafetyValidationAgent` | Validates draft safety and builds resolution. |
| `ParameterValidationAgent` | Validates parameters. |
| `ConfirmationPolicyAgent` | Applies confirmation policy. |
| `ExecutionPlanningInput` | Input for execution planning. |
| `AgentExecutionPlanner` | Converts drafts into execution plans. |
| `AgentPlanExecutor` | Executes low-risk plan steps against the mock registry. |
| `ExecutionPlanningAgent` | Produces execution plan. |
| `MockExecutionAgent` | Executes low-risk commands. |
| `RuleFallbackInput` | Input for deterministic fallback. |
| `AgentRuleBasedResolver` | Deterministic rule-based resolver. |
| `RuleFallbackAgent` | Wraps rule-based fallback. |
| `AgentBixbyDraftMatch` | Bixby fallback match. |
| `BixbyFallbackInput` | Input for Bixby fallback. |
| `AgentBixbyFallbackMapper` | Maps Bixby hints to drafts. |
| `BixbyFallbackAgent` | Runs Bixby fallback mapping. |
| `UnsupportedCommandAgent` | Returns unsupported resolution. |
| `AgentTextParser` | Deterministic multilingual text parser. |
| `ClarificationAgent` | Returns clarification resolution. |
| `ResultSummaryAgent` | Formats final summaries. |

## 20. Low-Level Component Description: Orchestrator

| Component | Role |
| --- | --- |
| `OrchestratorUpdate` | Stream update enum: event or final result. |
| `HomeCommandOrchestrator` | Main orchestrated resolver. |
| `AgentTask` | One planned agent call. |
| `AgentPhase` | Sequential or parallel plan phase. |
| `AgentExecutionPlan` | Ordered plan of phases. |
| `AgentPlanner` | Builds fallback-only or full model execution plan. |
| `AgentScheduler` | Runs agents, handles circuit checks, applies patches, emits events, and fails closed. |
| `AgentRegistry` | Stores type-erased agents by identity/capability. |
| `ContextualHomeAgent` | Adapts a typed `HomeAgent` into `AnyHomeAgent` with context input and patch mapping. |
| `DefaultAgentRegistryFactory` | Wires default agent implementations and dependencies. |
| `ResolutionContextPatchKey` | String constants for patch updates. |
| `ResolutionContextStore` | Actor for snapshot/apply/append operations on context. |
| `OrchestratorPipelineEvent` | UI-visible pipeline event. |
| `AgentEventBus` | Async event publisher. |
| `OrchestratorPolicyEngine` | Runtime policy for models, retries, terminal exits, execution, and fail-closed safety. |
| `CircuitState` | Circuit breaker state enum. |
| `AgentCircuitBreaker` | Per-agent breaker. |
| `CircuitBreakerRegistry` | Registry of per-agent breakers. |
| `ConversationTurn` | Stored previous-turn summary. |
| `ConversationMemory` | Actor storing recent turns and last resolved device hints. |
| `ConversationMemoryReferenceDetector` | Detects commands that reference prior context. |
| `OrchestratorContextMetrics` | Metrics about context and RAG usage. |
| `OrchestratorSafetyMetrics` | Safety-specific metrics. |
| `OrchestratorCandidateMetrics` | Candidate and shard metrics. |
| `OrchestratorMetrics` | Full metrics payload. |
| `OrchestratorMetricsCollector` | Stores and serializes latest metrics. |

## 21. Low-Level Component Description: Legacy Compatibility Target

`HomeAutomationResolver` preserves the original staged resolver. It is useful for regression tests, parity comparisons, and migration documentation.

| Component | Role |
| --- | --- |
| `LegacyHomeCommandResolver` | Original end-to-end resolver. |
| `LegacyRuleBasedResolver` | Original deterministic rule fallback. |
| `LegacyPartialSafeWorkerSessionLayer` | Original worker-analysis layer with partial safety fallbacks. |
| `LegacyCandidateResolver` | Original candidate selector. |
| `LegacyCandidateResolverMetrics` | Original candidate metrics store. |
| `LegacyCandidateContextStore` | Original async candidate cache. |
| `LegacyInstructionSetFactory` | Original prompt and tool package builder. |
| `LegacyDraftResolver` | Original draft retry wrapper. |
| `LegacyDraftAttemptReport` | Original single draft-attempt report. |
| `LegacyDraftResolutionReport` | Original aggregate draft report. |
| `LegacyDraftResolutionOutput` | Original draft plus report output. |
| `LegacyDraftResolverMetrics` | Original draft metrics store. |
| `LegacyCommandValidator` | Original deterministic draft validator. |
| `LegacyExecutionPlanner` | Original execution planner. |
| `LegacyPlanExecutor` | Original plan executor. |
| `LegacyBixbyFallbackMapper` | Original Bixby fallback mapper. |
| `LegacyBixbyDraftMatch` | Original Bixby match record. |
| `LegacyPipelineStage` | Original stream stage enum. |
| `LegacyPipelineEvent` | Original timeline event. |
| `LegacyResolverUpdate` | Original stream update enum. |
| `LegacyResolutionMetrics` | Original metrics payload. |
| `LegacyMetricsCollector` | Original metrics store. |
| `LegacyAdapterTrainingExporter` | JSONL/export helper for generated dataset examples. |
| `LegacyDeploymentChecklist` | Static deployment checklist. |
| `LegacyTextParser` | Original deterministic text parser. |
| `LegacyToolProvider` and `Legacy*Tool` types | Original Foundation Models tools. |

## 22. Resource Model

| Resource | Purpose |
| --- | --- |
| `home_automation_capability_catalog.json` | Generated capability and device-type catalog loaded by `HomeAutomationKnowledgeBase`. |
| `home_automation_nl_command_dataset.json` | Generated natural-language examples used for RAG examples, adapter export, and tests. |
| Embedded Bixby catalog | Static command catalog in `HomeBixbyCommandCatalog`. |
| Mock device registry | Runtime device/routine records and current mock state. |

## 23. Observability

The runtime exposes several layers of observability:

- `OrchestratorPipelineEvent` streams live stage and agent updates to the UI.
- `AgentTraceEntry` records per-agent timing and result.
- `OrchestratorMetrics` records final outcome, fallback status, circuit states, safety fields, candidate fields, and evaluation fields.
- `HomeAutomationViewModel` renders timeline, JSON metrics, and agent dashboard data.
- Tests assert metrics and event behavior for fallback, RAG, memory, safety, and parallel shard scenarios.

## 24. Testing Architecture

| Test Target | Focus |
| --- | --- |
| `HomeAutomationRAGTests` | Chunking, embedding, vector search, metadata filtering, indexer, retriever, and semantic fallback. |
| `HomeAutomationAgentTests` | Agent contracts, NLU agents, knowledge agents, candidate agents, draft agents, safety agents, execution agents, fallback agents, and RAG integration. |
| `HomeAutomationOrchestratorTests` | Scheduler, registry, circuit breakers, conversation memory, orchestrator streams, parity, metrics, and fail-closed behavior. |
| `HomeAutomationResolverTests` | Legacy resolver parity and safety regression coverage. |

Verified command set:

```sh
cd HomeAutomationCore
swift test
cd ..
xcodebuild -scheme HomeAutomation -destination platform=macOS build
```

Current verified state: 77 Swift package tests pass, and the `HomeAutomation` Xcode scheme builds successfully.

## 25. Architecture Invariants

1. New orchestrator code must not depend on `HomeAutomationResolver`.
2. RAG may rank and retrieve, but final facts must be hydrated from canonical registries.
3. Safety, parameter, confirmation, execution-planning, and mock-execution gates must fail closed.
4. Memory hints must never bypass candidate hydration or safety validation.
5. High-risk and security-sensitive actions must require explicit confirmation.
6. Execution is allowed only for low-risk command steps when `executeLowRiskCommands` is true.
7. Query/read steps do not mutate registry state.
8. Every agent execution path should emit traceable events or metrics.
9. Legacy compatibility should remain test-covered until intentionally removed.
