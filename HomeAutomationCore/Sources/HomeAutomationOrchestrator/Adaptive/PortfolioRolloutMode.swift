import Foundation

public enum PortfolioRolloutMode: String, Sendable, Codable, Hashable {
    case disabled
    case shadowStatic

    public var computesShadowDecision: Bool {
        switch self {
        case .disabled:
            false
        case .shadowStatic:
            true
        }
    }
}
