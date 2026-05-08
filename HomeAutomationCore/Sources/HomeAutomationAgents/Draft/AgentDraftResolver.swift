import Foundation
import HomeAutomationCore

/// Retry wrapper around draft generation packages.
///
/// `AgentDraftResolver` tries 4 strategy variants in order:
/// 1. `base/full` — Base model, full prompt
/// 2. `adapter/full` — Adapter model, full prompt
/// 3. `base/simplified` — Base model, simplified prompt
/// 4. `adapter/simplified` — Adapter model, simplified prompt
///
/// The first attempt exceeding the confidence threshold is returned immediately.
/// If no attempt exceeds the threshold, the highest-confidence result is selected.
public struct AgentDraftResolver: HomeCommandDraftResolving {
    private let resolver: any HomeCommandDraftResolving
    private let confidenceThreshold: Double
    private let metrics: AgentDraftResolverMetrics?

    public init(
        adapterProvider: HomeAdapterModelProvider = HomeAdapterModelProvider(),
        confidenceThreshold: Double = 0.70,
        metrics: AgentDraftResolverMetrics? = nil,
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

    public func resolveDraftWithReport(from package: HomeModelInstructionPackage) async throws -> AgentDraftResolutionOutput {
        var lastError: Error?
        var bestDraft: HomeCommandDraft?
        var bestAttemptIndex: Int?
        var attempts: [AgentDraftAttemptReport] = []

        for candidate in retryPackages(for: package) {
            do {
                let draft = try await resolver.resolveDraft(from: candidate.package)
                if draft.confidence >= confidenceThreshold {
                    attempts.append(
                        AgentDraftAttemptReport(
                            name: candidate.name,
                            useAdapter: candidate.useAdapter,
                            simplifiedPrompt: candidate.simplifiedPrompt,
                            outcome: "success",
                            confidence: draft.confidence,
                            selected: true,
                            errorDescription: nil
                        )
                    )
                    return AgentDraftResolutionOutput(
                        draft: draft,
                        report: AgentDraftResolutionReport(attempts: attempts, selectedAttemptName: candidate.name)
                    )
                }
                if bestDraft.map({ draft.confidence > $0.confidence }) ?? true {
                    bestDraft = draft
                    bestAttemptIndex = attempts.count
                }
                attempts.append(
                    AgentDraftAttemptReport(
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
                    AgentDraftAttemptReport(
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
            return AgentDraftResolutionOutput(
                draft: bestDraft,
                report: AgentDraftResolutionReport(
                    attempts: attempts,
                    selectedAttemptName: attempts[bestAttemptIndex].name
                )
            )
        }

        let report = AgentDraftResolutionReport(attempts: attempts, selectedAttemptName: nil)
        await metrics?.store(report)
        throw lastError ?? FoundationLabCoreError.invalidRequest("Agent draft resolver failed")
    }

    private func retryPackages(for package: HomeModelInstructionPackage) -> [AgentDraftPackageAttempt] {
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
    ) -> AgentDraftPackageAttempt {
        AgentDraftPackageAttempt(
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

private struct AgentDraftPackageAttempt {
    let name: String
    let useAdapter: Bool
    let simplifiedPrompt: Bool
    let package: HomeModelInstructionPackage
}
