import Foundation
import HomeAutomationAgents

public enum AdaptiveContextKeys {
    public static let preparedRequest = ScopedContextKey<PreparedOrchestrationRequest>(
        "adaptive.preparedRequest",
        scope: .root
    )
}
