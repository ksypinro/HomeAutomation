import Foundation
import HomeAutomationAgents

public final class AgentRegistry: Sendable {
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
    }

    public func agent(for id: AgentID) -> (any AnyHomeAgent)? {
        agents[id]
    }

    public func agents(for capability: AgentCapability) -> [any AnyHomeAgent] {
        (capabilityIndex[capability] ?? []).compactMap { agents[$0] }
    }
}
