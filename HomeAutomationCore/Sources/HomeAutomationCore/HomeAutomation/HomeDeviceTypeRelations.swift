import Foundation

public enum HomeDeviceTypeRelations {
    public static func matches(_ deviceType: String, in hints: Set<String>) -> Bool {
        let normalizedType = normalized(deviceType)
        guard !normalizedType.isEmpty else { return false }
        let normalizedHints = Set(hints.map(normalized).filter { !$0.isEmpty })
        if normalizedHints.contains(normalizedType) { return true }
        return normalizedHints.contains { areRelated(normalizedType, $0) }
    }

    public static func areRelated(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right { return true }
        return relatedGroups.contains { group in
            group.contains(left) && group.contains(right)
        }
    }

    private static let relatedGroups: [Set<String>] = [
        ["outlet", "smartplug"],
        ["lock", "smartlock"],
        ["tv", "television"],
        ["washer", "washerlaundry", "clotheswasherdryer"],
        ["dryer", "dryerlaundry", "clotheswasherdryer"],
        ["microwave", "microwaveoven"],
        ["coffeemaker", "coffeemachine"],
        ["hood", "cookerhood"],
        ["airqualitydetector", "airqualitymonitor"],
        ["valve", "watervalve"],
        ["vacuum", "robotcleaner"]
    ]

    private static func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"[^a-z0-9 ]+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined()
    }
}
