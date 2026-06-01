import Foundation

public struct TemplateCommandParaphraseProvider: CommandParaphraseProvider {
    public init() {}

    public func paraphrases(for spec: CanonicalCommandSpec, count: Int) async throws -> [String] {
        guard count > 0 else { return [] }
        var variants = baseVariants(for: spec)
        variants.append(contentsOf: politeVariants(from: variants))
        variants = stableUnique(variants)

        var result: [String] = []
        var index = 0
        while result.count < count {
            let phrase = variants[index % variants.count]
            if index < variants.count {
                result.append(phrase)
            } else {
                result.append(numberedVariation(phrase, ordinal: (index / variants.count) + 1))
            }
            index += 1
        }
        return result
    }

    private func baseVariants(for spec: CanonicalCommandSpec) -> [String] {
        let device = spec.deviceDisplayName ?? "device"
        let roomPrefix = spec.room.map { "\($0) " } ?? ""
        switch spec.category {
        case .directPower:
            if spec.expected.command == "off" {
                return [
                    "Turn off \(device)",
                    "Switch off \(device)",
                    "Power off \(device)",
                    "Turn \(roomPrefix)\(device) off"
                ]
            }
            return [
                "Turn on \(device)",
                "Switch on \(device)",
                "Power on \(device)",
                "Turn \(roomPrefix)\(device) on"
            ]
        case .brightness:
            let level = spec.expected.parameters["level"] ?? "50"
            return [
                "Set \(device) to \(level) percent",
                "Set the brightness of \(device) to \(level) percent",
                "Dim \(device) to \(level) percent",
                "Make \(roomPrefix)\(device) \(level) percent"
            ]
        case .climate:
            if let command = spec.expected.command, command == "setCoolingSetpoint" {
                let value = spec.expected.parameters["coolingSetpoint"] ?? "24"
                return [
                    "Set \(device) to \(value) degrees",
                    "Set the cooling on \(device) to \(value)",
                    "Make \(device) cool to \(value) degrees"
                ]
            }
            return [
                "Turn on \(device)",
                "Switch on \(device)",
                "Start \(device)"
            ]
        case .media:
            if spec.expected.command == "play" {
                return [
                    "Play \(device)",
                    "Resume playback on \(device)",
                    "Start playing on \(device)"
                ]
            }
            return [
                "Turn on \(device)",
                "Switch on \(device)",
                "Power on \(device)"
            ]
        case .lockOpenClose:
            let command = spec.expected.command ?? "lock"
            return [
                "\(command.capitalized) \(device)",
                "\(command.capitalized) the \(device)",
                "Please \(command) \(device)"
            ]
        case .statusQuery:
            return [
                "Is \(device) on?",
                "What is the status of \(device)?",
                "Check \(device)",
                "Tell me the state of \(device)"
            ]
        case .scheduleAutomation, .conditionAutomation:
            return [
                spec.canonicalUtterance,
                "Every day at 7 AM, \(spec.canonicalUtterance)",
                "Schedule this daily at 7 AM: \(spec.canonicalUtterance)",
                "Create an automation to \(spec.canonicalUtterance)"
            ]
        case .unsupported:
            return [
                spec.canonicalUtterance,
                "Can you handle this: \(spec.canonicalUtterance)?"
            ]
        }
    }

    private func politeVariants(from variants: [String]) -> [String] {
        variants.flatMap { phrase in
            [
                "Please \(phrase.prefix(1).lowercased())\(phrase.dropFirst())",
                "Can you \(phrase.prefix(1).lowercased())\(phrase.dropFirst())?"
            ]
        }
    }

    private func numberedVariation(_ phrase: String, ordinal: Int) -> String {
        if ordinal.isMultiple(of: 2) {
            return "\(phrase) now"
        }
        return "\(phrase) please"
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seen.insert(normalized.lowercased()).inserted else {
                continue
            }
            result.append(normalized)
        }
        return result.isEmpty ? ["Unsupported home automation request"] : result
    }
}
