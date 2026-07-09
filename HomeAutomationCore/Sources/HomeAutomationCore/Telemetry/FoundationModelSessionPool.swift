import Foundation
import FoundationModels
import os

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

    private let maxPoolSize: Int
    private var pools: [SessionKind: [LanguageModelSession]] = [:]
    private var instructionRegistry: [SessionKind: String] = [:]
    private let logger = Logger(subsystem: "HomeAutomation", category: "FM.SessionPool")

    public init(maxPoolSize: Int = 2) {
        self.maxPoolSize = max(1, maxPoolSize)
    }

    public func register(kind: SessionKind, instructions: String) {
        instructionRegistry[kind] = instructions
    }

    public func acquire(kind: SessionKind) -> LanguageModelSession {
        if var pool = pools[kind], !pool.isEmpty {
            let session = pool.removeLast()
            pools[kind] = pool
            logger.debug("[SessionPool] Reused session for \(kind.rawValue). Pool size: \(pool.count)")
            return session
        }
        logger.debug("[SessionPool] Creating new session for \(kind.rawValue)")
        return makeSession(kind: kind)
    }

    public func release(kind: SessionKind, session: LanguageModelSession) {
        var pool = pools[kind] ?? []
        guard pool.count < maxPoolSize else {
            logger.debug("[SessionPool] Pool full for \(kind.rawValue); discarding session.")
            return
        }
        pool.append(session)
        pools[kind] = pool
        logger.debug("[SessionPool] Released session for \(kind.rawValue). Pool size: \(pool.count)")
    }

    public func prewarm(kinds: [SessionKind]) {
        for kind in kinds {
            guard (pools[kind]?.count ?? 0) < maxPoolSize else { continue }
            let session = makeSession(kind: kind)
            var pool = pools[kind] ?? []
            pool.append(session)
            pools[kind] = pool
            logger.debug("[SessionPool] Pre-warmed session for \(kind.rawValue). Pool size: \(pool.count)")
        }
    }

    public func poolSize(for kind: SessionKind) -> Int {
        pools[kind]?.count ?? 0
    }

    private func makeSession(kind: SessionKind) -> LanguageModelSession {
        if let instructions = instructionRegistry[kind] {
            return LanguageModelSession(instructions: Instructions(instructions))
        }
        return LanguageModelSession()
    }
}
