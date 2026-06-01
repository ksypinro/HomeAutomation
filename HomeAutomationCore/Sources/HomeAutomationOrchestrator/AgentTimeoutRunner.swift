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
    timeoutGraceNanoseconds: UInt64 = 5_000_000_000,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let raceState = AgentTimeoutRaceState<T>()
    let timeout = AgentTimeoutError.timedOut(
        agentID: agentID,
        timeoutNanoseconds: timeoutNanoseconds
    )
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            raceState.setContinuation(continuation)
            let operationTask = Task {
                try await operation()
            }
            raceState.setOperationTask(operationTask)

            Task {
                do {
                    let result = try await operationTask.value
                    raceState.resolve(.success(result))
                } catch {
                    raceState.resolve(.failure(error))
                }
            }

            Task {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds + timeoutGraceNanoseconds)
                } catch {
                    return
                }
                raceState.resolve(.failure(timeout), cancelOperation: true)
            }
        }
    } onCancel: {
        raceState.resolve(.failure(CancellationError()), cancelOperation: true)
    }
}

private final class AgentTimeoutRaceState<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?
    private var operationTask: Task<T, any Error>?
    private var isResolved = false

    func setContinuation(_ continuation: CheckedContinuation<T, any Error>) {
        lock.lock()
        if isResolved {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func setOperationTask(_ task: Task<T, any Error>) {
        lock.lock()
        if isResolved {
            lock.unlock()
            task.cancel()
            return
        }
        operationTask = task
        lock.unlock()
    }

    func resolve(_ result: Result<T, any Error>, cancelOperation: Bool = false) {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }
        isResolved = true
        let continuation = continuation
        self.continuation = nil
        let operationTask = operationTask
        self.operationTask = nil
        lock.unlock()

        if cancelOperation {
            operationTask?.cancel()
        }

        switch result {
        case .success(let value):
            continuation?.resume(returning: value)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}
