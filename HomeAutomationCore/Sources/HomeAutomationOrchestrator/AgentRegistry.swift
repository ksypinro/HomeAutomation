import Foundation
import HomeAutomationAgents
import OSLog

/// A read-only registry holding instances of `AnyHomeAgent`.
/// 
/// The registry allows the orchestrator to look up agents either by their unique
/// identifier (`AgentID`) or by their supported capabilities.
public final class AgentRegistry: Sendable {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "AgentRegistry")
    private let agents: [AgentID: any AnyHomeAgent]
    private let capabilityIndex: [AgentCapability: [AgentID]]

    public init(agents: [any AnyHomeAgent]) {
        var byID: [AgentID: any AnyHomeAgent] = [:]
        var byCapability: [AgentCapability: [AgentID]] = [:]
        for agent in agents {
            byID[agent.id] = agent
            for capability in agent.capabilities {
                byCapability[capability, default: []].append(agent.id)
            }
        }
        self.agents = byID
        self.capabilityIndex = byCapability
        
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

    /// Retrieves all agents that declare support for a specific capability.
    ///
    /// - Parameter capability: The `AgentCapability` to filter by.
    /// - Returns: An array of agents matching the capability.
    public func agents(for capability: AgentCapability) -> [any AnyHomeAgent] {
        let found = (capabilityIndex[capability] ?? []).compactMap { agents[$0] }
        logger.debug("Found \(found.count, privacy: .public) agents for capability: \(String(describing: capability), privacy: .public)")
        return found
    }
}
