import Foundation

public struct HomeAutomationExecutionStep: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public let type: String
    public let deviceID: String
    public let deviceName: String
    public let capability: String
    public let command: String
    public let value: String?
    public let attribute: String?
    public let valueFormula: String?

    public init(
        id: UUID = UUID(),
        type: String,
        deviceID: String,
        deviceName: String,
        capability: String,
        command: String,
        value: String? = nil,
        attribute: String? = nil,
        valueFormula: String? = nil
    ) {
        self.id = id
        self.type = type
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.capability = capability
        self.command = command
        self.value = value
        self.attribute = attribute
        self.valueFormula = valueFormula
    }
}

public struct HomeAutomationExecutionPlan: Sendable, Hashable, Codable {
    public let steps: [HomeAutomationExecutionStep]
    public let requiresConfirmation: Bool

    public init(steps: [HomeAutomationExecutionStep], requiresConfirmation: Bool) {
        self.steps = steps
        self.requiresConfirmation = requiresConfirmation
    }
}

public enum HomeCommandResolution: Sendable, Hashable, Codable {
    case readyToExecute(HomeAutomationExecutionPlan)
    case executed(HomeAutomationExecutionPlan, updatedDevice: HomeCandidateRecord)
    case requiresConfirmation(HomeCommandDraft)
    case automationDrafted(HomeAutomationCreationPlan)
    case automationRequiresConfirmation(HomeAutomationCreationPlan)
    case needsClarification(String)
    case unsupported(String)

    public var displaySummary: String {
        switch self {
        case .readyToExecute(let plan):
            if plan.steps.allSatisfy({ $0.type == "query" }) {
                return "Resolved \(plan.steps.count) status query step(s)."
            }
            return "Ready to execute \(plan.steps.count) low-risk step(s)."
        case .executed(let plan, let device):
            return "Executed \(plan.steps.count) step(s) on \(device.displayName)."
        case .requiresConfirmation:
            return "This command requires confirmation before execution."
        case .automationDrafted(let plan):
            let suffix = Self.conditionReadingSuffix(for: plan)
            if plan.backendResponse?.status == .created {
                return "Automation created with \(plan.resolvedActions.count) action(s)\(suffix)."
            }
            if plan.smartThingsRuleJSON != nil {
                return "Automation drafted with \(plan.resolvedActions.count) action(s) and SmartThings JSON\(suffix)."
            }
            return "Automation drafted with \(plan.resolvedActions.count) action(s)\(suffix)."
        case .automationRequiresConfirmation(let plan):
            let suffix = Self.conditionReadingSuffix(for: plan)
            return "This automation requires confirmation before it can be created\(suffix)."
        case .needsClarification(let question):
            return question
        case .unsupported(let reason):
            return reason
        }
    }

    /// Renders the committed condition interpretation as a `" if <reading>"`
    /// suffix so the parser's boolean-precedence reading is always user-visible
    /// on a drafted automation (redesign item A-4). Empty when the automation
    /// has no condition.
    private static func conditionReadingSuffix(for plan: HomeAutomationCreationPlan) -> String {
        guard let condition = plan.ruleDraft.condition else { return "" }
        return " if \(condition.parenthesizedDescription())"
    }
}

public struct HomeFinalResolutionInput: Sendable, Hashable, Codable {
    public let rawText: String
    public let resolutionState: HomeResolutionState
    public let hydratedCandidates: [HomeCandidateRecord]
    public let aggregation: HomeCandidateAggregationResult
    public let capabilityDecision: HomeCapabilityDecision?

    public init(
        rawText: String,
        resolutionState: HomeResolutionState,
        hydratedCandidates: [HomeCandidateRecord],
        aggregation: HomeCandidateAggregationResult,
        capabilityDecision: HomeCapabilityDecision? = nil
    ) {
        self.rawText = rawText
        self.resolutionState = resolutionState
        self.hydratedCandidates = hydratedCandidates
        self.aggregation = aggregation
        self.capabilityDecision = capabilityDecision
    }
}

public struct HomeAutomationSubgraphRunSummary: Sendable, Hashable, Codable {
    public let id: String
    public let parentNodeID: String
    public let scopeID: String
    public let graphID: String
    public let goal: String
    public let nodeStatuses: [String: String]
    public let selectedAgents: [String: String]
    public let skippedNodeIDs: [String]
    public let nodeDurations: [String: Double]

    public init(
        id: String,
        parentNodeID: String,
        scopeID: String,
        graphID: String,
        goal: String,
        nodeStatuses: [String: String],
        selectedAgents: [String: String],
        skippedNodeIDs: [String],
        nodeDurations: [String: Double]
    ) {
        self.id = id
        self.parentNodeID = parentNodeID
        self.scopeID = scopeID
        self.graphID = graphID
        self.goal = goal
        self.nodeStatuses = nodeStatuses
        self.selectedAgents = selectedAgents
        self.skippedNodeIDs = skippedNodeIDs
        self.nodeDurations = nodeDurations
    }
}
