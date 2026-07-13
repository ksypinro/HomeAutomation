import Foundation
import FoundationModels
import os

/// Backward-compatible facade for Phase III callers.
///
/// Phase 8 intentionally stops pooling `LanguageModelSession` transcripts
/// across unrelated requests. `acquire` now creates a fresh instruction-scoped
/// session every time, `release` discards it, and `prewarm` delegates to real
/// `LanguageModelSession.prewarm(promptPrefix:)` through
/// `FoundationModelSessionFactory`.
public actor FoundationModelSessionPool {
    public struct SessionKind: Hashable, Sendable {
        public let rawValue: String
        public init(_ rawValue: String) { self.rawValue = rawValue }

        public static let conditionClause = SessionKind("conditionClause")
        public static let triggerResolution = SessionKind("triggerResolution")
        public static let segmentation = SessionKind("segmentation")
        public static let verifier = SessionKind("verifier")
        public static let fragmentNLU = SessionKind("fragmentNLU")
    }

    private let factory: FoundationModelSessionFactory
    private var checkedOutCountByKind: [SessionKind: Int] = [:]
    private let logger = Logger(subsystem: "HomeAutomation", category: "FM.SessionPool")

    public init(maxPoolSize: Int = 2, factory: FoundationModelSessionFactory = FoundationModelSessionFactory()) {
        _ = maxPoolSize
        self.factory = factory
    }

    public func register(kind: SessionKind, instructions: String, promptPrefix: String? = nil) async {
        await factory.register(
            kind: FoundationModelSessionFactory.SessionKind(kind),
            instructions: instructions,
            promptPrefix: promptPrefix
        )
    }

    public func acquire(kind: SessionKind, runID: String? = nil) async -> LanguageModelSession {
        checkedOutCountByKind[kind, default: 0] += 1
        logger.debug("[SessionPool] Creating fresh non-pooled session for \(kind.rawValue, privacy: .public)")
        return await factory.makeSession(
            kind: FoundationModelSessionFactory.SessionKind(kind),
            runID: runID
        )
    }

    public func release(kind: SessionKind, session: LanguageModelSession) async {
        _ = session
        checkedOutCountByKind[kind] = max(0, (checkedOutCountByKind[kind] ?? 0) - 1)
        await factory.discard(
            kind: FoundationModelSessionFactory.SessionKind(kind),
            reason: .released
        )
    }

    public func discard(kind: SessionKind, session: LanguageModelSession, reason: FoundationModelSessionDiscardReason) async {
        _ = session
        checkedOutCountByKind[kind] = max(0, (checkedOutCountByKind[kind] ?? 0) - 1)
        await factory.discard(
            kind: FoundationModelSessionFactory.SessionKind(kind),
            reason: reason
        )
    }

    public func prewarm(kinds: [SessionKind]) async {
        await factory.prewarm(kinds: kinds.map(FoundationModelSessionFactory.SessionKind.init))
    }

    /// Always zero because Phase 8 no longer stores stateful sessions for
    /// future requests.
    public func poolSize(for kind: SessionKind) -> Int {
        _ = kind
        return 0
    }

    public func checkedOutCount(for kind: SessionKind) -> Int {
        checkedOutCountByKind[kind] ?? 0
    }

    public func snapshot() async -> FoundationModelSessionFactorySnapshot {
        await factory.snapshot()
    }
}
