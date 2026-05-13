import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import OSLog

/// A read-only registry holding instances of `AnyHomeAgent`.
/// 
/// The registry allows the orchestrator to look up agents either by their unique
/// identifier (`AgentID`) or by their supported capabilities.
public final class AgentRegistry: Sendable {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "AgentRegistry")
    private let agents: [AgentID: any AnyHomeAgent]
    private let manifests: [AgentID: AgentManifest]
    private let capabilityIndex: [AgentCapability: [AgentID]]
    private let operationIndex: [HomeAutomationOperationKind: [AgentID]]

    public init(agents: [any AnyHomeAgent]) {
        var byID: [AgentID: any AnyHomeAgent] = [:]
        var byManifest: [AgentID: AgentManifest] = [:]
        var byCapability: [AgentCapability: [AgentID]] = [:]
        var byOperation: [HomeAutomationOperationKind: [AgentID]] = [:]
        for agent in agents {
            let manifest = agent.manifest
            byID[agent.id] = agent
            byManifest[agent.id] = manifest
            for capability in manifest.capabilities {
                byCapability[capability, default: []].append(agent.id)
            }
            for operation in manifest.supportedOperations {
                byOperation[operation, default: []].append(agent.id)
            }
        }
        self.agents = byID
        self.manifests = byManifest
        self.capabilityIndex = byCapability.mapValues { ids in
            ids.sorted { lhs, rhs in
                let left = byManifest[lhs]?.priority ?? 0
                let right = byManifest[rhs]?.priority ?? 0
                if left == right {
                    return lhs.rawValue < rhs.rawValue
                }
                return left > right
            }
        }
        self.operationIndex = byOperation.mapValues { ids in
            ids.sorted { lhs, rhs in
                let left = byManifest[lhs]?.priority ?? 0
                let right = byManifest[rhs]?.priority ?? 0
                if left == right {
                    return lhs.rawValue < rhs.rawValue
                }
                return left > right
            }
        }
        
        logger.info("Initialized AgentRegistry with \(byID.count, privacy: .public) agents.")
    }

    /// Retrieves an agent by its unique identifier.
    ///
    /// - Parameter id: The `AgentID` to search for.
    /// - Returns: The registered agent, or `nil` if not found.
    public func agent(for id: AgentID) -> (any AnyHomeAgent)? {
        let found = agents[id]
        if found == nil {
            logger.warning("Agent lookup failed for ID: \(id.rawValue, privacy: .public)")
        } else {
            logger.debug("Agent lookup succeeded for ID: \(id.rawValue, privacy: .public)")
        }
        return found
    }

    /// Retrieves an agent manifest by agent ID.
    public func manifest(for id: AgentID) -> AgentManifest? {
        manifests[id]
    }

    /// Retrieves all agents that declare support for a specific capability.
    ///
    /// - Parameter capability: The `AgentCapability` to filter by.
    /// - Returns: An array of agents matching the capability.
    public func agents(for capability: AgentCapability) -> [any AnyHomeAgent] {
        let found = (capabilityIndex[capability] ?? []).compactMap { agents[$0] }
        logger.debug("Found \(found.count, privacy: .public) agents for capability: \(String(describing: capability), privacy: .public)")
        return found
    }

    /// Retrieves all agents that declare support for a capability and operation.
    public func agents(
        for capability: AgentCapability,
        operation: HomeAutomationOperationKind
    ) -> [any AnyHomeAgent] {
        let ids = capabilityIndex[capability] ?? []
        let found = ids.compactMap { id -> (any AnyHomeAgent)? in
            guard manifests[id]?.supportedOperations.contains(operation) == true else {
                return nil
            }
            return agents[id]
        }
        logger.debug("Found \(found.count, privacy: .public) agents for capability \(String(describing: capability), privacy: .public) and operation \(operation.rawValue, privacy: .public)")
        return found
    }

    /// Retrieves all agents that declare support for an operation.
    public func agents(for operation: HomeAutomationOperationKind) -> [any AnyHomeAgent] {
        let found = (operationIndex[operation] ?? []).compactMap { agents[$0] }
        logger.debug("Found \(found.count, privacy: .public) agents for operation: \(operation.rawValue, privacy: .public)")
        return found
    }
}
