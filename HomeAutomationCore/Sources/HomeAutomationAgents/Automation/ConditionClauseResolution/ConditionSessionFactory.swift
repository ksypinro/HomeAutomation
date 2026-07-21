import Foundation
import FoundationModels
import HomeAutomationCore
import os

/// Shared session factory for single and batch condition resolution.
/// Manages session reuse, prompt budgeting, and deterministic candidate retention.
public struct ConditionSessionFactory: Sendable {
    private let logger = Logger(subsystem: "HomeAutomation", category: "ConditionSession")
    private let sessionPool: FoundationModelSessionPool?
    private let batchPromptBudget = ConditionBatchSessionContext.maxPromptCharacters

    public init(sessionPool: FoundationModelSessionPool? = nil) {
        self.sessionPool = sessionPool
    }

    /// Acquire or create a session for single-condition resolution.
    /// Prefers lazy reuse from pool if available.
    public func acquireSingleConditionSession() async -> LanguageModelSession? {
        guard let pool = sessionPool else { return nil }
        return await pool.acquire(kind: .conditionClause)
    }

    /// Release single-condition session back to pool.
    public func releaseSingleConditionSession(_ session: LanguageModelSession) async {
        guard let pool = sessionPool else { return }
        await pool.release(kind: .conditionClause, session: session)
    }

    /// Discard failed single-condition session from pool.
    public func discardSingleConditionSession(_ session: LanguageModelSession, reason: FoundationModelSessionDiscardReason) async {
        guard let pool = sessionPool else { return }
        await pool.discard(kind: .conditionClause, session: session, reason: reason)
    }

    /// Create batch session context for condition residuals.
    /// Enforces hard prompt budget and determines reuse strategy.
    public func createBatchContext(
        residualInputs: [AutomationConditionClauseResolutionInput],
        instructionCharacters: Int
    ) -> ConditionBatchSessionContext {
        let allDevices = residualInputs
            .flatMap(\.availableDevices)
        let uniqueDevices = stableUniqueDevices(allDevices)

        let devicePromptSize = estimateDevicePromptSize(uniqueDevices)
        let clausePromptSize = estimateClausePromptSize(residualInputs.count)
        let totalSize = instructionCharacters + devicePromptSize + clausePromptSize

        return ConditionBatchSessionContext(
            relevantDevices: uniqueDevices,
            instructionCharacters: instructionCharacters,
            estimatedPromptCharacters: totalSize
        )
    }

    /// Acquire or create a session for batch condition resolution.
    /// Respects the batch context's reuse strategy.
    public func acquireBatchSession(
        context: ConditionBatchSessionContext
    ) async -> (session: LanguageModelSession, wasReused: Bool) {
        guard let pool = sessionPool else {
            return (
                LanguageModelSession(instructions: Instructions("")),
                false
            )
        }

        switch context.sessionReuseStrategy {
        case .lazy, .idempotent:
            let session = await pool.acquire(kind: .conditionClause)
            let logMsg = context.sessionReuseStrategy == .lazy
                ? "reused from pool (lazy)"
                : "reused from pool (idempotent, no warmup needed)"
            logger.debug("Batch session: \(logMsg)")
            return (session, true)

        case .alwaysNew:
            let fresh = LanguageModelSession(instructions: Instructions(""))
            logger.debug("Batch session: created fresh (always-new strategy)")
            return (fresh, false)
        }
    }

    /// Release batch session back to pool.
    public func releaseBatchSession(_ session: LanguageModelSession) async {
        guard let pool = sessionPool else { return }
        await pool.release(kind: .conditionClause, session: session)
    }

    /// Discard failed batch session from pool.
    public func discardBatchSession(_ session: LanguageModelSession, reason: FoundationModelSessionDiscardReason) async {
        guard let pool = sessionPool else { return }
        await pool.discard(kind: .conditionClause, session: session, reason: reason)
    }

    // MARK: - Helpers

    private func stableUniqueDevices(_ devices: [HomeCandidateRecord]) -> [HomeCandidateRecord] {
        var seen = Set<String>()
        return devices.filter { device in
            guard !seen.contains(device.id) else { return false }
            seen.insert(device.id)
            return true
        }
    }

    private func estimateDevicePromptSize(_ devices: [HomeCandidateRecord]) -> Int {
        // Rough estimate: 150 chars per device (ID + name + capabilities)
        devices.count * 150
    }

    private func estimateClausePromptSize(_ clauseCount: Int) -> Int {
        // Rough estimate: 100 chars per clause (text + metadata)
        clauseCount * 100
    }
}
