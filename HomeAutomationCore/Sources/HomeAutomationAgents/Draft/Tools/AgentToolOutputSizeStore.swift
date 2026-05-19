import Foundation

public final class AgentToolOutputSizeStore: @unchecked Sendable {
    public static let shared = AgentToolOutputSizeStore()

    private let lock = NSLock()
    private var maxCharacterCountsByTool: [String: Int] = [:]

    public init() {}

    public func record(toolName: String, characterCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        maxCharacterCountsByTool[toolName] = max(maxCharacterCountsByTool[toolName] ?? 0, characterCount)
    }

    public func estimate(toolName: String, fallback: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return max(maxCharacterCountsByTool[toolName] ?? 0, fallback)
    }
}
