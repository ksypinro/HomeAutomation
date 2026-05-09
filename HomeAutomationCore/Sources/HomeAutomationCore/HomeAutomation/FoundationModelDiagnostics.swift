import Foundation
import FoundationModels

public enum FoundationModelFailureKind: String, Sendable, Codable, Hashable {
    case contextWindowExceeded
    case guardrailRefusal
    case adapterUnavailable
    case toolFailure
    case generationFailed
    case unknown
}

public enum FoundationModelDiagnostics {
    public static func failureKind(for error: any Error) -> FoundationModelFailureKind {
        if let generationError = error as? LanguageModelSession.GenerationError {
            switch generationError {
            case .exceededContextWindowSize:
                return .contextWindowExceeded
            case .guardrailViolation, .refusal:
                return .guardrailRefusal
            case .assetsUnavailable, .unsupportedGuide, .unsupportedLanguageOrLocale, .decodingFailure, .rateLimited, .concurrentRequests:
                return .generationFailed
            @unknown default:
                return .unknown
            }
        }

        if error is LanguageModelSession.ToolCallError {
            return .toolFailure
        }

        if error is SystemLanguageModel.Adapter.AssetError {
            return .adapterUnavailable
        }

        return failureKind(forDescription: error.localizedDescription)
    }

    public static func failureKind(forDescription description: String) -> FoundationModelFailureKind {
        let text = description.agentLowercasedDiagnosticText
        if text.contains("context") || text.contains("window") || text.contains("token") {
            return .contextWindowExceeded
        }
        if text.contains("guardrail") || text.contains("refusal") || text.contains("refused") {
            return .guardrailRefusal
        }
        if text.contains("tool") {
            return .toolFailure
        }
        if text.contains("adapter") || text.contains("asset") {
            return .adapterUnavailable
        }
        return .unknown
    }

    public static func availabilityStatus() -> String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "available"
        case .unavailable(let reason):
            return "unavailable.\(reason)"
        @unknown default:
            return "unknown"
        }
    }
}

private extension String {
    var agentLowercasedDiagnosticText: String {
        lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }
}
