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

/// Type-erased agent protocol for scheduler-level orchestration.
public protocol AnyHomeAgent: Sendable {
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
}
