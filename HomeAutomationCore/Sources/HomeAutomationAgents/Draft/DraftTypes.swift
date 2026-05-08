import Foundation
import HomeAutomationCore

/// Shared types for Draft agent reporting and metrics.

/// One draft attempt diagnostic record.
public struct AgentDraftAttemptReport: Sendable, Codable, Equatable {
    public let name: String
    public let useAdapter: Bool
    public let simplifiedPrompt: Bool
    public let outcome: String
    public let confidence: Double?
    public let selected: Bool
    public let errorDescription: String?

    public var summary: String {
        var parts = ["\(name) \(outcome)"]
        if let confidence {
            parts.append("confidence=\(confidence)")
        }
        if selected {
            parts.append("selected")
        }
        if let errorDescription {
            parts.append("error=\(errorDescription)")
        }
        return parts.joined(separator: " ")
    }

    public init(
        name: String,
        useAdapter: Bool,
        simplifiedPrompt: Bool,
        outcome: String,
        confidence: Double?,
        selected: Bool,
        errorDescription: String?
    ) {
        self.name = name
        self.useAdapter = useAdapter
        self.simplifiedPrompt = simplifiedPrompt
        self.outcome = outcome
        self.confidence = confidence
        self.selected = selected
        self.errorDescription = errorDescription
    }

    func selecting() -> AgentDraftAttemptReport {
        AgentDraftAttemptReport(
            name: name,
            useAdapter: useAdapter,
            simplifiedPrompt: simplifiedPrompt,
            outcome: outcome,
            confidence: confidence,
            selected: true,
            errorDescription: errorDescription
        )
    }
}

/// Aggregate report across draft attempts.
public struct AgentDraftResolutionReport: Sendable, Codable, Equatable {
    public let attempts: [AgentDraftAttemptReport]
    public let selectedAttemptName: String?

    public var attemptCount: Int { attempts.count }
    public var attemptSummaries: [String] { attempts.map(\.summary) }
    public var bestDraftAttempt: String? { selectedAttemptName }

    public init(attempts: [AgentDraftAttemptReport], selectedAttemptName: String?) {
        self.attempts = attempts
        self.selectedAttemptName = selectedAttemptName
    }
}

/// Draft plus report output.
public struct AgentDraftResolutionOutput: Sendable {
    public let draft: HomeCommandDraft
    public let report: AgentDraftResolutionReport

    public init(draft: HomeCommandDraft, report: AgentDraftResolutionReport) {
        self.draft = draft
        self.report = report
    }
}

/// Stores the latest draft-resolution report for metrics.
public actor AgentDraftResolverMetrics {
    private var report: AgentDraftResolutionReport?

    public init() {}

    public func store(_ report: AgentDraftResolutionReport) {
        self.report = report
    }

    public func lastReport() -> AgentDraftResolutionReport? {
        report
    }
}
