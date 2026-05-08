import Foundation
import HomeAutomationCore

public struct LegacyDraftAttemptReport: Sendable, Codable, Equatable {
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

    func selecting() -> LegacyDraftAttemptReport {
        LegacyDraftAttemptReport(
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

public struct LegacyDraftResolutionReport: Sendable, Codable, Equatable {
    public let attempts: [LegacyDraftAttemptReport]
    public let selectedAttemptName: String?

    public var attemptCount: Int { attempts.count }
    public var attemptSummaries: [String] { attempts.map(\.summary) }
    public var bestDraftAttempt: String? { selectedAttemptName }
}

public struct LegacyDraftResolutionOutput: Sendable {
    public let draft: HomeCommandDraft
    public let report: LegacyDraftResolutionReport
}

public actor LegacyDraftResolverMetrics {
    private var report: LegacyDraftResolutionReport?

    public init() {}

    public func store(_ report: LegacyDraftResolutionReport) {
        self.report = report
    }

    public func lastReport() -> LegacyDraftResolutionReport? {
        report
    }
}

public struct LegacyDraftResolver: HomeCommandDraftResolving {
    private let resolver: any HomeCommandDraftResolving
    private let confidenceThreshold: Double
    private let metrics: LegacyDraftResolverMetrics?

    public init(
        adapterProvider: HomeAdapterModelProvider = HomeAdapterModelProvider(),
        confidenceThreshold: Double = 0.70,
        metrics: LegacyDraftResolverMetrics? = nil,
        resolver: (any HomeCommandDraftResolving)? = nil
    ) {
        self.resolver = resolver ?? FoundationHomeCommandDraftResolver(adapterProvider: adapterProvider)
        self.confidenceThreshold = confidenceThreshold
        self.metrics = metrics
    }

    public func resolveDraft(from package: HomeModelInstructionPackage) async throws -> HomeCommandDraft {
        let output = try await resolveDraftWithReport(from: package)
        await metrics?.store(output.report)
        return output.draft
    }

    public func resolveDraftWithReport(from package: HomeModelInstructionPackage) async throws -> LegacyDraftResolutionOutput {
        var lastError: Error?
        var bestDraft: HomeCommandDraft?
        var bestAttemptIndex: Int?
        var attempts: [LegacyDraftAttemptReport] = []

        for candidate in retryPackages(for: package) {
            do {
                let draft = try await resolver.resolveDraft(from: candidate.package)
                if draft.confidence >= confidenceThreshold {
                    attempts.append(
                        LegacyDraftAttemptReport(
                            name: candidate.name,
                            useAdapter: candidate.useAdapter,
                            simplifiedPrompt: candidate.simplifiedPrompt,
                            outcome: "success",
                            confidence: draft.confidence,
                            selected: true,
                            errorDescription: nil
                        )
                    )
                    return LegacyDraftResolutionOutput(
                        draft: draft,
                        report: LegacyDraftResolutionReport(
                            attempts: attempts,
                            selectedAttemptName: candidate.name
                        )
                    )
                }
                if bestDraft.map({ draft.confidence > $0.confidence }) ?? true {
                    bestDraft = draft
                    bestAttemptIndex = attempts.count
                }
                attempts.append(
                    LegacyDraftAttemptReport(
                        name: candidate.name,
                        useAdapter: candidate.useAdapter,
                        simplifiedPrompt: candidate.simplifiedPrompt,
                        outcome: "low-confidence",
                        confidence: draft.confidence,
                        selected: false,
                        errorDescription: nil
                    )
                )
            } catch {
                lastError = error
                attempts.append(
                    LegacyDraftAttemptReport(
                        name: candidate.name,
                        useAdapter: candidate.useAdapter,
                        simplifiedPrompt: candidate.simplifiedPrompt,
                        outcome: "error",
                        confidence: nil,
                        selected: false,
                        errorDescription: error.localizedDescription
                    )
                )
            }
        }

        if let bestDraft, let bestAttemptIndex {
            attempts[bestAttemptIndex] = attempts[bestAttemptIndex].selecting()
            return LegacyDraftResolutionOutput(
                draft: bestDraft,
                report: LegacyDraftResolutionReport(
                    attempts: attempts,
                    selectedAttemptName: attempts[bestAttemptIndex].name
                )
            )
        }

        await metrics?.store(
            LegacyDraftResolutionReport(
                attempts: attempts,
                selectedAttemptName: nil
            )
        )
        throw lastError ?? FoundationLabCoreError.invalidRequest("legacy draft resolver failed")
    }

    private func retryPackages(for package: HomeModelInstructionPackage) -> [LegacyDraftPackageAttempt] {
        [
            makeAttempt(from: package, name: "base/full", useAdapter: false, simplifyPrompt: false),
            makeAttempt(from: package, name: "adapter/full", useAdapter: true, simplifyPrompt: false),
            makeAttempt(from: package, name: "base/simplified", useAdapter: false, simplifyPrompt: true),
            makeAttempt(from: package, name: "adapter/simplified", useAdapter: true, simplifyPrompt: true)
        ]
    }

    private func makeAttempt(
        from package: HomeModelInstructionPackage,
        name: String,
        useAdapter: Bool,
        simplifyPrompt: Bool
    ) -> LegacyDraftPackageAttempt {
        LegacyDraftPackageAttempt(
            name: name,
            useAdapter: useAdapter,
            simplifiedPrompt: simplifyPrompt,
            package: HomeModelInstructionPackage(
                instructions: package.instructions,
                prompt: simplifyPrompt ? simplifiedPrompt(from: package.prompt) : package.prompt,
                tools: package.tools,
                useAdapter: useAdapter,
                generationMode: package.generationMode
            )
        )
    }

    private func simplifiedPrompt(from prompt: String) -> String {
        """
        Resolve the smart-home command using only the hydrated candidate IDs, capabilities, and commands in this prompt.
        Return a single HomeCommandDraft. If the target or command is ambiguous, set needsClarification true.

        \(prompt)
        """
    }
}

private struct LegacyDraftPackageAttempt {
    let name: String
    let useAdapter: Bool
    let simplifiedPrompt: Bool
    let package: HomeModelInstructionPackage
}
