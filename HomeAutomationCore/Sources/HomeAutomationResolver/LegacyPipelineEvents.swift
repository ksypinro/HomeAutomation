import Foundation
import HomeAutomationCore

public enum LegacyPipelineStage: String, Sendable, Codable, CaseIterable {
    case input
    case ruleBasedPrecheck
    case availability
    case fallback
    case workers
    case registry
    case candidateResolution
    case hydration
    case draftResolution
    case validation
    case execution
    case metrics
    case outcome
    case resolver
}

public struct LegacyPipelineEvent: Identifiable, Sendable, Codable, Equatable {
    public enum Status: String, Sendable, Codable {
        case pending
        case running
        case completed
        case failed
    }

    public let id: String
    public let stage: LegacyPipelineStage?
    public let title: String
    public let status: Status
    public let detail: String

    public init(id: String, title: String, status: Status, detail: String = "") {
        self.id = id
        self.stage = LegacyPipelineStage(rawValue: id)
        self.title = title
        self.status = status
        self.detail = detail
    }

    public init(stage: LegacyPipelineStage, title: String, status: Status, detail: String = "") {
        self.id = stage.rawValue
        self.stage = stage
        self.title = title
        self.status = status
        self.detail = detail
    }
}

public enum LegacyResolverUpdate: Sendable {
    case event(LegacyPipelineEvent)
    case result(HomeAutomationResolverResult)
}

public extension LegacyHomeCommandResolver {
    func resolveWithEvents(
        _ text: String,
        executeLowRiskCommands: Bool = true
    ) -> AsyncStream<LegacyPipelineEvent> {
        AsyncStream { continuation in
            Task {
                do {
                    for try await update in resolveStream(text, executeLowRiskCommands: executeLowRiskCommands) {
                        if case .event(let event) = update {
                            continuation.yield(event)
                        }
                    }
                } catch {
                    continuation.yield(
                        LegacyPipelineEvent(
                            stage: .resolver,
                            title: "Resolver",
                            status: .failed,
                            detail: error.localizedDescription
                        )
                    )
                }
                continuation.finish()
            }
        }
    }
}
