import Foundation

/// Unique identity for each agent.
public struct AgentID: Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

public extension AgentID {
    // NLU
    static let operationDetection = AgentID("operationDetection")
    static let semanticNLU = AgentID("semanticNLU")
    static let slotExtraction = AgentID("slotExtraction")
    static let riskClassification = AgentID("riskClassification")

    // Knowledge
    static let capabilityKnowledge = AgentID("capabilityKnowledge")
    static let bixbyKnowledge = AgentID("bixbyKnowledge")
    static let commandExample = AgentID("commandExample")
    static let retrievalJudge = AgentID("retrievalJudge")

    // Candidates
    static let candidateRetrieval = AgentID("candidateRetrieval")
    static let candidateRanking = AgentID("candidateRanking")
    static let candidateShard = AgentID("candidateShard")
    static let candidateHydration = AgentID("candidateHydration")
    static let capabilityResolution = AgentID("capabilityResolution")

    // Draft
    static let automationDraft = AgentID("automationDraft")
    static let automationActionResolution = AgentID("automationActionResolution")
    static let automationConditionOperandResolution = AgentID("automationConditionOperandResolution")
    static let instructionComposer = AgentID("instructionComposer")
    static let draftGeneration = AgentID("draftGeneration")
    static let draftRepair = AgentID("draftRepair")

    // Safety
    static let automationValidation = AgentID("automationValidation")
    static let safetyValidation = AgentID("safetyValidation")
    static let parameterValidation = AgentID("parameterValidation")
    static let confirmationPolicy = AgentID("confirmationPolicy")

    // Execution
    static let executionPlanning = AgentID("executionPlanning")
    static let mockExecution = AgentID("mockExecution")
    static let smartThingsCompilation = AgentID("smartThingsCompilation")
    static let smartThingsRuleCreation = AgentID("smartThingsRuleCreation")

    // Fallback
    static let ruleFallback = AgentID("ruleFallback")
    static let bixbyFallback = AgentID("bixbyFallback")
    static let unsupportedCommand = AgentID("unsupportedCommand")

    // Response
    static let automationResultAssembly = AgentID("automationResultAssembly")
    static let clarification = AgentID("clarification")
    static let resultSummary = AgentID("resultSummary")
}

/// What an agent can do, used by the registry and planner for dynamic lookup.
public enum AgentCapability: String, Sendable, Hashable, Codable {
    case operationDetection
    case intentClassification
    case deviceTypeExtraction
    case slotExtraction
    case riskClassification
    case knowledgeRetrieval
    case candidateRetrieval
    case candidateRanking
    case candidateSharding
    case candidateHydration
    case capabilityResolution
    case instructionComposition
    case draftGeneration
    case draftRepair
    case automationDrafting
    case automationActionResolution
    case automationConditionOperandResolution
    case automationValidation
    case smartThingsCompilation
    case safetyValidation
    case parameterValidation
    case confirmationPolicy
    case executionPlanning
    case execution
    case ruleFallback
    case bixbyFallback
    case unsupported
    case automationResultAssembly
    case smartThingsRuleCreation
    case clarification
    case resultSummary
}
