import Foundation
import FoundationModels
import HomeAutomationCore

/// Package containing a budget-aware prompt for candidate resolution.
public struct CandidateResolutionPromptPackage: Sendable, Equatable {
    public let prompt: String
    public let contextBudgetReport: HomeModelContextBudgetReport

    public init(prompt: String, contextBudgetReport: HomeModelContextBudgetReport) {
        self.prompt = prompt
        self.contextBudgetReport = contextBudgetReport
    }
}

/// Builds context-budget-aware prompts for candidate resolution and shard ranking.
public struct CandidateResolutionPromptBuilder: Sendable {
    private let budgeter: FoundationModelContextBudgeter

    public init(budgeter: FoundationModelContextBudgeter = FoundationModelContextBudgeter()) {
        self.budgeter = budgeter
    }

    public func makeDirectPrompt(
        userText: String,
        resolutionState: HomeResolutionState,
        candidates: [HomeCompactCandidateView],
        memoryHints: [MemoryHint],
        instructionText: String
    ) -> CandidateResolutionPromptPackage {
        makePrompt(
            userText: userText,
            resolutionState: resolutionState,
            candidates: candidates,
            memoryHints: memoryHints,
            instructionText: instructionText,
            candidateLabel: "Candidates"
        )
    }

    public func makeShardPrompt(
        userText: String,
        resolutionState: HomeResolutionState,
        shard: [HomeCompactCandidateView],
        memoryHints: [MemoryHint],
        instructionText: String
    ) -> CandidateResolutionPromptPackage {
        makePrompt(
            userText: userText,
            resolutionState: resolutionState,
            candidates: shard,
            memoryHints: memoryHints,
            instructionText: instructionText,
            candidateLabel: "Candidate shard"
        )
    }

    private func makePrompt(
        userText: String,
        resolutionState: HomeResolutionState,
        candidates: [HomeCompactCandidateView],
        memoryHints: [MemoryHint],
        instructionText: String,
        candidateLabel: String
    ) -> CandidateResolutionPromptPackage {
        let variants = [
            promptVariant(
                level: "full",
                userText: userText,
                resolutionState: resolutionState,
                candidates: candidates,
                memoryHints: memoryHints,
                candidateLabel: candidateLabel,
                candidateLines: fullCandidateLines(candidates),
                includeFullHints: true
            ),
            promptVariant(
                level: "compactCandidates",
                userText: userText,
                resolutionState: resolutionState,
                candidates: candidates,
                memoryHints: memoryHints,
                candidateLabel: candidateLabel,
                candidateLines: compactCandidateLines(candidates),
                includeFullHints: false
            ),
            promptVariant(
                level: "minimal",
                userText: userText,
                resolutionState: resolutionState,
                candidates: candidates,
                memoryHints: [],
                candidateLabel: candidateLabel,
                candidateLines: minimalCandidateLines(candidates),
                includeFullHints: false
            )
        ]

        var fallback: CandidateResolutionPromptPackage?
        for variant in variants {
            let report = budgeter.report(
                instructionText: instructionText,
                prompt: variant.prompt,
                tools: [],
                candidateCount: candidates.count,
                ragCapabilitySectionCount: 0,
                ragExampleSectionCount: 0,
                ragBixbySectionCount: 0,
                selectedCompactionLevel: variant.level,
                estimatedToolOutputCharacterCount: 0
            )
            let package = CandidateResolutionPromptPackage(prompt: variant.prompt, contextBudgetReport: report)
            fallback = package
            if budgeter.isWithinBudget(report) {
                return package
            }
        }

        return fallback ?? CandidateResolutionPromptPackage(
            prompt: "\(userText)\n\(candidateLabel):\n\(minimalCandidateLines(candidates))",
            contextBudgetReport: budgeter.report(
                instructionText: instructionText,
                prompt: userText,
                tools: [],
                candidateCount: candidates.count,
                ragCapabilitySectionCount: 0,
                ragExampleSectionCount: 0,
                ragBixbySectionCount: 0,
                selectedCompactionLevel: "minimal",
                estimatedToolOutputCharacterCount: 0
            )
        )
    }

    internal func promptVariant(
        level: String,
        userText: String,
        resolutionState: HomeResolutionState,
        candidates: [HomeCompactCandidateView],
        memoryHints: [MemoryHint],
        candidateLabel: String,
        candidateLines: String,
        includeFullHints: Bool
    ) -> (level: String, prompt: String) {
        let hintBlock: String
        if includeFullHints {
            hintBlock = """
            Resolution hints:
            - Intent families: \(resolutionState.intent.topFamilies)
            - Device types: \(resolutionState.deviceType.deviceTypes)
            - Rooms: \(resolutionState.slots.rooms)
            - Device nicknames: \(resolutionState.slots.deviceNicknames)
            - Values: \(resolutionState.slots.values)
            - Memory hints: \(memoryHints)
            """
        } else {
            hintBlock = """
            Resolution hints:
            - Intent families: \(resolutionState.intent.topFamilies.prefix(3))
            - Device types: \(resolutionState.deviceType.deviceTypes.prefix(5))
            - Rooms: \(resolutionState.slots.rooms.prefix(5))
            - Values: \(resolutionState.slots.values.prefix(3))
            - Memory device IDs: \(memoryHints.compactMap(\.deviceID).prefix(5))
            """
        }

        return (
            level,
            """
            User command: \(userText)

            \(hintBlock)

            \(candidateLabel):
            \(candidateLines)
            """
        )
    }
}
