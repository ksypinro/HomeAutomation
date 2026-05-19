# HomeAutomation Orchestrator — Architecture Document

> **Module**: `HomeAutomationOrchestrator`
> **Last Updated**: 2026-05-17
> **Status**: Production (graph-only orchestrator)

---

## 1. Executive Summary

The `HomeAutomationOrchestrator` is the central coordination layer of the HomeAutomation system. It receives raw natural-language voice commands, classifies them into operation types, dynamically constructs a Directed Acyclic Graph (DAG) of specialized AI agents, executes them with resilience guarantees (circuit breakers, safety gates, fallback paths), and produces a fully resolved command output — either a device command draft, an automation creation plan, or a clarification request.

The module implements a **model-first with deterministic fallback** architecture: Foundation Model (FM) calls are prioritized for all NLU tasks, with rule-based systems providing hints and serving as robust fallbacks when the FM is unavailable.

---

## 2. High-Level Architecture

```mermaid
graph TB
    subgraph Entry["Entry Layer"]
        UI["Client / UI"]
        HCO["HomeCommandOrchestrator"]
    end

    subgraph Routing["Operation Routing"]
        ROOT["Root Command Graph"]
        OD["OperationDetectionAgent"]
        OP["OrchestratorPolicyEngine"]
    end

    subgraph Planning["Graph Planning"]
        GP["GraphPlanner"]
        OGC["OperationGraphCatalog"]
        GV["GraphValidator"]
    end

    subgraph Execution["Graph Execution"]
        GS["GraphScheduler"]
        AR["AgentRegistry"]
        CBR["CircuitBreakerRegistry"]
        RCS["ResolutionContextStore"]
        AEB["AgentEventBus"]
    end

    subgraph AgentPool["Agent Pool"]
        NLU["NLU Agents (6)"]
        RAG["RAG/Knowledge Agents (4)"]
        RANK["Ranking & Draft Agents (5)"]
        SAFE["Safety Gate Agents (4)"]
        AUTO["Automation Agents (8)"]
        FB["Fallback Agents (3)"]
    end

    subgraph Observability["Observability"]
        MC["OrchestratorMetricsCollector"]
        GRM["GraphRunMetrics"]
        CM["ConversationMemory"]
    end

    UI -->|"resolve(text)"| HCO
    HCO --> ROOT
    ROOT --> OD
    OD -->|"operation type patch"| HCO
    HCO --> OP
    OP -->|"policy decision"| GP
    GP --> OGC
    OGC -->|"OrchestrationGraph"| GV
    GV -->|"validated graph"| GS
    GS --> AR
    GS --> CBR
    GS --> RCS
    GS --> AEB
    AR --> AgentPool
    GS -->|"AgentRunResult"| HCO
    HCO --> MC
    HCO --> CM
    HCO -->|"OrchestratorUpdate stream"| UI
```

---

## 3. Component Inventory

| Component | Type | LOC | Responsibility |
|---|---|---|---|
| `HomeCommandOrchestrator` | `final class` | 761 | Entry point, lifecycle coordination, metrics assembly |
| `GraphScheduler` | `struct` | — | DAG-based agent execution engine |
| `GraphPlanner` | `struct` | 181 | Constructs operation-specific DAGs |
| `GraphValidator` | `struct` | 235 | Pre-execution graph integrity checks (cycles, reachability) |
| `AgentRegistry` | `final class` | 111 | Agent lookup by ID, capability, or operation |
| `ContextualAgentAdapters` | — | 820 | Type-erased wrappers + `DefaultAgentRegistryFactory` |
| `HomeAutomationAgents/AutomationRuntime` | directory | — | Shared automation runtime context keys, bridge types, and input/output DTOs |
| `HomeAutomationAgents/AutomationDraftExtraction` | directory | — | Automation draft extraction DAG agent |
| `HomeAutomationAgents/AutomationActionResolution` | directory | — | Automation action-resolution DAG agent plus action result DTOs |
| `HomeAutomationAgents/AutomationConditionOperandResolution` | directory | — | Automation condition operand DAG agent plus condition result DTOs |
| `HomeAutomationAgents/SmartThingsCompilation` | directory | — | SmartThings Rule compilation DAG agent |
| `HomeAutomationAgents/SmartThingsRuleCreation` | directory | — | SmartThings Rule creation DAG agent |
| `HomeAutomationAgents/AutomationResultAssembly` | directory | — | Final automation result assembly DAG agent |
| `ResolutionContextStore` | `actor` | 226 | Thread-safe mutable context with typed patch application |
| `OrchestratorPolicyEngine` | `struct` | 150 | Routing, retry, safety gate, and fail-closed policies |
| `CircuitBreakerRegistry` | `actor` | 130 | Per-agent failure isolation (closed → open → half-open) |
| `AgentEventBus` | `actor` | 106 | Real-time event streaming to UI via `AsyncStream` |
| `ConversationMemory` | `actor` | 101 | Short-term multi-turn memory for pronoun resolution |
| `OrchestratorMetricsCollector` | `actor` | 590 | Comprehensive per-run telemetry snapshots |
| `AutomationCreationResolver` | `struct` | — | Automation creation service support retained for reusable logic |
| `AutomationActionResolver` | `struct` | 328 | Resolves action descriptions via direct-command pipeline |
| `AutomationConditionOperandResolver` | `struct` | ~500 | Resolves condition operands to device attributes |
| `OperationGraphCatalog` | `struct` | 82 | Registry of graph providers per operation type |
| `GraphRunMetrics` | — | 81 | Per-node timing, status, and agent selection tracking |

---

## 4. Request Lifecycle — Detailed Flow

```mermaid
sequenceDiagram
    participant UI as Client
    participant HCO as HomeCommandOrchestrator
    participant ROOT as RootGraph
    participant OD as OperationDetectionAgent
    participant PE as PolicyEngine
    participant GP as GraphPlanner
    participant GV as GraphValidator
    participant GS as GraphScheduler
    participant AR as AgentRegistry
    participant CB as CircuitBreaker
    participant RCS as ContextStore
    participant EB as EventBus
    participant MC as MetricsCollector
    participant CM as ConversationMemory

    UI->>HCO: resolveStream("Turn on AC daily at 7 AM")
    HCO->>RCS: init(CommandRequest)
    HCO->>CM: check memory references
    HCO->>EB: publish(input event)
    HCO->>GP: planRootRouting(text, context)
    HCO->>GS: execute(rootCommandGraph)
    GS->>OD: run(context)
    OD-->>RCS: operation patch: automationCreation (confidence: 0.92)
    HCO->>RCS: snapshot()
    HCO->>HCO: supportedOperation() filter
    HCO->>EB: publish(operationDetection event)

    alt automationCreation
        HCO->>GP: plan(text, context, .automationCreation)
        GP->>GV: validate(graph)
        GV-->>GS: validated graph
        HCO->>GS: execute(automationCreationGraph)
        loop For each ready node batch
            GS->>AR: selectAgent(node)
            GS->>CB: shouldAllow(agentID)
            GS->>EB: publish(running)
            GS->>RCS: snapshot()
            GS->>GS: agent.run(context)
            GS->>RCS: apply(patch)
            GS->>CB: recordSuccess/Failure
            GS->>EB: publish(completed/failed)
        end
        GS-->>HCO: GraphSchedulerResult
    else executeDeviceCommand
        HCO->>GP: plan(text, context, .executeDeviceCommand)
        HCO->>GS: execute(directCommandGraph)
        GS-->>HCO: GraphSchedulerResult
    else unsupported
        HCO->>GS: execute(unsupportedGraph)
        GS-->>HCO: GraphSchedulerResult
    end

    HCO->>MC: store(metrics)
    HCO->>CM: append(ConversationTurn)
    HCO->>EB: publish(outcome), finish()
    HCO-->>UI: yield(.result), finish stream
```

---

## 5. Operation-Specific DAG Topologies

### 5.1 Direct Command Graph

```mermaid
graph LR
    subgraph Phase1["Phase 1 — NLU Classification (Parallel)"]
        L["Language"]
        D["Domain"]
        IF["IntentFamily"]
        DT["DeviceType"]
        SE["SlotExtraction"]
        RC["RiskClassification"]
    end

    subgraph Phase2["Phase 2 — Knowledge Retrieval (Parallel)"]
        CK["CapabilityKnowledge"]
        BK["BixbyKnowledge"]
        CE["CommandExample"]
        CR["CandidateRetrieval"]
    end

    subgraph Phase3["Phase 3 — Resolution (Sequential)"]
        RJ["RetrievalJudge"]
        CRank["CandidateRanking"]
        CH["CandidateHydration"]
        IC["InstructionComposer"]
        DG["DraftGeneration"]
        SV["SafetyValidation 🛡"]
        PV["ParameterValidation 🛡"]
        CP["ConfirmationPolicy 🛡"]
        EP["ExecutionPlanning 🛡"]
    end

    L --> CK & BK & CE & CR
    D --> CK & BK & CE & CR
    IF --> CK & BK & CE & CR
    DT --> CK & BK & CE & CR
    SE --> CK & BK & CE & CR
    RC --> CK & BK & CE & CR

    CK & BK & CE & CR --> RJ
    RJ --> CRank --> CH --> IC --> DG --> SV --> PV --> CP --> EP
```

> 🛡 = Safety Gate. Failure triggers `failClosed()` producing a safe resolution (confirmation or unsupported).

### 5.2 Automation Creation Graph

```mermaid
graph LR
    AD["AutomationDraft"] --> ACOR["ConditionOperandResolution"]
    AD --> AAR["ActionResolution"]
    ACOR --> AV["AutomationValidation 🛡"]
    AAR --> AV
    AV --> STC["SmartThingsCompilation"]
    STC --> STRC["SmartThingsRuleCreation"]
    STRC --> ARA["AutomationResultAssembly"]
```

Key design: operation detection is owned by the root routing graph. `ConditionOperandResolution` and `ActionResolution` fan out in parallel after draft extraction, then converge at the validation gate.

### 5.3 Fallback Graph

```mermaid
graph LR
    RF["RuleFallback"] --> BF["BixbyFallback"] --> UC["UnsupportedCommand"]
```

Activated when `PolicyEngine.shouldUseModels()` returns `false`.

---

## 6. Core Subsystem Deep Dives

### 6.1 Agent Protocol Hierarchy

```mermaid
classDiagram
    class HomeAgent {
        <<protocol>>
        +id: AgentID
        +capabilities: Set~AgentCapability~
        +manifest: AgentManifest
        +timeoutNanoseconds: UInt64
        +run(Input, ResolutionContext) async throws → Output
    }

    class AnyHomeAgent {
        <<protocol>>
        +id: AgentID
        +run(context: ResolutionContext) async → AgentRunResult
    }

    class ContextualHomeAgent~Agent~ {
        +agent: Agent
        +makeInput: (ResolutionContext) → Agent.Input
        +makePatch: (Agent.Output) → ResolutionContextPatch
        +run(context:) → AgentRunResult
    }

    HomeAgent <|-- LanguageAgent
    HomeAgent <|-- DomainAgent
    HomeAgent <|-- OperationDetectionAgent
    AnyHomeAgent <|.. ContextualHomeAgent
    ContextualHomeAgent o-- HomeAgent : wraps
```

The **two-protocol split** is critical: `HomeAgent` provides type safety for individual agent development, while `AnyHomeAgent` provides type-erasure for the scheduler. `ContextualHomeAgent` bridges them by converting `ResolutionContext` ↔ typed I/O.

### 6.2 ResolutionContext — Shared State Architecture

```mermaid
graph TB
    subgraph Store["ResolutionContextStore (actor)"]
        CTX["ResolutionContext (struct, Sendable)"]
        SNAP["snapshot() → immutable copy"]
        APPLY["apply(ResolutionContextPatch)"]
    end

    subgraph Fields["Context Fields"]
        REQ["request: CommandRequest"]
        NLU_F["language, domain, intent, deviceType, slots, risk"]
        CAND["retrievedCandidates, hydratedCandidates, selectedIDs"]
        KNOW["knowledgeSnippets, retrievalReports, memoryHints"]
        DRAFT_F["instructionPackage, draft, executionPlan"]
        RES["resolution: HomeCommandResolution"]
        SCOPED["scopedValues: [ContextScope: [String: AnySendableValue]]"]
        TRACE["trace: [AgentTraceEntry], errors: [AgentFailure]"]
    end

    Store --> Fields
```

**Critical invariant**: Agents receive an immutable `snapshot()`. They return a `ResolutionContextPatch` containing only the fields they update. The store applies patches atomically. This prevents race conditions during parallel execution.

### 6.3 Circuit Breaker State Machine

```mermaid
stateDiagram-v2
    [*] --> Closed
    Closed --> Closed : recordSuccess()
    Closed --> Open : failureCount >= threshold
    Open --> HalfOpen : recoveryInterval elapsed
    HalfOpen --> Closed : recordSuccess()
    HalfOpen --> Open : recordFailure()
    Open --> Open : recoveryInterval not elapsed
```

**Defaults**: threshold=3, recoveryInterval=30s. Safety-gate agents that are circuit-broken trigger `failClosed()`.

### 6.4 Graph-Only Runtime

```mermaid
graph LR
    ROOT["root-command-graph"] --> ROUTE{"operation"}
    ROUTE -->|"executeDeviceCommand"| DIRECT["direct-command-graph or fallback graph"]
    ROUTE -->|"automationCreation"| AUTO["automation-creation-graph"]
    ROUTE -->|"unsupported"| UNSUP["unsupported-graph"]
    GP2["GraphPlanner"] --> ROOT
    GP2 --> DIRECT
    GP2 --> AUTO
    GP2 --> UNSUP
    DIRECT --> GS2["GraphScheduler"]
    AUTO --> GS2
    UNSUP --> GS2
```

Every command path now runs through `GraphPlanner`, `OperationGraphCatalog`, and `GraphScheduler`. The old phased runtime mode has been removed from active orchestration.

---

## 7. FM-First Agent Pattern

Every NLU worker session follows this pattern:

```mermaid
flowchart TD
    A["Input Text"] --> B{Mock detect closure?}
    B -->|Yes| C["Return mock result (testing)"]
    B -->|No| D["Compute rule-based result"]
    D --> E{FM Available?}
    E -->|No| F["Return rule-based result"]
    E -->|Yes| G["Build prompt with rule hint"]
    G --> H["FM inference"]
    H --> I{Safety preference check}
    I -->|"Rule=automationCreation AND Model=executeDeviceCommand"| J["Prefer rule (safety floor)"]
    I -->|Otherwise| K["Return model result"]
    H -->|Error| F
```

**Key design decision**: The rule-based result is always computed first and provided as a "hint" to the FM. For risk classification, the rule-based risk level serves as a **safety floor** — the FM cannot lower it.

---

## 8. Metrics & Observability

The `OrchestratorMetrics` struct captures 7 metric categories per run:

| Category | Key Fields |
|---|---|
| **Context** | commandCharacterCount, knowledgeSnippetCount, errorCount |
| **Safety** | safetyValidationRan, riskLevel, requiresConfirmation |
| **Candidates** | retrievedCount, hydratedCount, selectedCount, aggregationConfidence |
| **Automation** | operation, graphID, actionCount, conditionCount, compilationSupported |
| **FM Usage** | modelCallCount, skippedCount, contextWindowFailures, guardrailFailures |
| **Retrieval Quality** | strategyNames, averageScore, judgeInvoked, retryCount |
| **Graph Run** | nodeStatuses, nodeDurations, selectedAgents, skippedNodeIDs |

---

## 9. Optimization Analysis

### 9.1 Critical — Performance

| # | Issue | Location | Impact | Recommendation |
|---|---|---|---|---|
| **O-1** | **Redundant context snapshots in GraphScheduler** | `GraphScheduler.execute()` L51 + L111 | Two `await contextStore.snapshot()` calls per iteration — one for candidate filtering, one for the batch. The first snapshot is discarded. | Reuse the same snapshot for both candidate evaluation and batch execution within a single loop iteration. |
| **O-2** | **Agent timeout tuning** | `GraphScheduler.runNode()` | Every agent declares `timeoutNanoseconds` and the scheduler enforces it. Timeout values should continue to be calibrated for parallel action fan-out and FM latency. | Keep timeout enforcement in `withAgentTimeout`, tune per-agent limits, and monitor `agent.timeout` telemetry. |
| **O-3** | **Sequential condition operand resolution** | `AutomationConditionOperandResolver.resolveDraft()` | Condition operands are resolved sequentially. Multi-condition automations pay O(n) latency. | Parallelize operand resolution using `withTaskGroup`, similar to `AutomationActionResolver.resolveAll()`. |
| **O-4** | **Duplicate `stableUnique` implementations** | 4 copies across `HomeCommandOrchestrator`, `AutomationCreationResolver`, `AutomationActionResolutionAggregate` | Code duplication and maintenance risk. | Extract to a shared utility extension on `Array`. |

### 9.2 High — Architecture

| # | Issue | Location | Impact | Recommendation |
|---|---|---|---|---|
| **O-5** | **Duplicated `makeOperationState` factory** | `HomeCommandOrchestrator` L704, `AutomationCreationResolver` L591, `AutomationResultAssemblyAgent` L629 | Three identical 30-line methods. Any change must be synchronized across all three. | Extract to a shared static factory on `HomeResolutionState`. |
| **O-6** | **Root routing graph consolidation** | `HomeCommandOrchestrator`, `GraphPlanner` | Operation routing belongs to the same DAG-owned execution model as direct command and automation creation. | Keep operation detection as the first root graph node and avoid reintroducing pre-graph routing branches. |
| **O-7** | **`AgentEventBus` continuation leak potential** | `AgentEventBus.stream()` L72 | Continuations are appended but never cleaned up on cancellation. If a consumer task is cancelled, its continuation remains in the array, holding memory. | Register an `onTermination` handler on each continuation to remove it from the array. |
| **O-8** | **`ResolutionContextStore.apply()` is a linear chain of conditionals** | `ResolutionContextStore.apply()` L26-95 | 20+ sequential `if let` checks for every patch. Adding a new context field requires modifying this method. | Refactor to a registry-based approach: `[String: (AnySendableValue, inout ResolutionContext) -> Void]` mapping patch keys to typed applicators. |

### 9.3 Medium — Resilience

| # | Issue | Location | Impact | Recommendation |
|---|---|---|---|---|
| **O-9** | **No retry logic in GraphScheduler** | `GraphScheduler.runNode()` | `PolicyEngine.shouldRetry()` exists but is never called by the graph scheduler. Retryable failures are recorded but not retried. | Add a retry loop in `runNode()` that calls `policy.shouldRetry()` and re-executes with exponential backoff up to `maxRetries`. |
| **O-10** | **Circuit breaker state is not persisted** | `CircuitBreakerRegistry` | Circuit breakers reset on process restart. A persistently failing agent will re-trip on every cold start, causing latency spikes. | Persist circuit states to `UserDefaults` or a lightweight store; restore on init. |
| **O-11** | **`GraphScheduler` blocked-node detection is fragile** | `GraphScheduler.execute()` L57 | If all remaining nodes have unsatisfied dependencies but no cycle exists (e.g., a skipped node's dependents), the scheduler correctly detects the block but emits a `terminalFailure`. | Treat blocked nodes with `.optional` policy as skippable rather than terminal. |

### 9.4 Low — Observability & Maintainability

| # | Issue | Location | Impact | Recommendation |
|---|---|---|---|---|
| **O-12** | **`ResolutionContextPatchKey` uses raw strings** | `ResolutionContextPatchKey` | Typos in key strings cause silent data loss. No compile-time safety. | Convert to an enum with `rawValue` strings, or use `ScopedContextKey<T>` consistently for all fields. |
| **O-13** | **`OrchestratorMetrics` is monolithic** | `OrchestratorMetricsCollector.swift` (590 LOC) | Contains 7 nested metric structs, capture logic, confidence computation, and FM diagnostics in a single file. | Split into separate files per metric category. Extract `captureEvaluationFields` and `captureAutomationFields` into dedicated metric builders. |
| **O-14** | **Conversation memory reference detection is naive** | `ConversationMemoryReferenceDetector.containsMemoryReference()` | Simple token matching for ["it", "that", "same", "there"]. High false-positive rate (e.g., "put it there" triggers twice). | Use an FM-backed coreference resolution step, or at minimum add bigram context (e.g., "turn it" vs "it is"). |

---

## 10. Optimization Priority Matrix

```mermaid
quadrantChart
    title Impact vs Effort
    x-axis Low Effort --> High Effort
    y-axis Low Impact --> High Impact
    quadrant-1 Do First
    quadrant-2 Plan & Schedule
    quadrant-3 Quick Wins
    quadrant-4 Deprioritize

    O-2 Timeout enforcement: [0.35, 0.95]
    O-9 Retry logic: [0.40, 0.80]
    O-4 Deduplicate stableUnique: [0.10, 0.30]
    O-5 Deduplicate makeOperationState: [0.15, 0.40]
    O-1 Snapshot reuse: [0.15, 0.60]
    O-7 Continuation cleanup: [0.20, 0.55]
    O-6 Root routing consolidation: [0.35, 0.70]
    O-8 Patch applicator registry: [0.55, 0.50]
    O-3 Parallel condition resolution: [0.40, 0.45]
    O-12 Typed patch keys: [0.50, 0.35]
    O-13 Split metrics file: [0.30, 0.20]
    O-10 Persist circuit state: [0.45, 0.35]
    O-14 Better coreference: [0.75, 0.30]
    O-11 Optional blocked nodes: [0.30, 0.40]
```

### Recommended Execution Order

1. **O-2** — Add timeout enforcement (prevents hung pipelines)
2. **O-1** — Eliminate redundant snapshots (free performance win)
3. **O-7** — Fix continuation leak (memory safety)
4. **O-9** — Wire retry logic into GraphScheduler (resilience)
5. **O-5 + O-4** — Deduplicate shared code (maintainability)
6. **O-6** — Preserve graph-only root routing (reduce surface area)

---

## 11. File Dependency Graph

```mermaid
graph TB
    HCO["HomeCommandOrchestrator.swift"]
    CAA["ContextualAgentAdapters.swift"]
    ART["HomeAutomationAgents/AutomationRuntime"]
    ADE["HomeAutomationAgents/AutomationDraftExtraction"]
    AARAgent["HomeAutomationAgents/AutomationActionResolution"]
    ACRAgent["HomeAutomationAgents/AutomationConditionOperandResolution"]
    STC["HomeAutomationAgents/SmartThingsCompilation"]
    STRC["HomeAutomationAgents/SmartThingsRuleCreation"]
    ARAss["HomeAutomationAgents/AutomationResultAssembly"]
    GS["GraphScheduler.swift"]
    GP["GraphPlanner.swift"]
    OGC["OperationGraphCatalog.swift"]
    GV["GraphValidator.swift"]
    AReg["AgentRegistry.swift"]
    PE["OrchestratorPolicyEngine.swift"]
    RCS["ResolutionContextStore.swift"]
    CBR["CircuitBreakerRegistry.swift"]
    EB["HomeAutomationAgents/Runtime/AgentEventBus.swift"]
    CM["ConversationMemory.swift"]
    MC["OrchestratorMetricsCollector.swift"]
    ACR["Automation/Creation/AutomationCreationResolver.swift"]
    AAR["Automation/ActionResolution/AutomationActionResolver.swift"]
    OG["OrchestrationGraph.swift"]
    GRM["GraphRunMetrics.swift"]
    PCK["HomeAutomationAgents/Runtime/ResolutionContextPatchKey.swift"]

    HCO --> CAA & ART & ADE & AARAgent & ACRAgent & STC & STRC & ARAss & GS & GP & AReg & PE & RCS & CBR & EB & CM & MC & ACR & OG & GRM
    GS --> OG & AReg & RCS & EB & PE & CBR & GV & GRM
    GP --> OGC & OG
    ACR --> AAR & CAA
    AAR --> GS & AReg & PE & GP & CBR
    CAA --> AReg & PE & RCS
```

---

## 12. Glossary

| Term | Definition |
|---|---|
| **Agent** | A single-responsibility processing unit that reads `ResolutionContext` and produces a `ResolutionContextPatch` |
| **Safety Gate** | An agent whose failure triggers `failClosed()` — producing a safe-but-degraded resolution rather than continuing |
| **Resolution** | The final outcome: `readyToExecute`, `requiresConfirmation`, `needsClarification`, `unsupported`, `automationDrafted`, or `executed` |
| **Patch** | A typed dictionary update (`ResolutionContextPatch`) that an agent emits to update shared state |
| **Guard Condition** | A predicate on `GraphNode` that must be true for the node to execute (e.g., `contextKeyPresent("draft")`) |
| **Fan-out** | Parallel execution of independent graph nodes (e.g., Phase 1 NLU agents or Action + Condition resolution) |
| **FM-First** | Architecture where Foundation Model is the primary inference path, with deterministic rules as hints and fallbacks |
| **Safety Floor** | The principle that deterministic risk assessment cannot be lowered by the FM — only raised |
