import Foundation
import FoundationModels
import os

public enum FoundationModelSessionDiscardReason: String, Sendable, Codable, Hashable {
    case released
    case failed
    case overflowed
    case crossRunReuseDenied
}

public struct FoundationModelSessionFactorySnapshot: Sendable, Codable, Hashable {
    public let createdCount: Int
    public let prewarmCount: Int
    public let discardedCount: Int
    public let prewarmDigests: [String: String]

    public init(
        createdCount: Int,
        prewarmCount: Int,
        discardedCount: Int,
        prewarmDigests: [String: String]
    ) {
        self.createdCount = createdCount
        self.prewarmCount = prewarmCount
        self.discardedCount = discardedCount
        self.prewarmDigests = prewarmDigests
    }
}

public actor FoundationModelSessionFactory {
    public struct SessionKind: Hashable, Sendable {
        public let rawValue: String
        public init(_ rawValue: String) { self.rawValue = rawValue }

        public static let conditionClause = SessionKind("conditionClause")
        public static let triggerResolution = SessionKind("triggerResolution")
        public static let segmentation = SessionKind("segmentation")
        public static let verifier = SessionKind("verifier")
        public static let fragmentNLU = SessionKind("fragmentNLU")
    }

    private var instructionRegistry: [SessionKind: String] = [:]
    private var promptPrefixRegistry: [SessionKind: String] = [:]
    private var createdCount = 0
    private var prewarmCount = 0
    private var discardedCount = 0
    private var prewarmDigests: [String: String] = [:]
    private let logger = Logger(subsystem: "HomeAutomation", category: "FM.SessionFactory")

    public init() {}

    public func register(
        kind: SessionKind,
        instructions: String,
        promptPrefix: String? = nil
    ) {
        instructionRegistry[kind] = instructions
        promptPrefixRegistry[kind] = promptPrefix ?? instructions
    }

    public func makeSession(kind: SessionKind, runID: String? = nil) -> LanguageModelSession {
        createdCount += 1
        logger.debug("[SessionFactory] Creating fresh session for \(kind.rawValue, privacy: .public), runID=\(runID ?? "none", privacy: .public)")
        if let instructions = instructionRegistry[kind] {
            return LanguageModelSession(instructions: Instructions(instructions))
        }
        return LanguageModelSession()
    }

    public func prewarm(kinds: [SessionKind]) {
        for kind in kinds {
            let session = makeSession(kind: kind)
            let prefix = promptPrefixRegistry[kind] ?? instructionRegistry[kind] ?? ""
            session.prewarm(promptPrefix: prefix.isEmpty ? nil : Prompt(prefix))
            prewarmCount += 1
            prewarmDigests[kind.rawValue] = FoundationModelBatchCompatibilityKey.stableDigest(prefix)
            logger.debug("[SessionFactory] Prewarmed prefix for \(kind.rawValue, privacy: .public)")
        }
    }

    public func discard(kind: SessionKind, reason: FoundationModelSessionDiscardReason) {
        discardedCount += 1
        logger.debug("[SessionFactory] Discarded session for \(kind.rawValue, privacy: .public), reason=\(reason.rawValue, privacy: .public)")
    }

    public func snapshot() -> FoundationModelSessionFactorySnapshot {
        FoundationModelSessionFactorySnapshot(
            createdCount: createdCount,
            prewarmCount: prewarmCount,
            discardedCount: discardedCount,
            prewarmDigests: prewarmDigests
        )
    }
}

public extension FoundationModelSessionFactory.SessionKind {
    init(_ legacyKind: FoundationModelSessionPool.SessionKind) {
        self.init(legacyKind.rawValue)
    }
}
