import Foundation

public enum PortfolioRolloutMode: String, Sendable, Codable, Hashable {
    case disabled
    case shadowStatic
    case activeStatic

    public var computesDecision: Bool {
        switch self {
        case .disabled:
            false
        case .shadowStatic, .activeStatic:
            true
        }
    }

    public var computesShadowDecision: Bool { computesDecision }

    public var executesSelectedArm: Bool {
        switch self {
        case .activeStatic:
            true
        case .disabled, .shadowStatic:
            false
        }
    }
}
