import Foundation
import HomeAutomationAgents

enum AgentTimeoutError: LocalizedError {
    case timedOut(agentID: AgentID, timeoutNanoseconds: UInt64)

    var errorDescription: String? {
        switch self {
        case .timedOut(let agentID, let timeoutNanoseconds):
            return "Agent \(agentID.rawValue) timed out after \(timeoutNanoseconds / 1_000_000)ms"
        }
    }
}

/// Races an agent execution against its declared timeout.
func withAgentTimeout<T: Sendable>(
    agentID: AgentID,
    timeoutNanoseconds: UInt64,
    timeoutGraceNanoseconds: UInt64 = 500_000_000,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: timeoutNanoseconds)
            throw AgentTimeoutError.timedOut(agentID: agentID, timeoutNanoseconds: timeoutNanoseconds)
        }

        do {
            guard let result = try await group.next() else {
                throw AgentTimeoutError.timedOut(agentID: agentID, timeoutNanoseconds: timeoutNanoseconds)
            }

            group.cancelAll()
            return result
        } catch let timeout as AgentTimeoutError {
            guard timeoutGraceNanoseconds > 0 else {
                group.cancelAll()
                throw timeout
            }

            group.addTask {
                try await Task.sleep(nanoseconds: timeoutGraceNanoseconds)
                throw timeout
            }

            do {
                guard let result = try await group.next() else {
                    throw timeout
                }

                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                throw error
            }
        } catch {
            group.cancelAll()
            throw error
        }
    }
}
