import Foundation

public enum PortfolioRolloutMode: String, Sendable, Codable, Hashable {
    case disabled
    case shadowStatic
    case activeStatic
    case shadowLearned
    case activeLearned

    public var computesDecision: Bool {
        switch self {
        case .disabled:
            false
        case .shadowStatic, .activeStatic, .shadowLearned, .activeLearned:
            true
        }
    }

    public var computesShadowDecision: Bool { computesDecision }

    public var usesLearnedRouter: Bool {
        switch self {
        case .shadowLearned, .activeLearned:
            true
        case .disabled, .shadowStatic, .activeStatic:
            false
        }
    }

    public var executesSelectedArm: Bool {
        switch self {
        case .activeStatic, .activeLearned:
            true
        case .disabled, .shadowStatic, .shadowLearned:
            false
        }
    }
}
