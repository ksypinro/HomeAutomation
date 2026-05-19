import Foundation
import HomeAutomationCore

enum NLUInstructionContextProvider {
    static func intentFamilyContext(for text: String) -> String {
        let exactMatches = HomeBixbyCommandCatalog.commands(matching: text).prefix(5)
        if !exactMatches.isEmpty {
            let pairs = exactMatches
                .map { "\($0.capability).\($0.action) method=\($0.method)" }
                .joined(separator: ", ")
            return """
            Relevant Bixby command matches: \(pairs).
            Treat device, location, mode, duration, temperature, and numeric placeholders as slots.
            Map GET methods to statusQuery and POST methods to command intent families.
            """
        }

        return """
        Intent family hints:
        - power: turn on, turn off, switch, power.
        - brightness: brightness, dim, percent, level, color.
        - temperature: thermostat, AC, cooler, warmer, fan mode.
        - lockUnlock/openClose: lock, unlock, open, close, blind, shade, garage, valve.
        - statusQuery: status, check, what is, battery, sensor reading.
        - media/routine/applianceCycle: play, pause, volume, scene, routine, washer, dryer, oven, vacuum.
        Treat Bixby placeholders such as device, location, mode, duration, temperature, and numeric values as slots.
        """
    }

    static func deviceTypeContext(for text: String) -> String {
        let normalized = text.agentNormalizedHomeTokenString
        let matchedTypes = HomeAutomationKnowledgeBase.shared.deviceTypes.filter { item in
            let searchable = ([item.id, item.displayName] + item.aliases + item.exampleNames)
                .joined(separator: " ")
                .agentNormalizedHomeTokenString
            return searchable.split(separator: " ").contains { normalized.contains($0) } ||
                normalized.contains(item.id.agentNormalizedHomeTokenString)
        }

        let selectedTypes = (matchedTypes.isEmpty ? commonDeviceTypes() : Array(matchedTypes.prefix(12)))
            .map { item in
                let aliases = item.aliases.prefix(3).joined(separator: "/")
                return aliases.isEmpty ? item.id : "\(item.id)(aliases=\(aliases))"
            }
            .joined(separator: ", ")

        return """
        Device type hints: \(selectedTypes).
        Use stable internal identifiers exactly. Bixby placeholders such as device, deviceType, and location are slots, not device names.
        Return an empty list when no device type is actually mentioned.
        """
    }

    private static func commonDeviceTypes() -> [HomeCatalogDeviceType] {
        let priority = [
            "light",
            "airConditioner",
            "thermostat",
            "fan",
            "lock",
            "garageDoor",
            "blind",
            "camera",
            "speaker",
            "tv",
            "washer",
            "dryer",
            "oven",
            "robotCleaner",
            "routine"
        ]
        let byID = Dictionary(uniqueKeysWithValues: HomeAutomationKnowledgeBase.shared.deviceTypes.map { ($0.id, $0) })
        return priority.compactMap { byID[$0] }
    }
}
