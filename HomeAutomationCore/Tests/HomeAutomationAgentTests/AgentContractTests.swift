import HomeAutomationAgents
import Testing

@Suite
struct AgentContractTests {
    @Test
    func definesAllPhaseOneAgentIdentities() {
        let ids: Set<AgentID> = [
            .language,
            .domain,
            .intentFamily,
            .deviceType,
            .slotExtraction,
            .riskClassification,
            .capabilityKnowledge,
            .bixbyKnowledge,
            .commandExample,
            .candidateRetrieval,
            .candidateRanking,
            .candidateShard,
            .candidateHydration,
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

        #expect(ids.count == 26)
    }

    @Test
    func contextStartsWithEmptyPhaseOneCollections() {
        let context = ResolutionContext(
            request: CommandRequest(text: "turn on the light", executeLowRiskCommands: false)
        )

        #expect(context.retrievedCandidates.isEmpty)
        #expect(context.knowledgeSnippets.isEmpty)
        #expect(context.memoryHints.isEmpty)
        #expect(context.trace.isEmpty)
    }
}
