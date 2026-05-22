import HomeAutomationAgents
import Testing

@Suite
struct AgentContractTests {
    @Test
    func definesAllPhaseOneAgentIdentities() {
        let ids: Set<AgentID> = [
            .semanticNLU,
            .slotExtraction,
            .riskClassification,
            .capabilityKnowledge,
            .bixbyKnowledge,
            .commandExample,
            .candidateRetrieval,
            .candidateRanking,
            .candidateShard,
            .candidateHydration,
            .capabilityResolution,
            .instructionComposer,
            .draftGeneration,
            .draftRepair,
            .safetyValidation,
            .parameterValidation,
            .confirmationPolicy,
            .executionPlanning,
            .mockExecution,
            .ruleFallback,
            .bixbyFallback,
            .unsupportedCommand,
            .clarification,
            .resultSummary
        ]

        #expect(ids.count == 24)
    }

    @Test
    func contextStartsWithEmptyPhaseOneCollections() {
        let context = ResolutionContext(
            request: CommandRequest(text: "turn on the light", executeLowRiskCommands: false)
        )

        #expect(context.retrievedCandidates.isEmpty)
        #expect(context.knowledgeSnippets.isEmpty)
        #expect(context.capabilityDecision == nil)
        #expect(context.memoryHints.isEmpty)
        #expect(context.trace.isEmpty)
    }
}
