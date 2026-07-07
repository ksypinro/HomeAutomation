import Foundation

/// Shared soft-timeout budget for NLU-class Foundation Model calls.
///
/// A soft timeout races the model call against a deadline; on expiry the
/// worker session returns its deterministic fallback instead of waiting for
/// a contended or hung model response.
public struct NLUSoftTimeoutBudget: Sendable {
    public var nluClassNanoseconds: UInt64

    public init(nluClassNanoseconds: UInt64) {
        self.nluClassNanoseconds = nluClassNanoseconds
    }

    public static let `default` = NLUSoftTimeoutBudget(nluClassNanoseconds: 4_000_000_000)
}

enum NLUModelSoftTimeoutError: LocalizedError {
    case timedOut(agentID: AgentID, timeoutNanoseconds: UInt64)

    var errorDescription: String? {
        switch self {
        case .timedOut(let agentID, let timeoutNanoseconds):
            return "Agent \(agentID.rawValue) model call soft timed out after \(timeoutNanoseconds / 1_000_000)ms"
        }
    }
}

func withNLUModelSoftTimeout<T: Sendable>(
    agentID: AgentID,
    timeoutNanoseconds: UInt64,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let raceState = NLUModelSoftTimeoutState<T>()
    let timeout = NLUModelSoftTimeoutError.timedOut(
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
                    let value = try await operationTask.value
                    raceState.resolve(.success(value))
                } catch {
                    raceState.resolve(.failure(error))
                }
            }

            Task {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
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

private final class NLUModelSoftTimeoutState<T: Sendable>: @unchecked Sendable {
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
