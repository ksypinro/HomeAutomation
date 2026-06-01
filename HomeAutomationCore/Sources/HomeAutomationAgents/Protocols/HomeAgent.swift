import Foundation

/// Typed agent protocol. Each concrete agent owns specific input and output types.
public protocol HomeAgent: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    var id: AgentID { get }
    var capabilities: Set<AgentCapability> { get }
    var manifest: AgentManifest { get }
    var timeoutNanoseconds: UInt64 { get }

    func run(_ input: Input, context: ResolutionContext) async throws -> Output
}

public extension HomeAgent {
    var manifest: AgentManifest {
        AgentManifestDefaults.manifest(id: id, capabilities: capabilities)
    }
}

public actor AgentRunCounter {
    private var value = 0

    public init() {}

    public func nextRunID() -> Int {
        value += 1
        return value
    }
}

public protocol AgentRuntimeIdentifiable: Sendable {
    var agentSessionID: String { get }
    func nextAgentRunID() async -> Int
}

/// Type-erased agent protocol for scheduler-level orchestration.
public protocol AnyHomeAgent: AgentRuntimeIdentifiable {
    var id: AgentID { get }
    var capabilities: Set<AgentCapability> { get }
    var manifest: AgentManifest { get }
    var timeoutNanoseconds: UInt64 { get }

    func run(context: ResolutionContext) async -> AgentRunResult
}

public extension AnyHomeAgent {
    var manifest: AgentManifest {
        AgentManifestDefaults.manifest(id: id, capabilities: capabilities)
    }

    var agentSessionID: String {
        "untracked-\(id.rawValue)"
    }

    func nextAgentRunID() async -> Int {
        0
    }
}
