import Foundation

public struct CommandParaphraseValidator: Sendable {
    public init() {}

    public func validatedParaphrases(
        _ paraphrases: [String],
        for spec: CanonicalCommandSpec
    ) -> [String] {
        stableUnique(paraphrases.compactMap { phrase in
            let sanitized = sanitize(phrase)
            return isValid(sanitized, for: spec) ? sanitized : nil
        })
    }

    public func isValid(_ phrase: String, for spec: CanonicalCommandSpec) -> Bool {
        let phrase = sanitize(phrase)
        guard !phrase.isEmpty, phrase.count <= 220 else { return false }
        if exposesInternalLabel(phrase) { return false }
        if spec.category == .unsupported {
            return true
        }
        guard targetMatches(phrase: phrase, spec: spec) else { return false }

        switch spec.category {
        case .directPower:
            return powerCommandMatches(phrase, expectedCommand: spec.expected.command)
        case .brightness:
            return containsAny(phrase, words: ["brightness", "bright", "dim", "level", "percent", "%"]) &&
                valueMatches(phrase, value: spec.expected.parameters["level"])
        case .climate:
            return valueMatches(phrase, value: spec.expected.parameters["coolingSetpoint"]) &&
                containsAny(phrase, words: ["degree", "degrees", "cool", "cooling", "temperature", "temp", "set"])
        case .media:
            guard spec.expected.command == "play" else { return true }
            return containsAny(phrase, words: ["play", "resume", "start"])
        case .lockOpenClose:
            guard let command = spec.expected.command else { return false }
            return containsCommandWord(command, in: phrase)
        case .statusQuery:
            return containsAny(phrase, words: ["status", "state", "check", "is", "what", "tell"])
        case .scheduleAutomation:
            return powerCommandMatches(phrase, expectedCommand: spec.expected.command) &&
                containsScheduleMarker(phrase)
        case .conditionAutomation:
            return powerCommandMatches(phrase, expectedCommand: spec.expected.command) &&
                containsScheduleMarker(phrase) &&
                normalizedText(phrase).contains(" if ")
        case .unsupported:
            return true
        }
    }

    private func sanitize(_ phrase: String) -> String {
        phrase
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }

    private func exposesInternalLabel(_ phrase: String) -> Bool {
        let text = phrase.lowercased()
        return text.contains("targetdeviceid") ||
            text.contains("canonicalcommandid") ||
            text.contains("expecteddeviceids") ||
            text.contains("capability:")
    }

    private func targetMatches(phrase: String, spec: CanonicalCommandSpec) -> Bool {
        guard let deviceDisplayName = spec.deviceDisplayName else { return true }
        let phraseTokens = Set(tokens(from: phrase))
        let targetTokens = tokens(from: deviceDisplayName)
        guard !targetTokens.isEmpty else { return true }
        if Set(targetTokens).isSubset(of: phraseTokens) {
            return true
        }
        if let room = spec.room {
            let roomTokens = Set(tokens(from: room))
            let deviceNoun = targetTokens.last.map { Set([$0]) } ?? []
            return roomTokens.union(deviceNoun).isSubset(of: phraseTokens)
        }
        return false
    }

    private func powerCommandMatches(_ phrase: String, expectedCommand: String?) -> Bool {
        guard let expectedCommand else { return false }
        let text = normalizedText(phrase)
        if expectedCommand == "on" {
            return (containsAny(text, words: ["turn on", "switch on", "power on", "start", "enable", "activate"]) ||
                splitVerbObjectCommandMatches(text, verbs: ["turn", "switch", "power"], value: "on")) &&
                !containsAny(text, words: ["turn off", "switch off", "power off", "disable", "deactivate"])
        }
        if expectedCommand == "off" {
            return (containsAny(text, words: ["turn off", "switch off", "power off", "stop", "disable", "deactivate"]) ||
                splitVerbObjectCommandMatches(text, verbs: ["turn", "switch", "power"], value: "off")) &&
                !containsAny(text, words: ["turn on", "switch on", "power on", "enable", "activate"])
        }
        return containsCommandWord(expectedCommand, in: phrase)
    }

    private func splitVerbObjectCommandMatches(_ normalizedPhrase: String, verbs: [String], value: String) -> Bool {
        let tokens = Set(normalizedPhrase.split(separator: " ").map(String.init))
        return tokens.contains(value) && verbs.contains { tokens.contains($0) }
    }

    private func containsCommandWord(_ command: String, in phrase: String) -> Bool {
        let tokens = Set(tokens(from: phrase))
        return tokens.contains(command.lowercased())
    }

    private func valueMatches(_ phrase: String, value: String?) -> Bool {
        guard let value, !value.isEmpty else { return true }
        let text = normalizedText(phrase)
        let normalizedValue = normalizedText(value).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains(" \(normalizedValue) ") {
            return true
        }
        if normalizedValue == "50", text.contains(" half ") {
            return true
        }
        return false
    }

    private func containsScheduleMarker(_ phrase: String) -> Bool {
        let text = normalizedText(phrase)
        return containsAny(text, words: ["every day", "daily", "schedule", "automation", "7 am", "7 00", "seven am"])
    }

    private func containsAny(_ phrase: String, words: [String]) -> Bool {
        let text = normalizedText(phrase)
        return words.contains { word in
            let normalizedWord = normalizedText(word).trimmingCharacters(in: .whitespacesAndNewlines)
            return !normalizedWord.isEmpty && text.contains(" \(normalizedWord) ")
        }
    }

    private func tokens(from text: String) -> [String] {
        normalizedText(text)
            .split(separator: " ")
            .map(String.init)
            .filter { token in
                !["the", "a", "an", "of", "in", "to", "please", "can", "you"].contains(token)
            }
    }

    private func normalizedText(_ text: String) -> String {
        var result = text.lowercased()
        for (word, number) in numberWords {
            result = result.replacingOccurrences(of: "\\b\(word)\\b", with: number, options: .regularExpression)
        }
        result = result.replacingOccurrences(of: "([a-z])([0-9])", with: "$1 $2", options: .regularExpression)
        result = result.replacingOccurrences(of: "([0-9])([a-z])", with: "$1 $2", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\b0+([0-9]+)\\b", with: "$1", options: .regularExpression)
        result = result
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return " \(result) "
    }

    private var numberWords: [(String, String)] {
        [
            ("twenty four", "24"),
            ("twenty-four", "24"),
            ("fifty", "50"),
            ("zero", "0"),
            ("one", "1"),
            ("two", "2"),
            ("three", "3"),
            ("four", "4"),
            ("five", "5"),
            ("six", "6"),
            ("seven", "7"),
            ("eight", "8"),
            ("nine", "9"),
            ("ten", "10")
        ]
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where seen.insert(value.lowercased()).inserted {
            result.append(value)
        }
        return result
    }
}
