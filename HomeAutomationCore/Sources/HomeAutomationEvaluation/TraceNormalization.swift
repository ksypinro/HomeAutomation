import Foundation
import HomeAutomationCore

public struct TraceNormalizer: Sendable {
    public init() {}

    public func normalize(_ events: [ObservabilityEvent], caseID: String) -> NormalizedTrace {
        var agentSessionAliases = AliasTable(prefix: "agent-session")
        var agentInvocationAliases = AliasTable(prefix: "agent-invocation")
        var toolSessionAliases = AliasTable(prefix: "tool-session")
        var toolCallAliases = AliasTable(prefix: "tool-call")
        var spans: [NormalizedTraceSpan] = []
        var selectedDeviceIDs: [String] = []
        var targetDeviceID: String?
        var capability: String?
        var command: String?
        var contextWindowFailureCount = 0
        var agentEvents: [String: [ObservabilityEvent]] = [:]
        var toolEventsByCallAlias: [String: [ObservabilityEvent]] = [:]
        var uniqueModelCallIDs: Set<String> = []
        var uniqueToolCallAliases: Set<String> = []

        for event in events {
            let payload = event.stringPayload
            appendUnique(&selectedDeviceIDs, values: candidateIDs(from: payload))
            if shouldReadResolvedFields(from: event, payload: payload) {
                if let value = firstNonEmpty(payload["targetDeviceID"], payload["targetDeviceId"]) {
                    targetDeviceID = value
                }
                if let value = firstNonEmpty(payload["capability"]) {
                    capability = value
                }
                if let value = firstNonEmpty(payload["command"]), isCanonicalCommandValue(value) {
                    command = value
                }
            }
            if let output = payload["output"], shouldReadResolvedTextPayload(from: event) {
                targetDeviceID = targetDeviceID ?? optionalStringField("targetDeviceID", in: output)
                capability = capability ?? optionalStringField("capability", in: output)
                if let outputCommand = optionalStringField("command", in: output),
                   isCanonicalCommandValue(outputCommand) {
                    command = command ?? outputCommand
                }
            }
            if isContextWindowFailure(event: event, payload: payload) {
                contextWindowFailureCount += 1
            }
            if event.spanKind == .modelCall {
                uniqueModelCallIDs.insert(payload["modelCallID"] ?? "\(event.eventType)-\(event.spanID ?? UUID().uuidString)")
            }

            let agentSessionAlias = event.agentSessionID.map {
                agentSessionAliases.alias(for: $0, scope: event.agentID)
            }
            let invocationAlias = event.agentInvocationID.map {
                agentInvocationAliases.alias(for: $0, scope: event.agentID)
            }
            let toolSessionAlias = event.toolSessionID.map {
                toolSessionAliases.alias(for: $0, scope: event.toolID)
            }
            let toolCallAlias = event.toolCallID.map {
                toolCallAliases.alias(for: $0, scope: event.toolID)
            }
            if let toolCallAlias {
                uniqueToolCallAliases.insert(toolCallAlias)
                toolEventsByCallAlias[toolCallAlias, default: []].append(event)
            }
            if let agentID = event.agentID, event.eventType.hasPrefix("agent.") {
                agentEvents[agentID, default: []].append(event)
            }

            spans.append(NormalizedTraceSpan(
                eventType: event.eventType,
                spanKind: event.spanKind.rawValue,
                graphID: event.graphID,
                stage: event.stage,
                graphNodeID: event.graphNodeID,
                agentID: event.agentID,
                agentInvocationGroup: invocationAlias,
                agentSessionAlias: agentSessionAlias,
                agentRunID: event.agentRunID,
                componentKind: event.componentKind,
                componentID: event.componentID,
                actionID: event.actionID,
                conditionID: event.conditionID,
                toolID: event.toolID,
                toolSessionAlias: toolSessionAlias,
                toolCallAlias: toolCallAlias,
                callerAgentID: event.toolID == nil ? nil : event.agentID,
                callerAgentSessionAlias: event.toolID == nil ? nil : agentSessionAlias,
                callerAgentRunID: event.toolID == nil ? nil : event.agentRunID,
                status: event.status?.rawValue,
                payloadMarkers: stablePayloadMarkers(from: payload)
            ))
        }

        return NormalizedTrace(
            caseID: caseID,
            spans: spans,
            selectedDeviceIDs: selectedDeviceIDs,
            targetDeviceID: targetDeviceID,
            capability: capability,
            command: command,
            modelCallCount: uniqueModelCallIDs.count,
            toolCallCount: uniqueToolCallAliases.count,
            contextWindowFailureCount: contextWindowFailureCount,
            agentIdentityChecks: agentIdentityChecks(from: agentEvents, aliases: &agentSessionAliases),
            toolIdentityChecks: toolIdentityChecks(from: toolEventsByCallAlias)
        )
    }

    private func agentIdentityChecks(
        from eventsByAgent: [String: [ObservabilityEvent]],
        aliases: inout AliasTable
    ) -> [String: NormalizedAgentIdentityCheck] {
        var checks: [String: NormalizedAgentIdentityCheck] = [:]
        for agentID in eventsByAgent.keys.sorted() {
            let events = eventsByAgent[agentID] ?? []
            let inputEvents = events.filter { $0.eventType == "agent.input" }
            let outputEvents = events.filter { $0.eventType == "agent.output" }
            let runIDs = inputEvents.compactMap(\.agentRunID)
            let sessionAlias = events.compactMap { event in
                event.agentSessionID.map { aliases.alias(for: $0, scope: agentID) }
            }.first ?? ""
            checks[agentID] = NormalizedAgentIdentityCheck(
                agentID: agentID,
                agentSessionAlias: sessionAlias,
                observedRunIDs: runIDs,
                inputOutputPairs: min(inputEvents.count, outputEvents.count),
                missingInputTraceIDCount: inputEvents.filter { $0.agentSessionID == nil || $0.agentRunID == nil }.count,
                missingOutputTraceIDCount: outputEvents.filter { $0.agentSessionID == nil || $0.agentRunID == nil }.count,
                nonMonotonicRunIDCount: nonMonotonicCount(runIDs)
            )
        }
        return checks
    }

    private func toolIdentityChecks(
        from eventsByCallAlias: [String: [ObservabilityEvent]]
    ) -> [String: NormalizedToolIdentityCheck] {
        var checks: [String: NormalizedToolIdentityCheck] = [:]
        for callAlias in eventsByCallAlias.keys.sorted() {
            let events = eventsByCallAlias[callAlias] ?? []
            let input = events.first { $0.eventType == "tool.input" }
            let output = events.first { $0.eventType == "tool.output" }
            let reference = input ?? output
            let callerPairs = Set(events.map { event in
                "\(event.agentID ?? "")|\(event.agentSessionID ?? "")|\(event.agentRunID.map(String.init) ?? "")"
            })
            let missingCaller = events.contains {
                $0.agentID == nil || $0.agentSessionID == nil || $0.agentRunID == nil
            }
            checks[callAlias] = NormalizedToolIdentityCheck(
                toolID: reference?.toolID ?? "",
                toolSessionAlias: reference?.toolSessionID.map { _ in "tool-session:\(reference?.toolID ?? "unknown"):present" },
                toolCallAlias: callAlias,
                callerAgentID: reference?.agentID,
                callerAgentSessionAlias: reference?.agentSessionID.map { _ in "agent-session:\(reference?.agentID ?? "unknown"):present" },
                callerAgentRunID: reference?.agentRunID,
                hasInputEvent: input != nil,
                hasOutputEvent: output != nil,
                missingToolSessionID: events.contains { $0.toolSessionID == nil },
                missingCallerAgentTraceID: missingCaller,
                callerIdentityMismatch: callerPairs.count > 1
            )
        }
        return checks
    }

    private func nonMonotonicCount(_ runIDs: [Int]) -> Int {
        guard runIDs.count > 1 else { return 0 }
        var count = 0
        for pair in zip(runIDs, runIDs.dropFirst()) where pair.1 <= pair.0 {
            count += 1
        }
        return count
    }

    private func candidateIDs(from payload: [String: String]) -> [String] {
        [
            "selectedCandidateIDs",
            "finalCandidateIDs",
            "selectedDeviceIDs",
            "targetDeviceID"
        ].flatMap { key in
            splitIDs(payload[key])
        }
    }

    private func shouldReadResolvedFields(from event: ObservabilityEvent, payload: [String: String]) -> Bool {
        if event.agentID == "draftGeneration" || event.agentID == "capabilityResolution" || event.agentID == "ruleFallback" {
            return true
        }
        if payload["targetDeviceID"] != nil || payload["targetDeviceId"] != nil {
            return true
        }
        if payload["capability"] != nil, payload["command"] != nil {
            return true
        }
        return false
    }

    private func shouldReadResolvedTextPayload(from event: ObservabilityEvent) -> Bool {
        event.agentID == "draftGeneration" ||
            event.agentID == "capabilityResolution" ||
            event.agentID == "ruleFallback" ||
            event.eventType == "run.metrics"
    }

    private func isCanonicalCommandValue(_ value: String) -> Bool {
        !value.isEmpty &&
            !value.contains(where: \.isWhitespace) &&
            value.count <= 64
    }

    private func isContextWindowFailure(event: ObservabilityEvent, payload: [String: String]) -> Bool {
        if event.eventType.localizedCaseInsensitiveContains("contextWindow") {
            return true
        }
        return [
            "failureKind",
            "errorKind",
            "errorCode",
            "fallbackReason"
        ].contains { key in
            payload[key]?.localizedCaseInsensitiveContains("contextWindow") == true ||
                payload[key]?.localizedCaseInsensitiveContains("context window") == true
        }
    }

    private func splitIDs(_ value: String?) -> [String] {
        guard let value, !value.isEmpty else { return [] }
        return value
            .split { character in character == "," || character == ";" || character == "[" || character == "]" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\""))) }
            .filter { !$0.isEmpty && $0 != "nil" }
    }

    private func optionalStringField(_ field: String, in text: String) -> String? {
        let pattern = "\(field): Optional(\""
        guard let start = text.range(of: pattern) else { return nil }
        let remainder = text[start.upperBound...]
        guard let end = remainder.range(of: "\")") else { return nil }
        return String(remainder[..<end.lowerBound])
    }

    private func stablePayloadMarkers(from payload: [String: String]) -> [String: String] {
        let allowedKeys = [
            "agentID",
            "toolID",
            "componentID",
            "componentKind",
            "selectedCandidateIDs",
            "finalCandidateIDs",
            "targetDeviceID",
            "capability",
            "command",
            "failureKind",
            "modelAvailability",
            "policyMode"
        ]
        return payload.filter { allowedKeys.contains($0.key) }
    }

    private func appendUnique(_ values: inout [String], values newValues: [String]) {
        for value in newValues where !values.contains(value) {
            values.append(value)
        }
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

private struct AliasTable {
    let prefix: String
    private var aliases: [String: String] = [:]
    private var countsByScope: [String: Int] = [:]

    init(prefix: String) {
        self.prefix = prefix
    }

    mutating func alias(for rawValue: String, scope: String?) -> String {
        if let existing = aliases[rawValue] {
            return existing
        }
        let scope = scope?.isEmpty == false ? scope! : "unknown"
        let next = (countsByScope[scope] ?? 0) + 1
        countsByScope[scope] = next
        let alias = "\(prefix):\(scope):\(next)"
        aliases[rawValue] = alias
        return alias
    }
}
