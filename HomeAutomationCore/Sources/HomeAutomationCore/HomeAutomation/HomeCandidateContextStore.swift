import Foundation

public final class HomeCandidateContextStore: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: HomeCandidateRecord] = [:]

    public init() {}

    public func save(_ candidates: [HomeCandidateRecord]) {
        lock.lock()
        defer { lock.unlock() }

        for candidate in candidates {
            records[candidate.id] = candidate
        }
    }

    public func hydrate(ids: [String]) -> [HomeCandidateRecord] {
        lock.lock()
        defer { lock.unlock() }

        return ids.compactMap { records[$0] }
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }

        records.removeAll()
    }
}

public func shardHomeCandidates(
    _ candidates: [HomeCompactCandidateView],
    shardSize: Int = 20
) -> [[HomeCompactCandidateView]] {
    guard shardSize > 0, !candidates.isEmpty else { return [] }

    return stride(from: 0, to: candidates.count, by: shardSize).map { startIndex in
        Array(candidates[startIndex..<min(startIndex + shardSize, candidates.count)])
    }
}
