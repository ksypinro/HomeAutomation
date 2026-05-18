import Foundation
import HomeAutomationAgents
import OSLog

/// Represents the current health state of a circuit breaker.
public enum CircuitState: String, Sendable, Codable, Hashable {
    /// Normal operation. The agent is considered healthy.
    case closed
    /// Failure threshold reached. The agent will be skipped to prevent cascading failures.
    case open
    /// Testing recovery. The agent will be allowed one execution to see if it recovered.
    case halfOpen
}

public struct CircuitBreakerSnapshot: Codable, Sendable {
    public let agentID: String
    public let state: CircuitState
    public let failureCount: Int
    public let lastFailure: Date?
}

/// A mechanism to isolate failing agents from the rest of the orchestration pipeline.
///
/// If an agent fails consecutively beyond its `threshold`, the breaker opens and skips 
/// the agent in future pipeline runs until the `recoveryInterval` has elapsed.
public actor AgentCircuitBreaker {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "AgentCircuitBreaker")
    public let agentID: AgentID
    private let threshold: Int
    private let recoveryInterval: Double
    private var failureCount = 0
    private var lastFailure: Date?
    private var state: CircuitState = .closed

    public init(
        agentID: AgentID,
        threshold: Int = 3,
        recoveryInterval: Double = 30,
        snapshot: CircuitBreakerSnapshot? = nil
    ) {
        self.agentID = agentID
        self.threshold = max(1, threshold)
        self.recoveryInterval = max(0, recoveryInterval)
        
        if let snapshot {
            self.failureCount = snapshot.failureCount
            self.state = snapshot.state
            self.lastFailure = snapshot.lastFailure
        }
    }
    
    public func snapshot() -> CircuitBreakerSnapshot {
        CircuitBreakerSnapshot(
            agentID: agentID.rawValue,
            state: state,
            failureCount: failureCount,
            lastFailure: lastFailure
        )
    }

    /// Determines if the agent should be allowed to execute.
    ///
    /// - Returns: `true` if the agent is healthy (closed) or testing recovery (half-open). `false` if open.
    public func shouldAllow() -> Bool {
        switch state {
        case .closed:
            return true
        case .open:
            if let lastFailure,
               Date().timeIntervalSince(lastFailure) >= recoveryInterval {
                logger.info("Circuit for agent \(self.agentID.rawValue, privacy: .public) transitioning from OPEN to HALF-OPEN to test recovery.")
                state = .halfOpen
                return true
            }
            return false
        case .halfOpen:
            return true
        }
    }

    /// Records a successful agent execution.
    ///
    /// This immediately closes a half-open circuit and resets the failure count.
    public func recordSuccess() {
        if state != .closed {
            logger.info("Circuit for agent \(self.agentID.rawValue, privacy: .public) transitioning to CLOSED. Agent recovered.")
        }
        failureCount = 0
        state = .closed
    }

    /// Records a failed agent execution.
    ///
    /// If the failure count reaches the threshold, the circuit transitions to open.
    public func recordFailure() {
        failureCount += 1
        lastFailure = Date()
        if failureCount >= threshold && state != .open {
            logger.warning("Circuit for agent \(self.agentID.rawValue, privacy: .public) transitioning to OPEN. Threshold (\(self.threshold, privacy: .public)) reached.")
            state = .open
        }
    }

    public func currentState() -> CircuitState {
        state
    }
}

/// A centralized factory and store for managing all `AgentCircuitBreaker` instances.
public actor CircuitBreakerRegistry {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "CircuitBreakerRegistry")
    private var breakers: [AgentID: AgentCircuitBreaker] = [:]
    private let threshold: Int
    private let recoveryInterval: Double

    private let persistenceKey = "com.homeautomation.circuitBreakers"

    public init(threshold: Int = 3, recoveryInterval: Double = 30) {
        self.threshold = max(1, threshold)
        self.recoveryInterval = max(0, recoveryInterval)
        
        if let data = UserDefaults.standard.data(forKey: "com.homeautomation.circuitBreakers"),
           let snapshots = try? JSONDecoder().decode([CircuitBreakerSnapshot].self, from: data) {
            for snapshot in snapshots {
                let id = AgentID(snapshot.agentID)
                let breaker = AgentCircuitBreaker(
                    agentID: id,
                    threshold: self.threshold,
                    recoveryInterval: self.recoveryInterval,
                    snapshot: snapshot
                )
                breakers[id] = breaker
            }
        }
    }
    
    public func persist() async {
        var snapshots: [CircuitBreakerSnapshot] = []
        for (_, breaker) in breakers {
            snapshots.append(await breaker.snapshot())
        }
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }

    /// Retrieves or creates the circuit breaker for a specific agent.
    ///
    /// - Parameter id: The ID of the agent.
    /// - Returns: The circuit breaker governing the agent.
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
        logger.debug("Created new circuit breaker for agent: \(id.rawValue, privacy: .public)")
        return breaker
    }

    /// Returns the current states of all instantiated breakers.
    public func allStatuses() async -> [AgentID: CircuitState] {
        var result: [AgentID: CircuitState] = [:]
        for (id, breaker) in breakers {
            result[id] = await breaker.currentState()
        }
        return result
    }

    /// Returns the current states of all instantiated breakers, formatted as string key-value pairs.
    public func allStatusStrings() async -> [String: String] {
        var result: [String: String] = [:]
        for (id, state) in await allStatuses() {
            result[id.rawValue] = state.rawValue
        }
        return result
    }
}
