import Foundation
import HomeAutomationCore

public enum GraphInterruptKind: String, Sendable, Hashable, Codable {
    case confirmation
    case externalMutationApproval
}

public struct GraphInterrupt: Sendable, Hashable, Codable {
    public let kind: GraphInterruptKind
    public let reason: String

    public init(kind: GraphInterruptKind, reason: String) {
        self.kind = kind
        self.reason = reason
    }
}

public struct GraphCheckpointRecord: Sendable, Hashable, Codable {
    public let runID: String
    public let graphID: String
    public let goal: String
    public let completedNodeIDs: [String]
    public let pendingNodeIDs: [String]
    public let lastCompletedNodeID: String?
    public let interruptedBeforeNodeID: String?
    public let interrupt: GraphInterrupt?
    public let contextKeys: [String]
    public let createdAt: Date

    public init(
        runID: String,
        graphID: String,
        goal: String,
        completedNodeIDs: [String],
        pendingNodeIDs: [String],
        lastCompletedNodeID: String?,
        interruptedBeforeNodeID: String? = nil,
        interrupt: GraphInterrupt? = nil,
        contextKeys: [String],
        createdAt: Date = Date()
    ) {
        self.runID = runID
        self.graphID = graphID
        self.goal = goal
        self.completedNodeIDs = completedNodeIDs.sorted()
        self.pendingNodeIDs = pendingNodeIDs.sorted()
        self.lastCompletedNodeID = lastCompletedNodeID
        self.interruptedBeforeNodeID = interruptedBeforeNodeID
        self.interrupt = interrupt
        self.contextKeys = contextKeys.sorted()
        self.createdAt = createdAt
    }
}

public protocol GraphCheckpointPersisting: Sendable {
    func save(_ checkpoint: GraphCheckpointRecord) async
    func latest(runID: UUID) async -> GraphCheckpointRecord?
}

public actor InMemoryGraphCheckpointStore: GraphCheckpointPersisting {
    private var checkpoints: [String: GraphCheckpointRecord] = [:]

    public init() {}

    public func save(_ checkpoint: GraphCheckpointRecord) async {
        checkpoints[checkpoint.runID] = checkpoint
    }

    public func latest(runID: UUID) async -> GraphCheckpointRecord? {
        checkpoints[runID.uuidString]
    }
}

public actor FileGraphCheckpointStore: GraphCheckpointPersisting {
    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func save(_ checkpoint: GraphCheckpointRecord) async {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(checkpoint)
            try data.write(to: fileURL(runID: checkpoint.runID), options: [.atomic])
        } catch {
            // Checkpoint persistence must not break command resolution.
        }
    }

    public func latest(runID: UUID) async -> GraphCheckpointRecord? {
        do {
            let data = try Data(contentsOf: fileURL(runID: runID.uuidString))
            return try decoder.decode(GraphCheckpointRecord.self, from: data)
        } catch {
            return nil
        }
    }

    private func fileURL(runID: String) -> URL {
        directoryURL.appendingPathComponent("\(runID).json", isDirectory: false)
    }
}

public struct GraphSchedulerExecutionOptions: Sendable {
    public let checkpointStore: (any GraphCheckpointPersisting)?
    public let resumeFromCheckpoint: GraphCheckpointRecord?
    public let pauseAtInterrupts: Bool
    public let interruptBeforeNodeIDs: Set<String>
    public let criticalPath: GraphCriticalPathMetadata?
    public let foundationModelSchedulerMode: FoundationModelSchedulerMode

    public init(
        checkpointStore: (any GraphCheckpointPersisting)? = nil,
        resumeFromCheckpoint: GraphCheckpointRecord? = nil,
        pauseAtInterrupts: Bool = false,
        interruptBeforeNodeIDs: Set<String> = [],
        criticalPath: GraphCriticalPathMetadata? = nil,
        foundationModelSchedulerMode: FoundationModelSchedulerMode = .legacy
    ) {
        self.checkpointStore = checkpointStore
        self.resumeFromCheckpoint = resumeFromCheckpoint
        self.pauseAtInterrupts = pauseAtInterrupts
        self.interruptBeforeNodeIDs = interruptBeforeNodeIDs
        self.criticalPath = criticalPath
        self.foundationModelSchedulerMode = foundationModelSchedulerMode
    }

    func shouldInterrupt(before node: GraphNode) -> Bool {
        interruptBeforeNodeIDs.contains(node.id) || (pauseAtInterrupts && node.interrupt != nil)
    }
}
