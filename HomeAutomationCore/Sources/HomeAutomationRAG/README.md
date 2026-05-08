# HomeAutomationRAG Source Module

`HomeAutomationRAG` is the retrieval layer for the home-automation resolver. It indexes canonical knowledge into small chunks and returns relevant context to agents without forcing every prompt to include the entire catalog.

This module answers the question: "Which small pieces of trusted context are relevant to this command or agent?"

## Architecture Role

```mermaid
flowchart TB
    subgraph Sources["Canonical Sources"]
        Capabilities["Capability Catalog"]
        Dataset["Generated NL Dataset"]
        Bixby["Bixby Command Catalog"]
        Devices["Mock Device Records"]
    end

    Chunker["DocumentChunker"]
    Embedder["EmbeddingProvider"]
    Store["VectorStore"]
    Indexer["KnowledgeIndexer"]
    Retriever["ContextRetriever"]
    Agents["HomeAutomationAgents"]

    Sources --> Chunker
    Chunker --> Embedder
    Embedder --> Store
    Indexer --> Chunker
    Indexer --> Store
    Agents --> Retriever
    Retriever --> Store
    Store --> Retriever
```

## Indexing Flow

```mermaid
flowchart LR
    A["HomeAutomationKnowledgeBase"] --> B["Capability chunks"]
    A --> C["Generated command example chunks"]
    D["HomeBixbyCommandCatalog"] --> E["Bixby command chunks"]
    F["MockHomeDeviceRegistry"] --> G["Device chunks"]
    B --> H["KnowledgeIndexer"]
    C --> H
    E --> H
    G --> H
    H --> I["Embedding provider prepares corpus"]
    I --> J["VectorStore indexes chunks"]
```

## Query Flow

```mermaid
flowchart TD
    A["Agent query"] --> B["ContextRetriever.retrieve"]
    B --> C["MetadataFilter optional source/scope restriction"]
    C --> D["VectorStore similarity search"]
    D --> E["ScoredChunk results"]
    E --> F["Agent hydrates canonical details from HomeAutomationCore"]
```

## Component Details

| Component | Role |
| --- | --- |
| `DocumentChunk` | Identifiable unit of retrievable knowledge. It stores content, source, and metadata. |
| `KnowledgeSource` | Enum that identifies chunk origin: capability, natural-language dataset, Bixby command, or device. |
| `ScoredChunk` | Result wrapper containing a chunk and similarity score. |
| `MetadataFilter` | Optional source and metadata constraints for retrieval. |
| `DocumentChunker` | Converts capabilities, generated examples, Bixby commands, and device records into chunk lists. |
| `EmbeddingProviding` | Protocol for converting text into vector embeddings. |
| `CorpusAwareEmbeddingProviding` | Embedding protocol for providers that can prepare themselves from the full corpus before indexing. |
| `TFIDFEmbeddingProvider` | Deterministic local embedding provider. Good for tests, offline operation, and reproducible fallback behavior. |
| `SemanticEmbeddingProvider` | Semantic provider wrapper for production-grade embeddings when available. |
| `FallbackEmbeddingProvider` | Attempts semantic vectors and falls back to TF-IDF when semantic embeddings are unavailable or empty. |
| `VectorStore` | Actor-backed in-memory vector index. Stores chunks, vectors, and supports top-k cosine similarity search. |
| `KnowledgeIndexer` | Builds the complete index from canonical sources at app launch or orchestrator initialization. |
| `KnowledgeIndexingResult` | Summary of indexed chunks and source counts. |
| `ContextRetriever` | Public retrieval API consumed by agents. |
| `cosineSimilarity` | Shared vector similarity function. |

## Source Types and Metadata

| Source | Chunk Granularity | Important Metadata | Typical Consumers |
| --- | --- | --- | --- |
| Capability catalog | One chunk per capability | Capability name, commands, risk, attributes, enum/range hints | `CapabilityKnowledgeAgent`, `InstructionComposerAgent`, safety-aware prompts |
| Generated command dataset | One chunk per example | Language, device type, capability, command, risk, expected values | NLU agents, `CommandExampleAgent`, instruction composition |
| Bixby command catalog | One chunk per Bixby command | Source capability, action, method, access level | `BixbyKnowledgeAgent`, `BixbyFallbackAgent` |
| Device registry | One chunk per device/routine | Device ID, room, type, capabilities, risk | `CandidateRetrievalAgent` |

## Retrieval Invariants

- RAG ranks and narrows context; it never becomes the final authority for capability support or safety.
- Agents must hydrate final capability, device, Bixby, and risk facts from `HomeAutomationCore`.
- Metadata filters should be used when an agent needs a specific source, such as only generated examples or only device chunks.
- The index is safe to rebuild from canonical sources because chunks are derived, not manually authored truth.
- Deterministic TF-IDF fallback preserves testability and offline behavior.

## Operational Notes

- `HomeCommandOrchestrator.makeRAGEnabled` creates a `KnowledgeIndexer`, indexes canonical knowledge, builds a `ContextRetriever`, and injects that retriever into the default agent registry.
- Retrieval scores are used for ranking and prompt selection. Low scores should reduce influence rather than bypass deterministic fallback.
- The vector store is in memory, so app startup indexing cost and memory use should be watched as catalogs grow.
