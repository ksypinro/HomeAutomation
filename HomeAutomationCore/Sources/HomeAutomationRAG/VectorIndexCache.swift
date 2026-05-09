import Foundation

// MARK: - Snapshot types

/// A snapshot of the TFIDF vocabulary and document statistics required to embed
/// new queries against a previously-built corpus without retraining from scratch.
public struct TFIDFVocabularySnapshot: Codable, Sendable, Equatable {
    public let vocabulary: [String: Int]
    public let documentFrequency: [String: Int]
    public let documentCount: Int

    public init(vocabulary: [String: Int], documentFrequency: [String: Int], documentCount: Int) {
        self.vocabulary = vocabulary
        self.documentFrequency = documentFrequency
        self.documentCount = documentCount
    }
}

/// A single persisted vector-store entry: the document chunk and its dense embedding.
public struct VectorStoreEntry: Codable, Sendable, Equatable {
    public let chunk: DocumentChunk
    public let embedding: [Float]

    public init(chunk: DocumentChunk, embedding: [Float]) {
        self.chunk = chunk
        self.embedding = embedding
    }
}

/// The full persisted index: all entries, the TFIDF vocabulary, and a version tag.
///
/// The `version` string is compared on load. If it does not match the currently
/// computed version, the cache is considered stale and the index is rebuilt.
public struct VectorIndexSnapshot: Codable, Sendable, Equatable {
    public let version: String
    public let entries: [VectorStoreEntry]
    public let tfidfVocabulary: TFIDFVocabularySnapshot?

    public init(
        version: String,
        entries: [VectorStoreEntry],
        tfidfVocabulary: TFIDFVocabularySnapshot?
    ) {
        self.version = version
        self.entries = entries
        self.tfidfVocabulary = tfidfVocabulary
    }
}

// MARK: - Cache actor

/// Persists and loads the RAG vector index snapshot to/from the OS caches directory.
///
/// **Strategy**:
/// 1. On first launch (or after a knowledge-base update), `KnowledgeIndexer` builds the
///    index normally and calls `save(_:)` — writing a `VectorIndexSnapshot` JSON file.
/// 2. On subsequent launches, `load(expectedVersion:)` reads the file and verifies the
///    version tag. If it matches, the index is restored instantly (~10 ms); if it does not,
///    `nil` is returned so the caller rebuilds and saves a fresh snapshot.
///
/// **Storage location**: `<Caches>/HomeAutomationRAG/rag_vector_index.json`  
/// This directory is safe for regeneratable cache data and is excluded from iCloud backup.
public actor VectorIndexCache {
    private let fileURL: URL
    private var pendingSave: Task<Void, Never>?

    public static let defaultFileName = "rag_vector_index.json"
    public static let defaultSubdirectory = "HomeAutomationRAG"

    /// Creates a cache pointing to `<Caches>/<subdirectory>/<fileName>`.
    public init(fileName: String = defaultFileName, subdirectory: String = defaultSubdirectory) {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directoryURL = cachesURL.appendingPathComponent(subdirectory, isDirectory: true)
        self.fileURL = directoryURL.appendingPathComponent(fileName)
    }

    /// Creates a cache pointing to a specific URL — useful for testing.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    // MARK: - Public API

    /// Loads a previously saved snapshot if the version matches `expectedVersion`.
    ///
    /// - Returns: The snapshot when the file exists and the version matches; `nil` otherwise.
    public func load(expectedVersion: String) -> VectorIndexSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try JSONDecoder().decode(VectorIndexSnapshot.self, from: data)
            guard snapshot.version == expectedVersion else {
                return nil
            }
            return snapshot
        } catch {
            return nil
        }
    }

    /// Saves a snapshot to disk, creating the parent directory if needed.
    ///
    /// Silently no-ops if the write fails (index will be rebuilt on the next launch).
    public func save(_ snapshot: VectorIndexSnapshot) async {
        let task = Self.makeSaveTask(snapshot, to: fileURL, priority: .utility)
        pendingSave = task
        await task.value
        pendingSave = nil
    }

    /// Starts a best-effort background save and returns immediately.
    public func saveInBackground(_ snapshot: VectorIndexSnapshot) {
        pendingSave = Self.makeSaveTask(snapshot, to: fileURL, priority: .background)
    }

    /// Waits for a background save kicked off by `saveInBackground`, if any.
    public func waitForPendingSave() async {
        await pendingSave?.value
        pendingSave = nil
    }

    /// Deletes the cached snapshot. Useful when forcing a rebuild in tests or after
    /// a knowledge-base schema migration.
    public func invalidate() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Returns the URL of the cache file — primarily useful for debugging and tests.
    public var cacheFileURL: URL { fileURL }

    private nonisolated static func makeSaveTask(
        _ snapshot: VectorIndexSnapshot,
        to fileURL: URL,
        priority: TaskPriority
    ) -> Task<Void, Never> {
        Task.detached(priority: priority) {
            write(snapshot, to: fileURL)
        }
    }

    private nonisolated static func write(_ snapshot: VectorIndexSnapshot, to fileURL: URL) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Non-fatal: the index will be rebuilt on the next launch.
        }
    }
}

// MARK: - Version computation

/// Computes a deterministic version string for the knowledge base that changes whenever
/// the underlying content changes. The version is derived from:
/// - The `HomeAutomationKnowledgeBase` schema version
/// - The Bixby catalog command count
/// - The generated dataset command count
/// - The device registry device count
///
/// This keeps version computation fast (no hashing of content) while still being
/// sensitive to the most common causes of index staleness.
public enum RAGIndexVersion {
    public static func compute(
        knowledgeBaseSchemaVersion: String,
        bixbyCommandCount: Int,
        datasetCommandCount: Int,
        deviceCount: Int
    ) -> String {
        "\(knowledgeBaseSchemaVersion)-b\(bixbyCommandCount)-d\(datasetCommandCount)-v\(deviceCount)"
    }
}
