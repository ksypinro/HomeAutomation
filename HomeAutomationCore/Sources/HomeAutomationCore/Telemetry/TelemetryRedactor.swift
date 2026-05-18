import Foundation

public struct TelemetryRedactor: Sendable {
    public let mode: HomeAutomationTelemetryPayloadMode
    public let maxPayloadCharacters: Int

    public init(mode: HomeAutomationTelemetryPayloadMode, maxPayloadCharacters: Int) {
        self.mode = mode
        self.maxPayloadCharacters = max(0, maxPayloadCharacters)
    }

    public func redact(_ payload: [String: String]) -> [String: String] {
        payload.reduce(into: [:]) { partial, element in
            let key = element.key
            let value = redactSecrets(element.value)
            let characterCount = value.count
            let hash = stableHash(value)

            switch mode {
            case .metadataOnly:
                partial[key] = "<metadata-only>"
                partial["\(key)CharacterCount"] = String(characterCount)
                partial["\(key)Truncated"] = "true"
                partial["\(key)Hash"] = hash
            case .cappedPayload:
                let capped = cap(value)
                partial[key] = capped.value
                partial["\(key)CharacterCount"] = String(characterCount)
                partial["\(key)Truncated"] = String(capped.truncated)
                partial["\(key)Hash"] = hash
            case .fullPayload:
                partial[key] = value
                partial["\(key)CharacterCount"] = String(characterCount)
                partial["\(key)Truncated"] = "false"
                partial["\(key)Hash"] = hash
            }
        }
    }

    private func cap(_ value: String) -> (value: String, truncated: Bool) {
        guard maxPayloadCharacters > 0, value.count > maxPayloadCharacters else {
            return (value, false)
        }
        return (String(value.prefix(maxPayloadCharacters)), true)
    }

    private func redactSecrets(_ value: String) -> String {
        var output = value
        let patterns = [
            #"(?i)(api[_-]?key|token|authorization|bearer|password|secret)["'\s:=]+[A-Za-z0-9_\-\.]+"#,
            #"(?i)(locationID|locationId)["'\s:=]+[A-Za-z0-9_\-\.]+"#
        ]
        for pattern in patterns {
            output = output.replacingOccurrences(
                of: pattern,
                with: "$1=<redacted>",
                options: .regularExpression
            )
        }
        return output
    }

    private func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

