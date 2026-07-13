import Foundation
import HomeAutomationCore

public enum OrchestrationMode: String, Sendable {
    case graph
    case verifierLoop

    public var foundationModelArm: FoundationModelCallArm {
        switch self {
        case .graph:
            .graph
        case .verifierLoop:
            .verifierLoop
        }
    }
}
