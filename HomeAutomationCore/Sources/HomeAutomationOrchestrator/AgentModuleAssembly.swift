import Foundation
import HomeAutomationAgents
import HomeAutomationCore

internal protocol AgentModule: Sendable {
    var name: String { get }
    func makeAgents() -> [any AnyHomeAgent]
}

internal struct StaticAgentModule: AgentModule {
    let name: String
    let agents: [any AnyHomeAgent]

    func makeAgents() -> [any AnyHomeAgent] {
        agents
    }
}

extension DefaultAgentRegistryFactory {
    internal static func agentModules(from agents: [any AnyHomeAgent]) -> [any AgentModule] {
        let agentsByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        let moduleDefinitions: [(name: String, ids: [AgentID])] = [
            ("operationDetection", [.operationDetection]),
            ("nlu", [.semanticNLU, .slotExtraction, .riskClassification]),
            ("automation", [
                .automationComponentSegmentation,
                .automationComponentFanOut,
                .automationDraftAssembly,
                .automationTriggerResolution,
                .automationConditionClauseResolution,
                .automationDraft,
                .automationConditionOperandResolution,
                .automationActionResolution,
                .automationValidation,
                .automationResultAssembly
            ]),
            ("smartThings", [.smartThingsCompilation, .smartThingsRuleCreation]),
            ("knowledge", [.capabilityKnowledge, .bixbyKnowledge, .commandExample, .retrievalJudge]),
            ("candidates", [.candidateRetrieval, .candidateRanking, .candidateShard, .candidateHydration, .capabilityResolution]),
            ("draft", [.instructionComposer, .draftGeneration, .draftRepair]),
            ("safety", [.safetyValidation, .parameterValidation, .confirmationPolicy]),
            ("execution", [.executionPlanning, .mockExecution]),
            ("fallback", [.ruleFallback, .bixbyFallback, .unsupportedCommand]),
            ("response", [.clarification, .resultSummary])
        ]

        var assignedIDs = Set<AgentID>()
        var modules: [any AgentModule] = moduleDefinitions.map { definition in
            assignedIDs.formUnion(definition.ids)
            return StaticAgentModule(
                name: definition.name,
                agents: definition.ids.compactMap { agentsByID[$0] }
            )
        }

        let remainingAgents = agents.filter { !assignedIDs.contains($0.id) }
        if !remainingAgents.isEmpty {
            modules.append(StaticAgentModule(name: "unassigned", agents: remainingAgents))
        }
        return modules
    }
}
