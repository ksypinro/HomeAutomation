import Foundation
import HomeAutomationCore

public actor LegacyCandidateContextStore {
    private var records: [String: HomeCandidateRecord] = [:]

    public init() {}

    public func save(_ candidates: [HomeCandidateRecord]) {
        for candidate in candidates {
            records[candidate.id] = candidate
        }
    }

    public func hydrate(ids: [String]) -> [HomeCandidateRecord] {
        ids.compactMap { records[$0] }
    }

    public func clear() {
        records.removeAll()
    }
}
