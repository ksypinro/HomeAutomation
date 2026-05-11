# Hybrid Agentic RAG — Part 3: Roadmap & Verification

## 8. Phased Implementation Roadmap

> [!TIP]
> Each phase is independently shippable and testable. Phase 1 alone delivers significant improvement with zero latency cost.

### Phase 1: Quick Wins (No Latency Cost)

**Goal**: Fix the worst retrieval issues without adding any new infrastructure.

| Task | File | Change |
|---|---|---|
| Dual-encoder chunking | `DocumentChunk.swift` | Add `semanticContent` field |
| Separate semantic content | `DocumentChunker.swift` | Populate `semanticContent` with clean text only |
| Embed semantic field | `KnowledgeIndexer.swift` | Embed `semanticContent` instead of `content` |
| Score threshold | `VectorStore.swift` | Add `minScore` parameter to `query()` |
| Score threshold (caller) | `ContextRetriever.swift` | Pass `minScore` through to VectorStore |
| Auto-expand synonyms | `EmbeddingProvider.swift` | Build synonyms from knowledge base at index time |
| Cache invalidation | `VectorIndexCache.swift` | Bump version format to invalidate stale dual-field caches |

**Expected impact**:
- NL dataset retrieval accuracy: **+25-40%** (metadata dilution eliminated)
- Garbage result injection: **eliminated** (score gating)
- TF-IDF offline recall: **+30-50%** (synonym expansion)

**Latency impact**: Zero. These are indexing-time changes.

---

### Phase 2: Hybrid Search (BM25 + Semantic Fusion)

**Goal**: Add keyword search and rank fusion for commands that mix NL with technical terms.

| Task | File | Change |
|---|---|---|
| BM25 index | `BM25Index.swift` [NEW] | Sparse inverted index with BM25 scoring |
| Hybrid strategy | `HybridRetrievalStrategy.swift` [NEW] | RRF fusion of semantic + BM25 results |
| Structured query | `StructuredRetrievalQuery.swift` [NEW] | Rich query type with strategy selection |
| Strategy-aware retriever | `ContextRetriever.swift` | Add `retrieve(StructuredRetrievalQuery)` overload |
| Index BM25 at startup | `KnowledgeIndexer.swift` | Build BM25 index alongside vector store |

**Expected impact**:
- Exact term matching (capability IDs, commands): **+60-80%**
- Mixed NL+technical queries (*"set switchLevel to 50"*): **+40%**

**Latency impact**: ~2-5ms per query (BM25 is extremely fast). RRF merge is O(K).

---

### Phase 3: NLU-Informed Retrieval

**Goal**: Wire NLU Phase 1 outputs into Knowledge Agent retrieval queries.

| Task | File | Change |
|---|---|---|
| Intent→capability map | `IntentCapabilityMap.swift` [NEW] | Static mapping from intent families to capability IDs |
| NLU hints type | `StructuredRetrievalQuery.swift` | Add `NLURetrievalHints` struct |
| CapabilityKnowledge reads NLU | `CapabilityKnowledgeAgent.swift` | Build structured query using `context.resolutionState` |
| BixbyKnowledge reads NLU | `BixbyKnowledgeAgent.swift` | Pre-filter by device type from NLU |
| CommandExample reads NLU | `CommandExampleAgent.swift` | Pre-filter by device type, use semantic-only strategy |
| Metadata enrichment | `DocumentChunker.swift` | Add `relatedDeviceTypes` to capability chunk metadata |

**Expected impact**:
- Cross-domain false positives: **-70%** (thermostat results for light commands eliminated)
- Candidate retrieval precision: **+30%**

**Latency impact**: Zero additional (NLU already computed in Phase 1 of the pipeline).

---

### Phase 4: Agentic RAG (FM-Judged Retrieval)

**Goal**: Add Foundation Model reasoning for ambiguous/poor retrievals.

| Task | File | Change |
|---|---|---|
| Judge agent | `RetrievalJudgeAgent.swift` [NEW] | FM evaluates retrieval quality, suggests reformulation |
| Judge input/output | `RetrievalJudgeTypes.swift` [NEW] | Input/output types for judge |
| Agent ID | `AgentCapability.swift` | Add `.retrievalJudge` to `AgentID` |
| Agent registration | `DefaultAgentRegistryFactory` | Register `RetrievalJudgeAgent` |
| Conditional planning | `AgentPlanner.swift` | Add optional Phase 2b for judge |
| Query reformulation | `QueryReformulator.swift` [NEW] | Reformulation strategies (synonym expansion, HyDE, decomposition) |
| Retrieval metrics | `OrchestratorMetrics.swift` | Track retrieval quality scores and retry counts |

**Expected impact**:
- Ambiguous command resolution: **+50-70%** (*"make it cozy"*, *"do the usual"*)
- Abstract intent handling: **new capability** (currently fails completely)

**Latency impact**: 
- Fast path (high scores): **0ms** (FM not invoked)
- Slow path (low scores): **+200-500ms** (one FM call for judgment + one retrieval retry)

> [!WARNING]
> Phase 4 requires Foundation Model availability. The judge must have a deterministic fallback (accept results as-is) when FM is unavailable, matching the existing policy pattern.

---

## 9. Complete File Inventory

### New Files (7)

| File | Module | Purpose |
|---|---|---|
| `StructuredRetrievalQuery.swift` | HomeAutomationRAG | Rich query type with NLU hints and strategy |
| `BM25Index.swift` | HomeAutomationRAG | Sparse keyword search index |
| `HybridRetrievalStrategy.swift` | HomeAutomationRAG | RRF fusion of semantic + BM25 |
| `IntentCapabilityMap.swift` | HomeAutomationCore | Intent family → capability ID mapping |
| `RetrievalJudgeAgent.swift` | HomeAutomationAgents/Knowledge | FM-judged retrieval quality |
| `RetrievalJudgeTypes.swift` | HomeAutomationAgents/Knowledge | Input/output types for judge |
| `QueryReformulator.swift` | HomeAutomationRAG | Query reformulation strategies |

### Modified Files (9)

| File | Module | Change Summary |
|---|---|---|
| `DocumentChunk.swift` | RAG | Add `semanticContent` field |
| `DocumentChunker.swift` | RAG | Populate `semanticContent`, enrich metadata |
| `VectorStore.swift` | RAG | Add `minScore` parameter |
| `ContextRetriever.swift` | RAG | Add structured query overload, hybrid strategy |
| `KnowledgeIndexer.swift` | RAG | Embed semantic field, build BM25 index |
| `EmbeddingProvider.swift` | RAG | Auto-expand synonyms from knowledge base |
| `CapabilityKnowledgeAgent.swift` | Agents | NLU-informed structured queries |
| `BixbyKnowledgeAgent.swift` | Agents | NLU-informed device type pre-filtering |
| `CommandExampleAgent.swift` | Agents | Device type pre-filter, semantic-only strategy |
| `AgentPlanner.swift` | Orchestrator | Conditional Phase 2b for retrieval judge |

---

## 10. Verification Plan

### 10.1 Test Matrix — Natural Language Commands

These 20 commands represent the failure modes the current system struggles with:

| # | Command | Why Current RAG Fails | Expected Fix Phase |
|---|---|---|---|
| 1 | *"Make it warmer"* | "warmer" has no TF-IDF synonym | Phase 1 (synonyms) |
| 2 | *"I'm freezing"* | Abstract intent, no direct keyword match | Phase 4 (judge reformulates) |
| 3 | *"Dim the lights to 30"* | Metadata dilution buries "dim the lights" | Phase 1 (dual-encoder) |
| 4 | *"Turn off everything except bedroom"* | Negation/multi-device, single retrieval pass | Phase 4 (decomposition) |
| 5 | *"Set thermostat to 22"* | "thermostat" keyword match needed | Phase 2 (BM25) |
| 6 | *"Make the living room cozy"* | Abstract intent mapping | Phase 4 (agentic) |
| 7 | *"Lock the front door"* | Works OK today, should not regress | All phases |
| 8 | *"Play some jazz"* | Media intent, specific device type needed | Phase 3 (NLU-informed) |
| 9 | *"Check if the garage is open"* | Status query + specific device type | Phase 3 (intent→cap) |
| 10 | *"Crank up the heat"* | Colloquial language, no keyword match | Phase 1 (synonyms) + Phase 4 |
| 11 | *"선풍기 켜 줘"* (Korean: turn on fan) | Multilingual, TF-IDF fails completely | Phase 2 (semantic) |
| 12 | *"AC를 24도로"* (Korean: AC to 24°) | Multilingual + numeric extraction | Phase 2 + Phase 3 |
| 13 | *"Do what you did last time"* | Memory reference, no static RAG match | Phase 4 (reformulation) |
| 14 | *"switchLevel setLevel 75"* | Pure technical terms, semantic embedding poor | Phase 2 (BM25) |
| 15 | *"Bedroom light brightness"* | Mixed NL + technical | Phase 2 (hybrid) |
| 16 | *"Close the blinds"* | "blinds" → windowShade mapping needed | Phase 1 (synonyms) |
| 17 | *"Set movie scene"* | Routine/scene intent | Phase 3 (NLU-informed) |
| 18 | *"Turn up the TV"* vs *"Turn on the TV"* | Subtle intent difference (volume vs power) | Phase 1 (dual-encoder) |
| 19 | *"Is the baby room warm enough?"* | Status query + room + temperature | Phase 3 (NLU cross) |
| 20 | *"꺼"* (Korean: "off", single word) | Minimal context, ambiguous | Phase 4 (judge requests context) |

### 10.2 Automated Verification

```bash
# Phase 1: Unit tests for dual-encoder chunking
swift test --filter DocumentChunkerTests    # verify semanticContent populated
swift test --filter VectorStoreTests        # verify minScore filtering
swift test --filter TFIDFSynonymTests       # verify auto-expanded synonyms

# Phase 2: BM25 integration tests
swift test --filter BM25IndexTests          # verify keyword retrieval
swift test --filter HybridRetrievalTests    # verify RRF fusion

# Phase 3: NLU-informed retrieval tests
swift test --filter CapabilityKnowledgeAgentTests  # verify NLU context usage
swift test --filter CommandExampleAgentTests        # verify device type pre-filter

# Phase 4: Agentic judge tests
swift test --filter RetrievalJudgeTests     # verify fast path + FM path

# Full integration: run orchestrator with all 20 test commands
swift test --filter OrchestratorRAGIntegrationTests
```

### 10.3 Latency Budgets

| Scenario | Current | Phase 1 | Phase 2 | Phase 3 | Phase 4 |
|---|---|---|---|---|---|
| Common command (clear intent) | ~50ms | ~45ms | ~52ms | ~52ms | ~52ms |
| Ambiguous command | ~50ms | ~45ms | ~52ms | ~52ms | ~300ms |
| FM unavailable (TF-IDF fallback) | ~15ms | ~12ms | ~18ms | ~18ms | ~18ms |
| App startup indexing | ~1.5s | ~1.6s | ~1.8s | ~1.8s | ~1.8s |

> [!NOTE]
> Phase 4 latency increase only hits the **slow path** (poor initial retrieval). The fast path — which covers 80%+ of commands — adds zero latency.

---

## 11. Strategy Comparison: Current vs. Proposed

| Dimension | Current (Passive RAG) | Proposed (Hybrid Agentic RAG) |
|---|---|---|
| **Retrieval** | Single-shot cosine similarity | Multi-strategy: semantic + BM25 + FM-judged |
| **Query Construction** | Raw user text | NLU-enriched structured query |
| **Cross-Source** | Isolated per-source | Intent→capability mapping, cross-source correlation |
| **Score Handling** | Return top-K regardless | Score-gated, confidence-aware injection |
| **Failure Recovery** | None | FM-driven query reformulation and retry |
| **Chunk Embedding** | Full content with boilerplate | Clean semantic content only |
| **TF-IDF Coverage** | 16 hardcoded synonyms | Auto-generated from knowledge base (~200+ entries) |
| **Abstract Commands** | Fails silently | FM decomposes and reformulates |
| **Multilingual** | TF-IDF fails, semantic may work | Hybrid ensures at least one strategy works |

---

## 12. Open Questions for Review

> [!IMPORTANT]
> **Q1: Phase 4 FM Budget** — The RetrievalJudgeAgent makes an additional Foundation Model call on the slow path. Should we share token budget with existing NLU agents, or allocate a separate budget? The judge prompt is small (~200 tokens input, ~50 tokens output).

> [!IMPORTANT]  
> **Q2: BM25 Memory Footprint** — The BM25 inverted index duplicates some data already in VectorStore. For the current catalog size (~500-1000 chunks) this is negligible (<1MB). Should we plan for a shared storage layer, or keep them independent for simplicity?

> [!IMPORTANT]
> **Q3: Implementation Priority** — Phase 1 is the clear first step. But between Phase 2 (Hybrid Search) and Phase 3 (NLU-Informed), which would you prioritize? Phase 2 helps technical/keyword queries; Phase 3 helps cross-domain precision.

> [!IMPORTANT]
> **Q4: Retrieval Metrics Dashboard** — Should we expose retrieval quality scores (avg score, retry count, strategy used) through the existing `OrchestratorMetrics` pipeline for the diagnostic dashboard?

---

## Summary

This plan transforms the RAG system from a **passive single-shot retrieval pipe** into an **intelligent, multi-strategy, self-correcting knowledge engine**. The four phases build incrementally:

1. **Phase 1** (Quick Wins): Fix chunk embeddings, add score gating, expand synonyms — **zero latency cost, highest ROI**
2. **Phase 2** (Hybrid Search): Add BM25 keyword search with RRF fusion — **catches what semantic search misses**
3. **Phase 3** (NLU-Informed): Wire NLU outputs into retrieval queries — **precision boost via cross-domain reasoning**  
4. **Phase 4** (Agentic RAG): FM-judged retrieval with reformulation — **handles the hardest commands**

Please review and let me know your thoughts on the open questions. I can begin implementation once you approve.
