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
    static let language = AgentID("language")
    static let domain = AgentID("domain")
    static let intentFamily = AgentID("intentFamily")
    static let deviceType = AgentID("deviceType")
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

    // Draft
    static let instructionComposer = AgentID("instructionComposer")
    static let draftGeneration = AgentID("draftGeneration")
    static let draftRepair = AgentID("draftRepair")

    // Safety
    static let safetyValidation = AgentID("safetyValidation")
    static let parameterValidation = AgentID("parameterValidation")
    static let confirmationPolicy = AgentID("confirmationPolicy")

    // Execution
    static let executionPlanning = AgentID("executionPlanning")
    static let mockExecution = AgentID("mockExecution")

    // Fallback
    static let ruleFallback = AgentID("ruleFallback")
    static let bixbyFallback = AgentID("bixbyFallback")
    static let unsupportedCommand = AgentID("unsupportedCommand")

    // Response
    static let clarification = AgentID("clarification")
    static let resultSummary = AgentID("resultSummary")
}

/// What an agent can do, used by the registry and planner for dynamic lookup.
public enum AgentCapability: String, Sendable, Hashable, Codable {
    case languageDetection
    case domainClassification
    case intentClassification
    case deviceTypeExtraction
    case slotExtraction
    case riskClassification
    case knowledgeRetrieval
    case candidateRetrieval
    case candidateRanking
    case candidateSharding
    case candidateHydration
    case instructionComposition
    case draftGeneration
    case draftRepair
    case safetyValidation
    case parameterValidation
    case confirmationPolicy
    case executionPlanning
    case execution
    case ruleFallback
    case bixbyFallback
    case unsupported
    case clarification
    case resultSummary
}
