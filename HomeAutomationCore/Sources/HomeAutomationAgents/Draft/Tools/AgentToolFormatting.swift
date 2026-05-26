import Foundation
import HomeAutomationCore

func agentToolDevice(_ id: String, in registry: any DeviceRegistryProtocol) async -> HomeCandidateRecord? {
    let devices = await registry.allDevices()
    return devices.first { $0.id == id }
}

enum AgentToolFormatting {
    static let maxOutputCharacters = 4_000

    static func records(_ records: [HomeCandidateRecord]) -> String {
        jsonLines(records.prefix(25).map { record in
            [
                "id": record.id,
                "name": record.displayName,
                "type": record.deviceType,
                "room": record.room ?? "",
                "capabilities": record.capabilities.joined(separator: ","),
                "risk": String(describing: record.riskLevel),
                "state": record.currentState.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",")
            ]
        })
    }

    static func dictionary(_ values: [String: String]) -> String {
        jsonLines([values])
    }

    static func array(_ values: [String]) -> String {
        capped(#"{"values":["# + values.prefix(20).map { #""\#($0)""# }.joined(separator: ",") + "]}")
    }

    static func jsonLines(_ values: [[String: String]]) -> String {
        capped(values.map { dictionary in
            let body = dictionary.keys.sorted().map { key in
                #""\#(escaped(key))":"\#(escaped(dictionary[key] ?? ""))""#
            }
            .joined(separator: ",")
            return "{\(body)}"
        }
        .joined(separator: "\n"))
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\"#, with: #"\\"#)
            .replacingOccurrences(of: #"""#, with: #"\""#)
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func capped(_ value: String) -> String {
        guard value.count > maxOutputCharacters else { return value }
        return String(value.prefix(maxOutputCharacters))
    }
}
