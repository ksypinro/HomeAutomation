import Foundation

enum LegacyTimeoutError: LocalizedError, Sendable, Equatable {
    case timedOut

    var errorDescription: String? {
        "legacy resolver timed out."
    }
}

enum LegacyTimeout {
    static func run<T: Sendable>(
        nanoseconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: nanoseconds)
                throw LegacyTimeoutError.timedOut
            }

            guard let result = try await group.next() else {
                throw LegacyTimeoutError.timedOut
            }
            group.cancelAll()
            return result
        }
    }
}
