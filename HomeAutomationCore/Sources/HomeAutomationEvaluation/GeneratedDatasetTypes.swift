import Foundation
import HomeAutomationCore

public enum EvaluationCommandGenerationMode: String, Sendable, Codable, Hashable {
    case codex
    case template
    case foundationModel
}

public struct EvaluationDatasetSpec: Sendable, Codable, Hashable {
    public let datasetName: String
    public let version: String
    public let fixtureCount: Int
    public let commandsPerFixture: Int
    public let randomSeed: Int
    public let generationMode: EvaluationCommandGenerationMode
    public let suiteDistribution: [String: Int]
    public let tags: [String]

    public init(
        datasetName: String,
        version: String,
        fixtureCount: Int,
        commandsPerFixture: Int,
        randomSeed: Int,
        generationMode: EvaluationCommandGenerationMode,
        suiteDistribution: [String: Int] = [:],
        tags: [String] = []
    ) {
        self.datasetName = datasetName
        self.version = version
        self.fixtureCount = fixtureCount
        self.commandsPerFixture = commandsPerFixture
        self.randomSeed = randomSeed
        self.generationMode = generationMode
        self.suiteDistribution = suiteDistribution
        self.tags = tags
    }
}

public struct EvaluationDatasetManifest: Sendable, Codable, Hashable {
    public let name: String
    public let version: String
    public let generatedAt: String
    public let generatorVersion: String
    public let fixtureCount: Int
    public let caseCount: Int
    public let commandsPerFixture: Int
    public let generationMode: String
    public let randomSeed: Int
    public let validationStatus: String

    public init(
        name: String,
        version: String,
        generatedAt: String,
        generatorVersion: String,
        fixtureCount: Int,
        caseCount: Int,
        commandsPerFixture: Int,
        generationMode: String,
        randomSeed: Int,
        validationStatus: String
    ) {
        self.name = name
        self.version = version
        self.generatedAt = generatedAt
        self.generatorVersion = generatorVersion
        self.fixtureCount = fixtureCount
        self.caseCount = caseCount
        self.commandsPerFixture = commandsPerFixture
        self.generationMode = generationMode
        self.randomSeed = randomSeed
        self.validationStatus = validationStatus
    }
}

public struct GeneratedEvaluationFixture: Sendable, Codable, Hashable {
    public let id: String
    public let name: String
    public let category: String
    public let devices: [HomeCandidateRecord]
    public let notes: String?

    public init(
        id: String,
        name: String,
        category: String,
        devices: [HomeCandidateRecord],
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.devices = devices
        self.notes = notes
    }
}

public struct GeneratedEvaluationCase: Sendable, Codable, Hashable {
    public let id: String
    public let fixtureID: String
    public let suite: String
    public let tags: [String]
    public let input: String
    public let canonicalCommandID: String
    public let expected: ExpectedResolvedOutput
    public let traceContractID: String
    public let metricsContractID: String

    public init(
        id: String,
        fixtureID: String,
        suite: String,
        tags: [String],
        input: String,
        canonicalCommandID: String,
        expected: ExpectedResolvedOutput,
        traceContractID: String,
        metricsContractID: String
    ) {
        self.id = id
        self.fixtureID = fixtureID
        self.suite = suite
        self.tags = tags
        self.input = input
        self.canonicalCommandID = canonicalCommandID
        self.expected = expected
        self.traceContractID = traceContractID
        self.metricsContractID = metricsContractID
    }
}

public struct ExpectedResolvedOutput: Sendable, Codable, Hashable {
    public let operation: HomeAutomationOperationKind?
    public let domain: HomeAutomationCommandDomain?
    public let languageCode: String?
    public let allowedOutcome: EvaluationAllowedOutcome
    public let expectedDeviceIDs: [String]
    public let targetDeviceID: String?
    public let capability: String?
    public let command: String?
    public let parameters: [String: String]
    public let actionCount: Int?
    public let conditionCount: Int?
    public let conditionTreeKind: String?
    public let smartThingsJSONContains: [String]
    public let expectedSmartThingsRuleJSON: String?

    public init(
        operation: HomeAutomationOperationKind? = nil,
        domain: HomeAutomationCommandDomain? = nil,
        languageCode: String? = "en",
        allowedOutcome: EvaluationAllowedOutcome,
        expectedDeviceIDs: [String] = [],
        targetDeviceID: String? = nil,
        capability: String? = nil,
        command: String? = nil,
        parameters: [String: String] = [:],
        actionCount: Int? = nil,
        conditionCount: Int? = nil,
        conditionTreeKind: String? = nil,
        smartThingsJSONContains: [String] = [],
        expectedSmartThingsRuleJSON: String? = nil
    ) {
        self.operation = operation
        self.domain = domain
        self.languageCode = languageCode
        self.allowedOutcome = allowedOutcome
        self.expectedDeviceIDs = expectedDeviceIDs
        self.targetDeviceID = targetDeviceID
        self.capability = capability
        self.command = command
        self.parameters = parameters
        self.actionCount = actionCount
        self.conditionCount = conditionCount
        self.conditionTreeKind = conditionTreeKind
        self.smartThingsJSONContains = smartThingsJSONContains
        self.expectedSmartThingsRuleJSON = expectedSmartThingsRuleJSON
    }
}

public struct ExpectedTraceContract: Sendable, Codable, Hashable {
    public let id: String
    public let caseID: String
    public let requiredGraphs: [String]
    public let graphPathAlternatives: [[String]]
    public let requiredAgents: [ExpectedAgentContract]
    public let agentPathAlternatives: [[ExpectedAgentContract]]
    public let requiredTools: [ExpectedToolContract]
    public let requiredComponents: [ExpectedAutomationComponentContract]
    public let allowedFailedAgents: [String]
    public let allowedSkippedAgents: [String]
    public let expectedSelectedDeviceIDs: [String]
    public let expectedCapability: String?
    public let expectedCommand: String?
    public let maxModelCallCount: Int?
    public let maxToolCallCount: Int?
    public let allowContextWindowFailures: Bool
    public let requireAgentTraceIdentity: Bool
    public let requireToolTraceIdentity: Bool
    public let requireToolCallerIdentityPropagation: Bool

    public init(
        id: String,
        caseID: String,
        requiredGraphs: [String] = [],
        graphPathAlternatives: [[String]] = [],
        requiredAgents: [ExpectedAgentContract] = [],
        agentPathAlternatives: [[ExpectedAgentContract]] = [],
        requiredTools: [ExpectedToolContract] = [],
        requiredComponents: [ExpectedAutomationComponentContract] = [],
        allowedFailedAgents: [String] = [],
        allowedSkippedAgents: [String] = [],
        expectedSelectedDeviceIDs: [String] = [],
        expectedCapability: String? = nil,
        expectedCommand: String? = nil,
        maxModelCallCount: Int? = nil,
        maxToolCallCount: Int? = nil,
        allowContextWindowFailures: Bool = false,
        requireAgentTraceIdentity: Bool = true,
        requireToolTraceIdentity: Bool = true,
        requireToolCallerIdentityPropagation: Bool = true
    ) {
        self.id = id
        self.caseID = caseID
        self.requiredGraphs = requiredGraphs
        self.graphPathAlternatives = graphPathAlternatives
        self.requiredAgents = requiredAgents
        self.agentPathAlternatives = agentPathAlternatives
        self.requiredTools = requiredTools
        self.requiredComponents = requiredComponents
        self.allowedFailedAgents = allowedFailedAgents
        self.allowedSkippedAgents = allowedSkippedAgents
        self.expectedSelectedDeviceIDs = expectedSelectedDeviceIDs
        self.expectedCapability = expectedCapability
        self.expectedCommand = expectedCommand
        self.maxModelCallCount = maxModelCallCount
        self.maxToolCallCount = maxToolCallCount
        self.allowContextWindowFailures = allowContextWindowFailures
        self.requireAgentTraceIdentity = requireAgentTraceIdentity
        self.requireToolTraceIdentity = requireToolTraceIdentity
        self.requireToolCallerIdentityPropagation = requireToolCallerIdentityPropagation
    }

    enum CodingKeys: String, CodingKey {
        case id
        case caseID
        case requiredGraphs
        case graphPathAlternatives
        case requiredAgents
        case agentPathAlternatives
        case requiredTools
        case requiredComponents
        case allowedFailedAgents
        case allowedSkippedAgents
        case expectedSelectedDeviceIDs
        case expectedCapability
        case expectedCommand
        case maxModelCallCount
        case maxToolCallCount
        case allowContextWindowFailures
        case requireAgentTraceIdentity
        case requireToolTraceIdentity
        case requireToolCallerIdentityPropagation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        caseID = try container.decode(String.self, forKey: .caseID)
        requiredGraphs = try container.decodeIfPresent([String].self, forKey: .requiredGraphs) ?? []
        graphPathAlternatives = try container.decodeIfPresent([[String]].self, forKey: .graphPathAlternatives) ?? []
        requiredAgents = try container.decodeIfPresent([ExpectedAgentContract].self, forKey: .requiredAgents) ?? []
        agentPathAlternatives = try container.decodeIfPresent([[ExpectedAgentContract]].self, forKey: .agentPathAlternatives) ?? []
        requiredTools = try container.decodeIfPresent([ExpectedToolContract].self, forKey: .requiredTools) ?? []
        requiredComponents = try container.decodeIfPresent([ExpectedAutomationComponentContract].self, forKey: .requiredComponents) ?? []
        allowedFailedAgents = try container.decodeIfPresent([String].self, forKey: .allowedFailedAgents) ?? []
        allowedSkippedAgents = try container.decodeIfPresent([String].self, forKey: .allowedSkippedAgents) ?? []
        expectedSelectedDeviceIDs = try container.decodeIfPresent([String].self, forKey: .expectedSelectedDeviceIDs) ?? []
        expectedCapability = try container.decodeIfPresent(String.self, forKey: .expectedCapability)
        expectedCommand = try container.decodeIfPresent(String.self, forKey: .expectedCommand)
        maxModelCallCount = try container.decodeIfPresent(Int.self, forKey: .maxModelCallCount)
        maxToolCallCount = try container.decodeIfPresent(Int.self, forKey: .maxToolCallCount)
        allowContextWindowFailures = try container.decodeIfPresent(Bool.self, forKey: .allowContextWindowFailures) ?? false
        requireAgentTraceIdentity = try container.decodeIfPresent(Bool.self, forKey: .requireAgentTraceIdentity) ?? true
        requireToolTraceIdentity = try container.decodeIfPresent(Bool.self, forKey: .requireToolTraceIdentity) ?? true
        requireToolCallerIdentityPropagation = try container.decodeIfPresent(Bool.self, forKey: .requireToolCallerIdentityPropagation) ?? true
    }
}

public struct ExpectedAgentContract: Sendable, Codable, Hashable {
    public let agentID: String
    public let required: Bool
    public let expectedStatus: String?
    public let minimumCount: Int
    public let maximumCount: Int?
    public let expectedOutputMarkers: [String]
    public let expectedSelectedDeviceIDs: [String]
    public let allowedFallbackReasons: [String]
    public let maxModelCalls: Int?
    public let maxDurationMs: Double?
    public let requireInputOutputTraceIDs: Bool
    public let requireStableSessionWithinCase: Bool
    public let requirePositiveRunID: Bool

    public init(
        agentID: String,
        required: Bool = true,
        expectedStatus: String? = "completed",
        minimumCount: Int = 1,
        maximumCount: Int? = nil,
        expectedOutputMarkers: [String] = [],
        expectedSelectedDeviceIDs: [String] = [],
        allowedFallbackReasons: [String] = [],
        maxModelCalls: Int? = nil,
        maxDurationMs: Double? = nil,
        requireInputOutputTraceIDs: Bool = true,
        requireStableSessionWithinCase: Bool = true,
        requirePositiveRunID: Bool = true
    ) {
        self.agentID = agentID
        self.required = required
        self.expectedStatus = expectedStatus
        self.minimumCount = minimumCount
        self.maximumCount = maximumCount
        self.expectedOutputMarkers = expectedOutputMarkers
        self.expectedSelectedDeviceIDs = expectedSelectedDeviceIDs
        self.allowedFallbackReasons = allowedFallbackReasons
        self.maxModelCalls = maxModelCalls
        self.maxDurationMs = maxDurationMs
        self.requireInputOutputTraceIDs = requireInputOutputTraceIDs
        self.requireStableSessionWithinCase = requireStableSessionWithinCase
        self.requirePositiveRunID = requirePositiveRunID
    }
}

public struct ExpectedToolContract: Sendable, Codable, Hashable {
    public let toolID: String
    public let required: Bool
    public let expectedStatus: String?
    public let minimumCount: Int
    public let maximumCount: Int?
    public let expectedCallerAgentIDs: [String]
    public let requireInputOutputPair: Bool
    public let requireToolSessionID: Bool
    public let requireToolCallID: Bool
    public let requireCallerAgentTraceIDs: Bool
    public let maxDurationMs: Double?

    public init(
        toolID: String,
        required: Bool = true,
        expectedStatus: String? = "completed",
        minimumCount: Int = 1,
        maximumCount: Int? = nil,
        expectedCallerAgentIDs: [String] = [],
        requireInputOutputPair: Bool = true,
        requireToolSessionID: Bool = true,
        requireToolCallID: Bool = true,
        requireCallerAgentTraceIDs: Bool = true,
        maxDurationMs: Double? = nil
    ) {
        self.toolID = toolID
        self.required = required
        self.expectedStatus = expectedStatus
        self.minimumCount = minimumCount
        self.maximumCount = maximumCount
        self.expectedCallerAgentIDs = expectedCallerAgentIDs
        self.requireInputOutputPair = requireInputOutputPair
        self.requireToolSessionID = requireToolSessionID
        self.requireToolCallID = requireToolCallID
        self.requireCallerAgentTraceIDs = requireCallerAgentTraceIDs
        self.maxDurationMs = maxDurationMs
    }
}

public struct ExpectedAutomationComponentContract: Sendable, Codable, Hashable {
    public let componentKind: String
    public let componentID: String
    public let expectedStatus: String
    public let expectedDeviceIDs: [String]
    public let expectedCapability: String?
    public let expectedCommand: String?

    public init(
        componentKind: String,
        componentID: String,
        expectedStatus: String = "completed",
        expectedDeviceIDs: [String] = [],
        expectedCapability: String? = nil,
        expectedCommand: String? = nil
    ) {
        self.componentKind = componentKind
        self.componentID = componentID
        self.expectedStatus = expectedStatus
        self.expectedDeviceIDs = expectedDeviceIDs
        self.expectedCapability = expectedCapability
        self.expectedCommand = expectedCommand
    }
}

public struct ExpectedMetricsContract: Sendable, Codable, Hashable {
    public let id: String
    public let caseID: String
    public let maxDurationMs: Double?
    public let maxModelCallCount: Int?
    public let maxSkippedModelCallCount: Int?
    public let maxToolCallCount: Int?
    public let maxContextWindowFailures: Int
    public let minCandidateRecallAt1: Double?
    public let minCandidateRecallAt3: Double?
    public let minCandidateRecallAt5: Double?
    public let expectedRetrievedCandidateContains: [String]
    public let expectedHydratedCandidateContains: [String]
    public let expectedSelectedCandidateIDs: [String]
    public let expectedActionCount: Int?
    public let expectedConditionCount: Int?

    public init(
        id: String,
        caseID: String,
        maxDurationMs: Double? = nil,
        maxModelCallCount: Int? = nil,
        maxSkippedModelCallCount: Int? = nil,
        maxToolCallCount: Int? = nil,
        maxContextWindowFailures: Int = 0,
        minCandidateRecallAt1: Double? = nil,
        minCandidateRecallAt3: Double? = nil,
        minCandidateRecallAt5: Double? = nil,
        expectedRetrievedCandidateContains: [String] = [],
        expectedHydratedCandidateContains: [String] = [],
        expectedSelectedCandidateIDs: [String] = [],
        expectedActionCount: Int? = nil,
        expectedConditionCount: Int? = nil
    ) {
        self.id = id
        self.caseID = caseID
        self.maxDurationMs = maxDurationMs
        self.maxModelCallCount = maxModelCallCount
        self.maxSkippedModelCallCount = maxSkippedModelCallCount
        self.maxToolCallCount = maxToolCallCount
        self.maxContextWindowFailures = maxContextWindowFailures
        self.minCandidateRecallAt1 = minCandidateRecallAt1
        self.minCandidateRecallAt3 = minCandidateRecallAt3
        self.minCandidateRecallAt5 = minCandidateRecallAt5
        self.expectedRetrievedCandidateContains = expectedRetrievedCandidateContains
        self.expectedHydratedCandidateContains = expectedHydratedCandidateContains
        self.expectedSelectedCandidateIDs = expectedSelectedCandidateIDs
        self.expectedActionCount = expectedActionCount
        self.expectedConditionCount = expectedConditionCount
    }
}

public struct NormalizedTrace: Sendable, Codable, Hashable {
    public let caseID: String
    public let spans: [NormalizedTraceSpan]
    public let selectedDeviceIDs: [String]
    public let targetDeviceID: String?
    public let capability: String?
    public let command: String?
    public let modelCallCount: Int
    public let toolCallCount: Int
    public let contextWindowFailureCount: Int
    public let agentIdentityChecks: [String: NormalizedAgentIdentityCheck]
    public let toolIdentityChecks: [String: NormalizedToolIdentityCheck]

    public init(
        caseID: String,
        spans: [NormalizedTraceSpan] = [],
        selectedDeviceIDs: [String] = [],
        targetDeviceID: String? = nil,
        capability: String? = nil,
        command: String? = nil,
        modelCallCount: Int = 0,
        toolCallCount: Int = 0,
        contextWindowFailureCount: Int = 0,
        agentIdentityChecks: [String: NormalizedAgentIdentityCheck] = [:],
        toolIdentityChecks: [String: NormalizedToolIdentityCheck] = [:]
    ) {
        self.caseID = caseID
        self.spans = spans
        self.selectedDeviceIDs = selectedDeviceIDs
        self.targetDeviceID = targetDeviceID
        self.capability = capability
        self.command = command
        self.modelCallCount = modelCallCount
        self.toolCallCount = toolCallCount
        self.contextWindowFailureCount = contextWindowFailureCount
        self.agentIdentityChecks = agentIdentityChecks
        self.toolIdentityChecks = toolIdentityChecks
    }
}

public struct NormalizedTraceSpan: Sendable, Codable, Hashable {
    public let eventType: String
    public let spanKind: String?
    public let graphID: String?
    public let stage: String?
    public let graphNodeID: String?
    public let agentID: String?
    public let agentInvocationGroup: String?
    public let agentSessionAlias: String?
    public let agentRunID: Int?
    public let componentKind: String?
    public let componentID: String?
    public let actionID: String?
    public let conditionID: String?
    public let toolID: String?
    public let toolSessionAlias: String?
    public let toolCallAlias: String?
    public let callerAgentID: String?
    public let callerAgentSessionAlias: String?
    public let callerAgentRunID: Int?
    public let status: String?
    public let payloadMarkers: [String: String]

    public init(
        eventType: String,
        spanKind: String? = nil,
        graphID: String? = nil,
        stage: String? = nil,
        graphNodeID: String? = nil,
        agentID: String? = nil,
        agentInvocationGroup: String? = nil,
        agentSessionAlias: String? = nil,
        agentRunID: Int? = nil,
        componentKind: String? = nil,
        componentID: String? = nil,
        actionID: String? = nil,
        conditionID: String? = nil,
        toolID: String? = nil,
        toolSessionAlias: String? = nil,
        toolCallAlias: String? = nil,
        callerAgentID: String? = nil,
        callerAgentSessionAlias: String? = nil,
        callerAgentRunID: Int? = nil,
        status: String? = nil,
        payloadMarkers: [String: String] = [:]
    ) {
        self.eventType = eventType
        self.spanKind = spanKind
        self.graphID = graphID
        self.stage = stage
        self.graphNodeID = graphNodeID
        self.agentID = agentID
        self.agentInvocationGroup = agentInvocationGroup
        self.agentSessionAlias = agentSessionAlias
        self.agentRunID = agentRunID
        self.componentKind = componentKind
        self.componentID = componentID
        self.actionID = actionID
        self.conditionID = conditionID
        self.toolID = toolID
        self.toolSessionAlias = toolSessionAlias
        self.toolCallAlias = toolCallAlias
        self.callerAgentID = callerAgentID
        self.callerAgentSessionAlias = callerAgentSessionAlias
        self.callerAgentRunID = callerAgentRunID
        self.status = status
        self.payloadMarkers = payloadMarkers
    }
}

public struct NormalizedAgentIdentityCheck: Sendable, Codable, Hashable {
    public let agentID: String
    public let agentSessionAlias: String
    public let observedRunIDs: [Int]
    public let inputOutputPairs: Int
    public let missingInputTraceIDCount: Int
    public let missingOutputTraceIDCount: Int
    public let nonMonotonicRunIDCount: Int

    public init(
        agentID: String,
        agentSessionAlias: String,
        observedRunIDs: [Int] = [],
        inputOutputPairs: Int = 0,
        missingInputTraceIDCount: Int = 0,
        missingOutputTraceIDCount: Int = 0,
        nonMonotonicRunIDCount: Int = 0
    ) {
        self.agentID = agentID
        self.agentSessionAlias = agentSessionAlias
        self.observedRunIDs = observedRunIDs
        self.inputOutputPairs = inputOutputPairs
        self.missingInputTraceIDCount = missingInputTraceIDCount
        self.missingOutputTraceIDCount = missingOutputTraceIDCount
        self.nonMonotonicRunIDCount = nonMonotonicRunIDCount
    }
}

public struct NormalizedToolIdentityCheck: Sendable, Codable, Hashable {
    public let toolID: String
    public let toolSessionAlias: String?
    public let toolCallAlias: String
    public let callerAgentID: String?
    public let callerAgentSessionAlias: String?
    public let callerAgentRunID: Int?
    public let hasInputEvent: Bool
    public let hasOutputEvent: Bool
    public let missingToolSessionID: Bool
    public let missingCallerAgentTraceID: Bool
    public let callerIdentityMismatch: Bool

    public init(
        toolID: String,
        toolSessionAlias: String? = nil,
        toolCallAlias: String,
        callerAgentID: String? = nil,
        callerAgentSessionAlias: String? = nil,
        callerAgentRunID: Int? = nil,
        hasInputEvent: Bool = false,
        hasOutputEvent: Bool = false,
        missingToolSessionID: Bool = false,
        missingCallerAgentTraceID: Bool = false,
        callerIdentityMismatch: Bool = false
    ) {
        self.toolID = toolID
        self.toolSessionAlias = toolSessionAlias
        self.toolCallAlias = toolCallAlias
        self.callerAgentID = callerAgentID
        self.callerAgentSessionAlias = callerAgentSessionAlias
        self.callerAgentRunID = callerAgentRunID
        self.hasInputEvent = hasInputEvent
        self.hasOutputEvent = hasOutputEvent
        self.missingToolSessionID = missingToolSessionID
        self.missingCallerAgentTraceID = missingCallerAgentTraceID
        self.callerIdentityMismatch = callerIdentityMismatch
    }
}

public struct TraceDiff: Sendable, Codable, Hashable {
    public let caseID: String
    public let passed: Bool
    public let missingRequiredAgents: [String]
    public let missingRequiredGraphs: [String]
    public let missingRequiredComponents: [String]
    public let wrongAgentStatuses: [String]
    public let unexpectedFailedAgents: [String]
    public let wrongSelectedDeviceIDs: [String]
    public let wrongCapability: String?
    public let wrongCommand: String?
    public let missingAgentTraceIDs: [String]
    public let missingToolTraceIDs: [String]
    public let unpairedToolCalls: [String]
    public let callerIdentityMismatches: [String]
    public let nonMonotonicAgentRunIDs: [String]
    public let budgetFailures: [String]
    public let notes: [String]

    public init(
        caseID: String,
        passed: Bool,
        missingRequiredAgents: [String] = [],
        missingRequiredGraphs: [String] = [],
        missingRequiredComponents: [String] = [],
        wrongAgentStatuses: [String] = [],
        unexpectedFailedAgents: [String] = [],
        wrongSelectedDeviceIDs: [String] = [],
        wrongCapability: String? = nil,
        wrongCommand: String? = nil,
        missingAgentTraceIDs: [String] = [],
        missingToolTraceIDs: [String] = [],
        unpairedToolCalls: [String] = [],
        callerIdentityMismatches: [String] = [],
        nonMonotonicAgentRunIDs: [String] = [],
        budgetFailures: [String] = [],
        notes: [String] = []
    ) {
        self.caseID = caseID
        self.passed = passed
        self.missingRequiredAgents = missingRequiredAgents
        self.missingRequiredGraphs = missingRequiredGraphs
        self.missingRequiredComponents = missingRequiredComponents
        self.wrongAgentStatuses = wrongAgentStatuses
        self.unexpectedFailedAgents = unexpectedFailedAgents
        self.wrongSelectedDeviceIDs = wrongSelectedDeviceIDs
        self.wrongCapability = wrongCapability
        self.wrongCommand = wrongCommand
        self.missingAgentTraceIDs = missingAgentTraceIDs
        self.missingToolTraceIDs = missingToolTraceIDs
        self.unpairedToolCalls = unpairedToolCalls
        self.callerIdentityMismatches = callerIdentityMismatches
        self.nonMonotonicAgentRunIDs = nonMonotonicAgentRunIDs
        self.budgetFailures = budgetFailures
        self.notes = notes
    }
}

public struct DatasetValidationIssue: Sendable, Codable, Hashable {
    public let severity: String
    public let caseID: String?
    public let fixtureID: String?
    public let field: String
    public let message: String

    public init(
        severity: String,
        caseID: String? = nil,
        fixtureID: String? = nil,
        field: String,
        message: String
    ) {
        self.severity = severity
        self.caseID = caseID
        self.fixtureID = fixtureID
        self.field = field
        self.message = message
    }
}

public struct GeneratedEvaluationDataset: Sendable, Codable, Hashable {
    public let manifest: EvaluationDatasetManifest
    public let fixtures: [GeneratedEvaluationFixture]
    public let cases: [GeneratedEvaluationCase]
    public let traceContracts: [ExpectedTraceContract]
    public let metricsContracts: [ExpectedMetricsContract]

    public init(
        manifest: EvaluationDatasetManifest,
        fixtures: [GeneratedEvaluationFixture] = [],
        cases: [GeneratedEvaluationCase] = [],
        traceContracts: [ExpectedTraceContract] = [],
        metricsContracts: [ExpectedMetricsContract] = []
    ) {
        self.manifest = manifest
        self.fixtures = fixtures
        self.cases = cases
        self.traceContracts = traceContracts
        self.metricsContracts = metricsContracts
    }
}
