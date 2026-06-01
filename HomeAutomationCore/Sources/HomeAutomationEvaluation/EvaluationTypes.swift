import Foundation
import HomeAutomationCore
import HomeAutomationOrchestrator

public enum EvaluationMode: String, Sendable, Codable, Hashable {
    case deterministic
    case live
}

public enum EvaluationAllowedOutcome: String, Sendable, Codable, Hashable {
    case ready
    case drafted
    case clarification
    case confirmation
    case unsupported
    case skipped
}

public struct EvaluationFixture: Sendable, Codable, Hashable {
    public let devices: [HomeCandidateRecord]

    public init(devices: [HomeCandidateRecord] = []) {
        self.devices = devices
    }
}

public struct EvaluationExpectedOutput: Sendable, Codable, Hashable {
    public let operation: HomeAutomationOperationKind?
    public let domain: HomeAutomationCommandDomain?
    public let languageCode: String?
    public let expectedDeviceIDs: [String]
    public let capability: String?
    public let command: String?
    public let actionCount: Int?
    public let conditionCount: Int?
    public let smartThingsJSONContains: [String]
    public let allowedOutcome: EvaluationAllowedOutcome
    public let maxDurationMs: Double?
    public let maxModelCallCount: Int?

    public init(
        operation: HomeAutomationOperationKind? = nil,
        domain: HomeAutomationCommandDomain? = nil,
        languageCode: String? = nil,
        expectedDeviceIDs: [String] = [],
        capability: String? = nil,
        command: String? = nil,
        actionCount: Int? = nil,
        conditionCount: Int? = nil,
        smartThingsJSONContains: [String] = [],
        allowedOutcome: EvaluationAllowedOutcome,
        maxDurationMs: Double? = nil,
        maxModelCallCount: Int? = nil
    ) {
        self.operation = operation
        self.domain = domain
        self.languageCode = languageCode
        self.expectedDeviceIDs = expectedDeviceIDs
        self.capability = capability
        self.command = command
        self.actionCount = actionCount
        self.conditionCount = conditionCount
        self.smartThingsJSONContains = smartThingsJSONContains
        self.allowedOutcome = allowedOutcome
        self.maxDurationMs = maxDurationMs
        self.maxModelCallCount = maxModelCallCount
    }
}

public enum EvaluationAssertion: String, Sendable, Codable, Hashable {
    case operationMatches
    case selectedDeviceMatches
    case capabilityMatches
    case commandMatches
    case outcomeAllowed
    case actionCountMatches
    case conditionCountMatches
    case smartThingsJSONContains
    case durationWithinBudget
    case modelCallWithinBudget
    case observabilityTracePresent
    case ragRecallAtK
}

public struct EvaluationCase: Sendable, Codable, Hashable {
    public let id: String
    public let suite: String
    public let tags: [String]
    public let input: String
    public let fixture: EvaluationFixture
    public let expected: EvaluationExpectedOutput

    public init(
        id: String,
        suite: String,
        tags: [String] = [],
        input: String,
        fixture: EvaluationFixture = EvaluationFixture(),
        expected: EvaluationExpectedOutput
    ) {
        self.id = id
        self.suite = suite
        self.tags = tags
        self.input = input
        self.fixture = fixture
        self.expected = expected
    }
}

public struct EvaluationCaseResult: Sendable, Codable, Hashable {
    public let id: String
    public let suite: String
    public let fixtureID: String?
    public let tags: [String]
    public let mode: EvaluationMode
    public let status: EvaluationAllowedOutcome
    public let passed: Bool
    public let skipped: Bool
    public let durationMs: Double
    public let traceID: String?
    public let assertionFailures: [String]
    public let expectedDeviceIDs: [String]
    public let selectedDeviceIDs: [String]
    public let actualTargetDeviceID: String?
    public let expectedCapability: String?
    public let actualCapability: String?
    public let expectedCommand: String?
    public let actualCommand: String?
    public let expectedActionCount: Int?
    public let actualActionCount: Int?
    public let expectedConditionCount: Int?
    public let actualConditionCount: Int?
    public let modelCallCount: Int
    public let toolCallCount: Int
    public let observability: EvaluationCaseObservabilityMetrics?
    public let metrics: RunMetricsV2?

    public init(
        id: String,
        suite: String,
        fixtureID: String? = nil,
        tags: [String] = [],
        mode: EvaluationMode,
        status: EvaluationAllowedOutcome,
        passed: Bool,
        skipped: Bool = false,
        durationMs: Double,
        traceID: String? = nil,
        assertionFailures: [String] = [],
        expectedDeviceIDs: [String] = [],
        selectedDeviceIDs: [String] = [],
        actualTargetDeviceID: String? = nil,
        expectedCapability: String? = nil,
        actualCapability: String? = nil,
        expectedCommand: String? = nil,
        actualCommand: String? = nil,
        expectedActionCount: Int? = nil,
        actualActionCount: Int? = nil,
        expectedConditionCount: Int? = nil,
        actualConditionCount: Int? = nil,
        modelCallCount: Int = 0,
        toolCallCount: Int = 0,
        observability: EvaluationCaseObservabilityMetrics? = nil,
        metrics: RunMetricsV2? = nil
    ) {
        self.id = id
        self.suite = suite
        self.fixtureID = fixtureID
        self.tags = tags
        self.mode = mode
        self.status = status
        self.passed = passed
        self.skipped = skipped
        self.durationMs = durationMs
        self.traceID = traceID
        self.assertionFailures = assertionFailures
        self.expectedDeviceIDs = expectedDeviceIDs
        self.selectedDeviceIDs = selectedDeviceIDs
        self.actualTargetDeviceID = actualTargetDeviceID
        self.expectedCapability = expectedCapability
        self.actualCapability = actualCapability
        self.expectedCommand = expectedCommand
        self.actualCommand = actualCommand
        self.expectedActionCount = expectedActionCount
        self.actualActionCount = actualActionCount
        self.expectedConditionCount = expectedConditionCount
        self.actualConditionCount = actualConditionCount
        self.modelCallCount = modelCallCount
        self.toolCallCount = toolCallCount
        self.observability = observability
        self.metrics = metrics
    }
}

public struct EvaluationCaseObservabilityMetrics: Sendable, Codable, Hashable {
    public let requiredAgents: [String]
    public let missingRequiredAgents: [String]
    public let agentInvocationCounts: [String: Int]
    public let agentStatusCounts: [String: [String: Int]]
    public let agentDurationSamplesMs: [String: [Double]]
    public let modelCallCountByAgent: [String: Int]
    public let toolCallCountByAgent: [String: Int]
    public let missingAgentTraceIdentityCountByAgent: [String: Int]
    public let missingToolTraceIdentityCount: Int
    public let unpairedToolCallCount: Int
    public let callerIdentityMismatchCount: Int
    public let contextWindowFailureCount: Int

    public init(
        requiredAgents: [String] = [],
        missingRequiredAgents: [String] = [],
        agentInvocationCounts: [String: Int] = [:],
        agentStatusCounts: [String: [String: Int]] = [:],
        agentDurationSamplesMs: [String: [Double]] = [:],
        modelCallCountByAgent: [String: Int] = [:],
        toolCallCountByAgent: [String: Int] = [:],
        missingAgentTraceIdentityCountByAgent: [String: Int] = [:],
        missingToolTraceIdentityCount: Int = 0,
        unpairedToolCallCount: Int = 0,
        callerIdentityMismatchCount: Int = 0,
        contextWindowFailureCount: Int = 0
    ) {
        self.requiredAgents = requiredAgents
        self.missingRequiredAgents = missingRequiredAgents
        self.agentInvocationCounts = agentInvocationCounts
        self.agentStatusCounts = agentStatusCounts
        self.agentDurationSamplesMs = agentDurationSamplesMs
        self.modelCallCountByAgent = modelCallCountByAgent
        self.toolCallCountByAgent = toolCallCountByAgent
        self.missingAgentTraceIdentityCountByAgent = missingAgentTraceIdentityCountByAgent
        self.missingToolTraceIdentityCount = missingToolTraceIdentityCount
        self.unpairedToolCallCount = unpairedToolCallCount
        self.callerIdentityMismatchCount = callerIdentityMismatchCount
        self.contextWindowFailureCount = contextWindowFailureCount
    }
}

public struct EvaluationSummaryMetrics: Sendable, Codable, Hashable {
    public let totalCaseCount: Int
    public let passedCaseCount: Int
    public let skippedCaseCount: Int
    public let failedCaseCount: Int
    public let passRate: Double
    public let passRateBySuite: [String: Double]
    public let passRateByFixture: [String: Double]
    public let passRateByTag: [String: Double]
    public let exactMatchAccuracy: Double
    public let partialMatchAccuracy: Double
    public let selectedDeviceExactMatchAccuracy: Double
    public let targetDeviceExactMatchAccuracy: Double
    public let capabilityExactMatchAccuracy: Double
    public let commandExactMatchAccuracy: Double
    public let candidateRecallAt1: Double
    public let candidateRecallAt3: Double
    public let candidateRecallAt5: Double
    public let draftExactFieldAccuracy: Double
    public let automationActionCountAccuracy: Double
    public let automationConditionCountAccuracy: Double
    public let smartThingsCompilationPassRate: Double
    public let clarificationRate: Double
    public let unsupportedRate: Double
    public let confirmationRate: Double
    public let contextWindowFailureRate: Double
    public let modelCallCount: Int
    public let averageModelCallsPerCase: Double
    public let toolCallCount: Int
    public let averageToolCallsPerCase: Double
    public let agentTraceIdentityPassRate: Double
    public let toolTraceIdentityPassRate: Double
    public let unpairedToolCallCount: Int
    public let callerIdentityMismatchCount: Int
    public let averageLatencyMsBySuite: [String: Double]
    public let topFailingAgents: [String]
    public let topFailingFixtureIDs: [String]
    public let topFailingTags: [String]
    public let topFailingCaseIDs: [String]

    public static func make(from results: [EvaluationCaseResult]) -> EvaluationSummaryMetrics {
        let total = results.count
        let passed = results.filter { $0.passed && !$0.skipped }.count
        let skipped = results.filter(\.skipped).count
        let failed = total - passed - skipped
        let grouped = Dictionary(grouping: results, by: \.suite)
        let passRateBySuite = grouped.mapValues { suiteResults in
            let suiteSkipped = suiteResults.filter(\.skipped).count
            let suitePassed = suiteResults.filter { $0.passed && !$0.skipped }.count
            return ratio(suitePassed, suiteResults.count - suiteSkipped)
        }
        let passRateByFixture = Dictionary(grouping: results.compactMap { result -> (String, EvaluationCaseResult)? in
            guard let fixtureID = result.fixtureID else { return nil }
            return (fixtureID, result)
        }, by: \.0).mapValues { entries in
            let fixtureResults = entries.map(\.1)
            return passRate(for: fixtureResults)
        }
        let tagEntries = results.flatMap { result in result.tags.map { ($0, result) } }
        let passRateByTag = Dictionary(grouping: tagEntries, by: \.0).mapValues { entries in
            passRate(for: entries.map(\.1))
        }
        let averageLatencyBySuite = grouped.mapValues { suiteResults in
            suiteResults.map(\.durationMs).reduce(0, +) / Double(max(suiteResults.count, 1))
        }
        let modelCalls = results.map(\.modelCallCount).reduce(0, +)
        let toolCalls = results.map(\.toolCallCount).reduce(0, +)
        let contextWindowFailures = results.reduce(0) { total, result in
            total +
                (result.observability?.contextWindowFailureCount ?? 0) +
                (result.metrics?.modelCalls.contextWindowFailuresByAgent.values.reduce(0, +) ?? 0)
        }
        let nonSkipped = results.filter { !$0.skipped }
        let expectedDeviceResults = nonSkipped.filter { !$0.expectedDeviceIDs.isEmpty }
        let expectedCapabilityResults = nonSkipped.filter { $0.expectedCapability != nil }
        let expectedCommandResults = nonSkipped.filter { $0.expectedCommand != nil }
        let expectedActionResults = nonSkipped.filter { $0.expectedActionCount != nil }
        let expectedConditionResults = nonSkipped.filter { $0.expectedConditionCount != nil }
        let smartThingsResults = nonSkipped.filter { $0.suite == "smartthings-compilation" || $0.tags.contains("automation") }
        let missingAgentTraceIDs = results.reduce(0) { total, result in
            total + (result.observability?.missingAgentTraceIdentityCountByAgent.values.reduce(0, +) ?? 0)
        }
        let agentInvocationCount = results.reduce(0) { total, result in
            total + (result.observability?.agentInvocationCounts.values.reduce(0, +) ?? 0)
        }
        let missingToolTraceIDs = results.reduce(0) { total, result in
            total + (result.observability?.missingToolTraceIdentityCount ?? 0)
        }
        let unpairedToolCalls = results.reduce(0) { total, result in
            total + (result.observability?.unpairedToolCallCount ?? 0)
        }
        let callerIdentityMismatches = results.reduce(0) { total, result in
            total + (result.observability?.callerIdentityMismatchCount ?? 0)
        }
        let failingResults = results.filter { !$0.passed && !$0.skipped }
        return EvaluationSummaryMetrics(
            totalCaseCount: total,
            passedCaseCount: passed,
            skippedCaseCount: skipped,
            failedCaseCount: failed,
            passRate: ratio(passed, total - skipped),
            passRateBySuite: passRateBySuite,
            passRateByFixture: passRateByFixture,
            passRateByTag: passRateByTag,
            exactMatchAccuracy: ratio(passed, total - skipped),
            partialMatchAccuracy: ratio(results.filter { $0.assertionFailures.count <= 1 && !$0.skipped }.count, total - skipped),
            selectedDeviceExactMatchAccuracy: ratio(expectedDeviceResults.filter { expectedSelectedDevicesMatch($0) }.count, expectedDeviceResults.count),
            targetDeviceExactMatchAccuracy: ratio(expectedDeviceResults.filter { expectedTargetDeviceMatches($0) }.count, expectedDeviceResults.count),
            capabilityExactMatchAccuracy: ratio(expectedCapabilityResults.filter { $0.actualCapability == $0.expectedCapability }.count, expectedCapabilityResults.count),
            commandExactMatchAccuracy: ratio(expectedCommandResults.filter { $0.actualCommand == $0.expectedCommand }.count, expectedCommandResults.count),
            candidateRecallAt1: candidateRecall(results: expectedDeviceResults, k: 1),
            candidateRecallAt3: candidateRecall(results: expectedDeviceResults, k: 3),
            candidateRecallAt5: candidateRecall(results: expectedDeviceResults, k: 5),
            draftExactFieldAccuracy: ratio(expectedCommandResults.filter { draftFieldsMatch($0) }.count, expectedCommandResults.count),
            automationActionCountAccuracy: ratio(expectedActionResults.filter { $0.actualActionCount == $0.expectedActionCount }.count, expectedActionResults.count),
            automationConditionCountAccuracy: ratio(expectedConditionResults.filter { $0.actualConditionCount == $0.expectedConditionCount }.count, expectedConditionResults.count),
            smartThingsCompilationPassRate: passRate(for: smartThingsResults),
            clarificationRate: ratio(results.filter { $0.status == .clarification }.count, total),
            unsupportedRate: ratio(results.filter { $0.status == .unsupported }.count, total),
            confirmationRate: ratio(results.filter { $0.status == .confirmation }.count, total),
            contextWindowFailureRate: ratio(contextWindowFailures, max(modelCalls, 1)),
            modelCallCount: modelCalls,
            averageModelCallsPerCase: Double(modelCalls) / Double(max(total - skipped, 1)),
            toolCallCount: toolCalls,
            averageToolCallsPerCase: Double(toolCalls) / Double(max(total - skipped, 1)),
            agentTraceIdentityPassRate: ratio(max(agentInvocationCount - missingAgentTraceIDs, 0), agentInvocationCount),
            toolTraceIdentityPassRate: toolCalls == 0 ? 1 : ratio(max(toolCalls - missingToolTraceIDs - unpairedToolCalls, 0), toolCalls),
            unpairedToolCallCount: unpairedToolCalls,
            callerIdentityMismatchCount: callerIdentityMismatches,
            averageLatencyMsBySuite: averageLatencyBySuite,
            topFailingAgents: topKeys(failingResults.flatMap { $0.observability?.missingRequiredAgents ?? [] }),
            topFailingFixtureIDs: topKeys(failingResults.compactMap(\.fixtureID)),
            topFailingTags: topKeys(failingResults.flatMap(\.tags)),
            topFailingCaseIDs: failingResults.prefix(10).map(\.id)
        )
    }

    private static func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }

    private static func passRate(for results: [EvaluationCaseResult]) -> Double {
        let skipped = results.filter(\.skipped).count
        let passed = results.filter { $0.passed && !$0.skipped }.count
        return ratio(passed, results.count - skipped)
    }

    private static func expectedSelectedDevicesMatch(_ result: EvaluationCaseResult) -> Bool {
        Set(result.expectedDeviceIDs) == Set(result.selectedDeviceIDs)
    }

    private static func expectedTargetDeviceMatches(_ result: EvaluationCaseResult) -> Bool {
        guard let expected = result.expectedDeviceIDs.first else { return false }
        return result.actualTargetDeviceID == expected || result.selectedDeviceIDs.first == expected
    }

    private static func draftFieldsMatch(_ result: EvaluationCaseResult) -> Bool {
        expectedTargetDeviceMatches(result) &&
            result.actualCapability == result.expectedCapability &&
            result.actualCommand == result.expectedCommand
    }

    private static func candidateRecall(results: [EvaluationCaseResult], k: Int) -> Double {
        ratio(
            results.filter { result in
                let actual = Set(result.selectedDeviceIDs.prefix(k))
                return result.expectedDeviceIDs.contains { actual.contains($0) }
            }.count,
            results.count
        )
    }

    private static func topKeys(_ values: [String], limit: Int = 10) -> [String] {
        var counts: [String: Int] = [:]
        for value in values {
            counts[value, default: 0] += 1
        }
        let sorted = counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }
        return sorted.prefix(limit).map { $0.key }
    }
}

public struct EvaluationSuiteResult: Sendable, Codable, Hashable {
    public let mode: EvaluationMode
    public let generatedAt: Date
    public let results: [EvaluationCaseResult]
    public let summary: EvaluationSummaryMetrics

    public init(mode: EvaluationMode, results: [EvaluationCaseResult]) {
        self.mode = mode
        self.generatedAt = Date()
        self.results = results
        self.summary = EvaluationSummaryMetrics.make(from: results)
    }
}

public struct EvaluationAgentMetricsReport: Sendable, Codable, Hashable {
    public let generatedAt: Date
    public let agents: [EvaluationAgentMetrics]

    public init(generatedAt: Date = Date(), agents: [EvaluationAgentMetrics]) {
        self.generatedAt = generatedAt
        self.agents = agents
    }

    public static func make(from results: [EvaluationCaseResult]) -> EvaluationAgentMetricsReport {
        var accumulator: [String: AgentAccumulator] = [:]
        for result in results {
            guard let observability = result.observability else { continue }
            let agentIDs = Set(
                observability.agentInvocationCounts.keys +
                    observability.requiredAgents +
                    observability.missingRequiredAgents
            )
            for agentID in agentIDs {
                var current = accumulator[agentID] ?? AgentAccumulator(agentID: agentID)
                current.caseCount += 1
                current.invocationCount += observability.agentInvocationCounts[agentID] ?? 0
                current.requiredCount += observability.requiredAgents.contains(agentID) ? 1 : 0
                current.missingCount += observability.missingRequiredAgents.contains(agentID) ? 1 : 0
                current.completedCount += observability.agentStatusCounts[agentID]?["completed"] ?? 0
                current.failedCount += observability.agentStatusCounts[agentID]?["failed"] ?? 0
                current.skippedCount += observability.agentStatusCounts[agentID]?["skipped"] ?? 0
                current.durationSamplesMs += observability.agentDurationSamplesMs[agentID] ?? []
                current.modelCallCount += observability.modelCallCountByAgent[agentID] ?? 0
                current.toolCallCount += observability.toolCallCountByAgent[agentID] ?? 0
                current.missingTraceIdentityCount += observability.missingAgentTraceIdentityCountByAgent[agentID] ?? 0
                current.contextWindowFailureCount += result.metrics?.modelCalls.contextWindowFailuresByAgent[agentID] ?? 0
                current.contextWindowFailureCount += agentID == "unknown" ? observability.contextWindowFailureCount : 0
                if observability.agentInvocationCounts[agentID, default: 0] > 0 {
                    current.invokedCaseCount += 1
                    if result.passed {
                        current.outputAccurateCaseCount += 1
                    }
                    if result.expectedDeviceIDs.isEmpty || Set(result.expectedDeviceIDs).isSubset(of: Set(result.selectedDeviceIDs)) {
                        current.selectedDeviceAccurateCaseCount += 1
                    }
                    if result.expectedCapability == nil || result.expectedCapability == result.actualCapability {
                        current.capabilityAccurateCaseCount += 1
                    }
                    if result.expectedCommand == nil || result.expectedCommand == result.actualCommand {
                        current.commandAccurateCaseCount += 1
                    }
                }
                accumulator[agentID] = current
            }
        }
        var agents = accumulator.values.map { $0.metrics }
        agents.sort { lhs, rhs in
            lhs.invocationCount == rhs.invocationCount ? lhs.agentID < rhs.agentID : lhs.invocationCount > rhs.invocationCount
        }
        return EvaluationAgentMetricsReport(agents: agents)
    }

    private struct AgentAccumulator {
        let agentID: String
        var caseCount = 0
        var invokedCaseCount = 0
        var invocationCount = 0
        var requiredCount = 0
        var missingCount = 0
        var completedCount = 0
        var failedCount = 0
        var skippedCount = 0
        var durationSamplesMs: [Double] = []
        var outputAccurateCaseCount = 0
        var selectedDeviceAccurateCaseCount = 0
        var capabilityAccurateCaseCount = 0
        var commandAccurateCaseCount = 0
        var modelCallCount = 0
        var toolCallCount = 0
        var missingTraceIdentityCount = 0
        var callerIdentityMismatchCount = 0
        var fallbackCount = 0
        var contextWindowFailureCount = 0

        var metrics: EvaluationAgentMetrics {
            EvaluationAgentMetrics(
                agentID: agentID,
                invocationCount: invocationCount,
                requiredCount: requiredCount,
                missingCount: missingCount,
                completedCount: completedCount,
                failedCount: failedCount,
                skippedCount: skippedCount,
                averageDurationMs: durationSamplesMs.isEmpty ? nil : durationSamplesMs.reduce(0, +) / Double(durationSamplesMs.count),
                outputAccuracy: ratio(outputAccurateCaseCount, invokedCaseCount),
                selectedDeviceAccuracy: ratio(selectedDeviceAccurateCaseCount, invokedCaseCount),
                capabilityAccuracy: ratio(capabilityAccurateCaseCount, invokedCaseCount),
                commandAccuracy: ratio(commandAccurateCaseCount, invokedCaseCount),
                modelCallCount: modelCallCount,
                toolCallCount: toolCallCount,
                missingTraceIdentityCount: missingTraceIdentityCount,
                callerIdentityMismatchCount: callerIdentityMismatchCount,
                fallbackCount: fallbackCount,
                contextWindowFailureCount: contextWindowFailureCount
            )
        }

        private func ratio(_ numerator: Int, _ denominator: Int) -> Double {
            guard denominator > 0 else { return 0 }
            return Double(numerator) / Double(denominator)
        }
    }
}

public struct EvaluationAgentMetrics: Sendable, Codable, Hashable {
    public let agentID: String
    public let invocationCount: Int
    public let requiredCount: Int
    public let missingCount: Int
    public let completedCount: Int
    public let failedCount: Int
    public let skippedCount: Int
    public let averageDurationMs: Double?
    public let outputAccuracy: Double
    public let selectedDeviceAccuracy: Double
    public let capabilityAccuracy: Double
    public let commandAccuracy: Double
    public let modelCallCount: Int
    public let toolCallCount: Int
    public let missingTraceIdentityCount: Int
    public let callerIdentityMismatchCount: Int
    public let fallbackCount: Int
    public let contextWindowFailureCount: Int

    public init(
        agentID: String,
        invocationCount: Int,
        requiredCount: Int,
        missingCount: Int,
        completedCount: Int,
        failedCount: Int,
        skippedCount: Int,
        averageDurationMs: Double?,
        outputAccuracy: Double,
        selectedDeviceAccuracy: Double,
        capabilityAccuracy: Double,
        commandAccuracy: Double,
        modelCallCount: Int,
        toolCallCount: Int,
        missingTraceIdentityCount: Int,
        callerIdentityMismatchCount: Int,
        fallbackCount: Int,
        contextWindowFailureCount: Int
    ) {
        self.agentID = agentID
        self.invocationCount = invocationCount
        self.requiredCount = requiredCount
        self.missingCount = missingCount
        self.completedCount = completedCount
        self.failedCount = failedCount
        self.skippedCount = skippedCount
        self.averageDurationMs = averageDurationMs
        self.outputAccuracy = outputAccuracy
        self.selectedDeviceAccuracy = selectedDeviceAccuracy
        self.capabilityAccuracy = capabilityAccuracy
        self.commandAccuracy = commandAccuracy
        self.modelCallCount = modelCallCount
        self.toolCallCount = toolCallCount
        self.missingTraceIdentityCount = missingTraceIdentityCount
        self.callerIdentityMismatchCount = callerIdentityMismatchCount
        self.fallbackCount = fallbackCount
        self.contextWindowFailureCount = contextWindowFailureCount
    }
}
