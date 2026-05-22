import Foundation
import HomeAutomationCore

public enum AvailableConditionDevicesTool {
    public static func relevantDevices(
        from devices: [HomeCandidateRecord],
        matching conditionText: String,
        limit: Int = 12
    ) -> [HomeCandidateRecord] {
        let query = normalize(conditionText)
        let ranked = devices
            .map { device in (device: device, score: score(device, query: query)) }
            .filter { $0.score > 0 }
            .sorted {
                if $0.score == $1.score {
                    return $0.device.displayName < $1.device.displayName
                }
                return $0.score > $1.score
            }
            .map(\.device)

        if !ranked.isEmpty {
            return Array(ranked.prefix(limit))
        }

        return Array(devices.prefix(limit))
    }

    public static func promptList(from devices: [HomeCandidateRecord]) -> String {
        let lines = devices.map { device in
            let room = device.room ?? "unknown"
            return "- id=\(device.id), name=\(device.displayName), type=\(device.deviceType), room=\(room), capabilities=[\(device.capabilities.joined(separator: ", "))]"
        }
        return lines.isEmpty ? "- none" : lines.joined(separator: "\n")
    }

    private static func score(_ device: HomeCandidateRecord, query: String) -> Int {
        var total = 0
        let name = normalize(device.displayName)
        let type = normalize(device.deviceType)
        let room = device.room.map(normalize)
        let coreQuery = conditionSubject(from: query)

        if query.contains(name) { total += 16 }
        if !coreQuery.isEmpty, name.contains(coreQuery) { total += 14 }
        if query.contains(type) { total += 6 }
        if let room, query.contains(room) { total += 6 }

        let queryTokens = Set(coreQuery.split(separator: " ").map(String.init))
            .subtracting(subjectStopWords)
        let nameTokens = Set(name.split(separator: " ").map(String.init))
        let allQueryTokens = Set(query.split(separator: " ").map(String.init))
        total += queryTokens.intersection(nameTokens).count * 3

        if !allQueryTokens.intersection(["lock", "locks", "locked", "unlock", "unlocks", "unlocked"]).isEmpty,
           device.capabilities.contains("lock") {
            total += 10
        }
        if !allQueryTokens.intersection(["open", "opens", "opened", "closed", "closes"]).isEmpty,
           device.capabilities.contains("contactSensor") ||
           device.capabilities.contains("doorControl") ||
           device.capabilities.contains("garageDoorControl") ||
           device.capabilities.contains("windowShade") {
            total += 7
        }
        if !allQueryTokens.intersection(["on", "off"]).isEmpty,
           device.capabilities.contains("switch") {
            total += 7
        }
        if allQueryTokens.contains("motion"), device.capabilities.contains("motionSensor") { total += 8 }
        if allQueryTokens.contains("temperature"), device.capabilities.contains("temperatureMeasurement") { total += 8 }
        if allQueryTokens.contains("contact"), device.capabilities.contains("contactSensor") { total += 8 }

        return total
    }

    private static func conditionSubject(from query: String) -> String {
        var subject = query
        let suffixes = [
            " is turned on",
            " is turned off",
            " is unlocked",
            " is locked",
            " is closed",
            " is open",
            " is on",
            " is off",
            " turns on",
            " turns off",
            " opens",
            " closes",
            " locks",
            " unlocks",
            " turned on",
            " turned off",
            " locked",
            " unlocked",
            " open",
            " closed",
            " on",
            " off"
        ]
        for suffix in suffixes where subject.hasSuffix(suffix) {
            subject.removeLast(suffix.count)
            break
        }
        return subject.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let subjectStopWords: Set<String> = [
        "is",
        "the",
        "a",
        "an",
        "and",
        "or",
        "if",
        "when"
    ]

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\s]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
