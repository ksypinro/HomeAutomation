import Foundation
import HomeAutomationAgents

public enum CircuitState: String, Sendable, Codable, Hashable {
    case closed
    case open
    case halfOpen
}

public actor AgentCircuitBreaker {
    public let agentID: AgentID
    private let threshold: Int
    private let recoveryInterval: Double
    private var failureCount = 0
    private var lastFailure: Date?
    private var state: CircuitState = .closed

    public init(agentID: AgentID, threshold: Int = 3, recoveryInterval: Double = 30) {
        self.agentID = agentID
        self.threshold = max(1, threshold)
        self.recoveryInterval = max(0, recoveryInterval)
    }

    public func shouldAllow() -> Bool {
        switch state {
        case .closed:
            return true
        case .open:
            if let lastFailure,
               Date().timeIntervalSince(lastFailure) >= recoveryInterval {
                state = .halfOpen
                return true
            }
            return false
        case .halfOpen:
            return true
        }
    }

    public func recordSuccess() {
        failureCount = 0
        state = .closed
    }

    public func recordFailure() {
        failureCount += 1
        lastFailure = Date()
        if failureCount >= threshold {
            state = .open
        }
    }

    public func currentState() -> CircuitState {
        state
    }
}

public actor CircuitBreakerRegistry {
    private var breakers: [AgentID: AgentCircuitBreaker] = [:]
    private let threshold: Int
    private let recoveryInterval: Double

    public init(threshold: Int = 3, recoveryInterval: Double = 30) {
        self.threshold = max(1, threshold)
        self.recoveryInterval = max(0, recoveryInterval)
    }

    public func breaker(for id: AgentID) -> AgentCircuitBreaker {
        if let breaker = breakers[id] {
            return breaker
        }
        let breaker = AgentCircuitBreaker(
            agentID: id,
            threshold: threshold,
            recoveryInterval: recoveryInterval
        )
        breakers[id] = breaker
        return breaker
    }

    public func allStatuses() async -> [AgentID: CircuitState] {
        var result: [AgentID: CircuitState] = [:]
        for (id, breaker) in breakers {
            result[id] = await breaker.currentState()
        }
        return result
    }

    public func allStatusStrings() async -> [String: String] {
        var result: [String: String] = [:]
        for (id, state) in await allStatuses() {
            result[id.rawValue] = state.rawValue
        }
        return result
    }
}
