import Foundation

public struct TraceDiffWriter: Sendable {
    public init() {}

    @discardableResult
    public func write(_ diff: TraceDiff, to directoryURL: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let url = directoryURL.appendingPathComponent("\(diff.caseID).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(diff)
        try data.write(to: url)
        return url
    }

    @discardableResult
    public func writeJSONL(_ diffs: [TraceDiff], to fileURL: URL) throws -> URL {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = try diffs.map { diff -> String in
            let data = try encoder.encode(diff)
            return String(data: data, encoding: .utf8) ?? "{}"
        }.joined(separator: "\n")
        try lines.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
