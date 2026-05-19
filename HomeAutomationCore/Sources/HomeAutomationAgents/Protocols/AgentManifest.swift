import Foundation
import HomeAutomationCore

public struct AgentManifest: Sendable, Hashable {
    public let id: AgentID
    public let capabilities: Set<AgentCapability>
    public let supportedOperations: Set<HomeAutomationOperationKind>
    public let consumes: Set<String>
    public let produces: Set<String>
    public let safetyRole: AgentSafetyRole
    public let retryPolicy: AgentRetryPolicy
    public let priority: Int

    public init(
        id: AgentID,
        capabilities: Set<AgentCapability>,
        supportedOperations: Set<HomeAutomationOperationKind> = [.executeDeviceCommand],
        consumes: Set<String> = [],
        produces: Set<String> = [],
        safetyRole: AgentSafetyRole = .none,
        retryPolicy: AgentRetryPolicy = .noRetry,
        priority: Int = 0
    ) {
        self.id = id
        self.capabilities = capabilities
        self.supportedOperations = supportedOperations
        self.consumes = consumes
        self.produces = produces
        self.safetyRole = safetyRole
        self.retryPolicy = retryPolicy
        self.priority = priority
    }
}

public enum AgentSafetyRole: Sendable, Hashable {
    case none
    case requiredGate
    case executionGate
}

public struct AgentRetryPolicy: Sendable, Hashable {
    public let maxAttempts: Int

    public init(maxAttempts: Int) {
        self.maxAttempts = maxAttempts
    }

    public static let noRetry = AgentRetryPolicy(maxAttempts: 0)
    public static let singleRetry = AgentRetryPolicy(maxAttempts: 1)
}

public enum AgentManifestDefaults {
    public static func manifest(
        id: AgentID,
        capabilities: Set<AgentCapability>
    ) -> AgentManifest {
        AgentManifest(
            id: id,
            capabilities: capabilities,
            supportedOperations: supportedOperations(for: id),
            consumes: consumes(for: id),
            produces: produces(for: id),
            safetyRole: safetyRole(for: id),
            retryPolicy: retryPolicy(for: id),
            priority: priority(for: id)
        )
    }

    private static func supportedOperations(for id: AgentID) -> Set<HomeAutomationOperationKind> {
        switch id {
        case .operationDetection:
            return [
                .executeDeviceCommand,
                .automationCreation,
                .automationUpdate,
                .automationDeletion,
                .automationQuery,
                .sceneCreation,
                .routineExecution,
                .unsupported
            ]
        case .automationDraft,
             .automationActionResolution,
             .automationConditionOperandResolution,
             .automationValidation,
             .smartThingsCompilation,
             .smartThingsRuleCreation,
             .automationResultAssembly:
            return [.automationCreation]
        default:
            return [.executeDeviceCommand]
        }
    }

    private static func consumes(for id: AgentID) -> Set<String> {
        switch id {
        case .language, .domain, .intentFamily, .deviceType, .slotExtraction, .riskClassification:
            return ["request.text"]
        case .capabilityKnowledge, .bixbyKnowledge, .commandExample, .candidateRetrieval:
            return ["request.text", "resolutionState"]
        case .retrievalJudge:
            return ["request.text", "knowledgeSnippets"]
        case .candidateRanking:
            return ["request.text", "resolutionState", "retrievedCandidates"]
        case .candidateHydration:
            return ["selectedCandidateIDs", "aggregation"]
        case .capabilityResolution:
            return ["request.text", "resolutionState", "hydratedCandidates", "aggregation", "knowledgeSnippets"]
        case .instructionComposer:
            return ["resolutionState", "hydratedCandidates", "aggregation", "knowledgeSnippets", "capabilityDecision"]
        case .draftGeneration, .draftRepair:
            return ["instructionPackage"]
        case .safetyValidation:
            return ["draft", "resolutionState", "hydratedCandidates", "aggregation"]
        case .parameterValidation:
            return ["draft", "hydratedCandidates"]
        case .confirmationPolicy:
            return ["draft", "hydratedCandidates"]
        case .executionPlanning:
            return ["draft", "hydratedCandidates"]
        case .mockExecution:
            return ["executionPlan"]
        case .ruleFallback, .bixbyFallback, .unsupportedCommand, .clarification, .resultSummary:
            return ["request.text"]
        case .operationDetection:
            return ["request.text"]
        case .automationDraft:
            return ["request.text", "operation"]
        case .automationActionResolution:
            return ["automationDraft"]
        case .automationConditionOperandResolution:
            return ["automationDraft"]
        case .automationValidation:
            return ["automationDraft", "automationResolvedActions", "automationConditionOperandResolutionRecords"]
        case .smartThingsCompilation:
            return ["automationDraft", "automationResolvedActions", "automationValidation"]
        case .smartThingsRuleCreation:
            return ["automationPlan", "smartThingsRule", "automationValidation", "request.automationCreationOptions"]
        case .automationResultAssembly:
            return ["automationDraft", "automationResolvedActions", "automationValidation", "automationPlan", "smartThingsRule", "smartThingsRuleCreation"]
        default:
            return []
        }
    }

    private static func produces(for id: AgentID) -> Set<String> {
        switch id {
        case .language:
            return ["language", "resolutionState"]
        case .domain:
            return ["domain", "resolutionState"]
        case .intentFamily:
            return ["intent", "resolutionState"]
        case .deviceType:
            return ["deviceType", "resolutionState"]
        case .slotExtraction:
            return ["slots", "resolutionState"]
        case .riskClassification:
            return ["risk", "resolutionState"]
        case .capabilityKnowledge, .bixbyKnowledge, .commandExample, .retrievalJudge:
            return ["knowledgeSnippets", "retrievalReports"]
        case .candidateRetrieval:
            return ["retrievedCandidates"]
        case .candidateRanking:
            return ["aggregation", "selectedCandidateIDs", "resolution"]
        case .candidateShard:
            return ["selectedCandidateIDs"]
        case .candidateHydration:
            return ["hydratedCandidates"]
        case .capabilityResolution:
            return ["capabilityDecision"]
        case .instructionComposer:
            return ["instructionPackage"]
        case .draftGeneration, .draftRepair:
            return ["draft"]
        case .safetyValidation:
            return ["resolution", "executionPlan"]
        case .parameterValidation, .confirmationPolicy:
            return ["resolution"]
        case .executionPlanning:
            return ["executionPlan", "resolution"]
        case .mockExecution:
            return ["resolution"]
        case .ruleFallback:
            return ["resolverResult"]
        case .bixbyFallback:
            return ["aggregation", "hydratedCandidates", "draft"]
        case .unsupportedCommand, .clarification, .resultSummary:
            return ["resolution"]
        case .operationDetection:
            return ["operation"]
        case .automationDraft:
            return ["automationDraft", "retrievalReports"]
        case .automationActionResolution:
            return ["automationResolvedActions"]
        case .automationConditionOperandResolution:
            return ["automationDraft", "automationConditionOperandResolutionRecords"]
        case .automationValidation:
            return ["automationValidation", "resolution"]
        case .smartThingsCompilation:
            return ["smartThingsRule", "automationPlan"]
        case .smartThingsRuleCreation:
            return ["smartThingsRuleCreation", "automationPlan"]
        case .automationResultAssembly:
            return ["resolverResult", "resolution"]
        default:
            return []
        }
    }

    private static func safetyRole(for id: AgentID) -> AgentSafetyRole {
        switch id {
        case .safetyValidation, .parameterValidation, .confirmationPolicy:
            return .requiredGate
        case .executionPlanning, .mockExecution:
            return .executionGate
        case .automationValidation:
            return .requiredGate
        default:
            return .none
        }
    }

    private static func retryPolicy(for id: AgentID) -> AgentRetryPolicy {
        switch id {
        case .draftGeneration:
            return AgentRetryPolicy(maxAttempts: 3)
        case .language, .domain, .intentFamily, .deviceType, .slotExtraction, .riskClassification:
            return .singleRetry
        case .candidateRetrieval, .candidateRanking, .ruleFallback:
            return .singleRetry
        default:
            return .noRetry
        }
    }

    private static func priority(for id: AgentID) -> Int {
        switch id {
        case .operationDetection:
            return 100
        case .automationDraft,
             .automationActionResolution,
             .automationConditionOperandResolution,
             .automationValidation,
             .smartThingsCompilation,
             .smartThingsRuleCreation,
             .automationResultAssembly:
            return 90
        case .safetyValidation, .parameterValidation, .confirmationPolicy, .executionPlanning:
            return 80
        default:
            return 0
        }
    }
}
