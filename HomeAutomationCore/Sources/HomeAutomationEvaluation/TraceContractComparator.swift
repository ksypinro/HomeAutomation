import Foundation

public struct TraceContractComparator: Sendable {
    public init() {}

    public func compare(_ contract: ExpectedTraceContract, actual trace: NormalizedTrace) -> TraceDiff {
        var missingRequiredAgents: [String] = []
        var missingRequiredGraphs: [String] = []
        var missingRequiredComponents: [String] = []
        var wrongAgentStatuses: [String] = []
        var unexpectedFailedAgents: [String] = []
        var wrongSelectedDeviceIDs: [String] = []
        var wrongCapability: String?
        var wrongCommand: String?
        var missingAgentTraceIDs: [String] = []
        var missingToolTraceIDs: [String] = []
        var unpairedToolCalls: [String] = []
        var callerIdentityMismatches: [String] = []
        var nonMonotonicAgentRunIDs: [String] = []
        var budgetFailures: [String] = []

        let graphIDs = Set(trace.spans.compactMap(\.graphID))
        missingRequiredGraphs = contract.requiredGraphs.filter { !graphIDs.contains($0) }
        if !contract.graphPathAlternatives.isEmpty {
            let alternativeMisses = contract.graphPathAlternatives.map { path in
                path.filter { !graphIDs.contains($0) }
            }
            if !alternativeMisses.contains(where: \.isEmpty) {
                missingRequiredGraphs += alternativeMisses.min(by: { $0.count < $1.count }) ?? []
            }
        }

        var agentContractsToValidate = contract.requiredAgents
        if !contract.agentPathAlternatives.isEmpty {
            let alternatives = contract.agentPathAlternatives.map { path in
                (path: path, missing: missingAgents(in: path, actual: trace))
            }
            if let matchingPath = alternatives.first(where: { $0.missing.isEmpty })?.path {
                agentContractsToValidate += matchingPath
            } else if let closest = alternatives.min(by: { $0.missing.count < $1.missing.count }) {
                missingRequiredAgents += closest.missing
            }
        }

        for agent in agentContractsToValidate {
            let spans = trace.spans.filter { $0.agentID == agent.agentID }
            let count = invocationCount(for: spans)
            if agent.required && count < agent.minimumCount {
                missingRequiredAgents.append(agent.agentID)
                continue
            }
            guard count > 0 else { continue }
            if let maximum = agent.maximumCount, count > maximum {
                budgetFailures.append("Agent \(agent.agentID) count \(count) exceeded \(maximum)")
            }
            if let expectedStatus = agent.expectedStatus,
               !spans.contains(where: { $0.status == expectedStatus }) {
                wrongAgentStatuses.append("\(agent.agentID):\(expectedStatus)")
            }
            if agent.requireInputOutputTraceIDs,
               let check = trace.agentIdentityChecks[agent.agentID],
               check.missingInputTraceIDCount + check.missingOutputTraceIDCount > 0 {
                missingAgentTraceIDs.append(agent.agentID)
            } else if agent.required && agent.requireInputOutputTraceIDs && trace.agentIdentityChecks[agent.agentID] == nil {
                missingAgentTraceIDs.append(agent.agentID)
            }
            if agent.requirePositiveRunID,
               let check = trace.agentIdentityChecks[agent.agentID],
               check.observedRunIDs.contains(where: { $0 <= 0 }) {
                missingAgentTraceIDs.append(agent.agentID)
            }
            if agent.requireStableSessionWithinCase,
               let check = trace.agentIdentityChecks[agent.agentID],
               check.nonMonotonicRunIDCount > 0 {
                nonMonotonicAgentRunIDs.append(agent.agentID)
            }
        }

        unexpectedFailedAgents = Set(trace.spans.compactMap { span -> String? in
            guard span.status == "failed", let agentID = span.agentID else { return nil }
            return contract.allowedFailedAgents.contains(agentID) ? nil : agentID
        }).sorted()

        for component in contract.requiredComponents {
            let found = trace.spans.contains {
                ($0.componentKind == component.componentKind || $0.eventType.contains(component.componentKind)) &&
                    ($0.componentID == component.componentID || $0.stage?.contains(component.componentID) == true)
            }
            if !found {
                missingRequiredComponents.append("\(component.componentKind):\(component.componentID)")
            }
        }

        if !contract.expectedSelectedDeviceIDs.isEmpty {
            let actualIDs = Set(trace.selectedDeviceIDs + [trace.targetDeviceID].compactMap { $0 })
            wrongSelectedDeviceIDs = contract.expectedSelectedDeviceIDs.filter { !actualIDs.contains($0) }
        }
        if let expectedCapability = contract.expectedCapability, trace.capability != expectedCapability {
            wrongCapability = "expected \(expectedCapability), got \(trace.capability ?? "nil")"
        }
        if let expectedCommand = contract.expectedCommand, trace.command != expectedCommand {
            wrongCommand = "expected \(expectedCommand), got \(trace.command ?? "nil")"
        }

        for tool in contract.requiredTools {
            let checks = trace.toolIdentityChecks.values.filter { $0.toolID == tool.toolID }
            if tool.required && checks.count < tool.minimumCount {
                missingToolTraceIDs.append(tool.toolID)
                continue
            }
            if let maximum = tool.maximumCount, checks.count > maximum {
                budgetFailures.append("Tool \(tool.toolID) count \(checks.count) exceeded \(maximum)")
            }
            for check in checks {
                if tool.requireInputOutputPair && (!check.hasInputEvent || !check.hasOutputEvent) {
                    unpairedToolCalls.append(check.toolCallAlias)
                }
                if tool.requireToolSessionID && check.missingToolSessionID {
                    missingToolTraceIDs.append(check.toolCallAlias)
                }
                if tool.requireCallerAgentTraceIDs && check.missingCallerAgentTraceID {
                    missingToolTraceIDs.append(check.toolCallAlias)
                }
                if !tool.expectedCallerAgentIDs.isEmpty,
                   let caller = check.callerAgentID,
                   !tool.expectedCallerAgentIDs.contains(caller) {
                    callerIdentityMismatches.append(check.toolCallAlias)
                }
                if check.callerIdentityMismatch {
                    callerIdentityMismatches.append(check.toolCallAlias)
                }
            }
        }

        if contract.requireToolTraceIdentity {
            for check in trace.toolIdentityChecks.values where check.missingToolSessionID {
                missingToolTraceIDs.append(check.toolCallAlias)
            }
        }
        if contract.requireToolCallerIdentityPropagation {
            for check in trace.toolIdentityChecks.values where check.missingCallerAgentTraceID || check.callerIdentityMismatch {
                callerIdentityMismatches.append(check.toolCallAlias)
            }
        }
        if let maxModelCallCount = contract.maxModelCallCount, trace.modelCallCount > maxModelCallCount {
            budgetFailures.append("Model calls \(trace.modelCallCount) exceeded \(maxModelCallCount)")
        }
        if let maxToolCallCount = contract.maxToolCallCount, trace.toolCallCount > maxToolCallCount {
            budgetFailures.append("Tool calls \(trace.toolCallCount) exceeded \(maxToolCallCount)")
        }
        if !contract.allowContextWindowFailures, trace.contextWindowFailureCount > 0 {
            budgetFailures.append("Context-window failures \(trace.contextWindowFailureCount) exceeded 0")
        }

        let passed = [
            missingRequiredAgents,
            missingRequiredGraphs,
            missingRequiredComponents,
            wrongAgentStatuses,
            unexpectedFailedAgents,
            wrongSelectedDeviceIDs,
            missingAgentTraceIDs,
            missingToolTraceIDs,
            unpairedToolCalls,
            callerIdentityMismatches,
            nonMonotonicAgentRunIDs,
            budgetFailures
        ].allSatisfy(\.isEmpty) && wrongCapability == nil && wrongCommand == nil

        return TraceDiff(
            caseID: contract.caseID,
            passed: passed,
            missingRequiredAgents: missingRequiredAgents.sorted(),
            missingRequiredGraphs: missingRequiredGraphs.sorted(),
            missingRequiredComponents: missingRequiredComponents.sorted(),
            wrongAgentStatuses: wrongAgentStatuses.sorted(),
            unexpectedFailedAgents: unexpectedFailedAgents.sorted(),
            wrongSelectedDeviceIDs: wrongSelectedDeviceIDs.sorted(),
            wrongCapability: wrongCapability,
            wrongCommand: wrongCommand,
            missingAgentTraceIDs: Array(Set(missingAgentTraceIDs)).sorted(),
            missingToolTraceIDs: Array(Set(missingToolTraceIDs)).sorted(),
            unpairedToolCalls: Array(Set(unpairedToolCalls)).sorted(),
            callerIdentityMismatches: Array(Set(callerIdentityMismatches)).sorted(),
            nonMonotonicAgentRunIDs: Array(Set(nonMonotonicAgentRunIDs)).sorted(),
            budgetFailures: budgetFailures.sorted()
        )
    }

    private func missingAgents(in contracts: [ExpectedAgentContract], actual trace: NormalizedTrace) -> [String] {
        contracts.compactMap { agent in
            guard agent.required else { return nil }
            let count = invocationCount(for: trace.spans.filter { $0.agentID == agent.agentID })
            return count < agent.minimumCount ? agent.agentID : nil
        }
    }

    private func invocationCount(for spans: [NormalizedTraceSpan]) -> Int {
        max(Set(spans.compactMap(\.agentInvocationGroup)).count, spans.isEmpty ? 0 : 1)
    }
}
