import Foundation
import HomeAutomationAgents

extension Array where Element: Identifiable, Element.ID == String {
    /// Returns elements in stable order, deduplicating by `id`.
    public func stableUnique() -> [Element] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}

extension Array where Element == String {
    /// Returns strings in stable order, deduplicating by value.
    public func stableUnique() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
