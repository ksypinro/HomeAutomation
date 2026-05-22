import Foundation
import HomeAutomationAgents
import HomeAutomationCore

extension DefaultAgentRegistryFactory {
    internal static func candidateRetrievalInput<Context: NLUContextFacet & KnowledgeContextFacet>(
        from context: Context
    ) -> CandidateRetrievalInput {
        CandidateRetrievalInput(
            text: context.request.text,
            state: context.resolutionState ?? fallbackState(for: context.request.text),
            memoryHints: context.memoryHints
        )
    }

    internal static func candidateRankingInput<Context: NLUContextFacet & CandidateContextFacet & KnowledgeContextFacet>(
        from context: Context
    ) throws -> CandidateRankingInput {
        CandidateRankingInput(
            text: context.request.text,
            state: try state(from: context, agentID: .candidateRanking),
            candidates: context.retrievedCandidates.map(\.compactView),
            memoryHints: context.memoryHints
        )
    }

    internal static func candidateHydrationInput<Context: CandidateContextFacet>(
        from context: Context
    ) -> CandidateHydrationInput {
        CandidateHydrationInput(
            candidateIDs: context.aggregation?.finalCandidateIDs ?? context.selectedCandidateIDs
        )
    }

    internal static func capabilityResolutionInput<Context: CapabilityContextFacet>(
        from context: Context
    ) throws -> CapabilityResolutionInput {
        CapabilityResolutionInput(
            rawText: context.request.text,
            resolutionState: try state(from: context, agentID: .capabilityResolution),
            hydratedCandidates: context.hydratedCandidates,
            aggregation: context.aggregation ?? HomeCandidateAggregationResult(
                finalCandidateIDs: context.selectedCandidateIDs,
                needsClarification: false,
                confidence: 0
            ),
            knowledgeSnippets: context.knowledgeSnippets
        )
    }

    internal static func state<Context: NLUContextFacet>(from context: Context, agentID: AgentID) throws -> HomeResolutionState {
        guard let state = context.resolutionState else {
            throw AgentContextInputError(agentID: agentID, message: "Missing resolution state")
        }
        return state
    }

    internal static func finalInput(_ context: ResolutionContext) throws -> HomeFinalResolutionInput {
        HomeFinalResolutionInput(
            rawText: context.request.text,
            resolutionState: try state(from: context, agentID: .instructionComposer),
            hydratedCandidates: context.hydratedCandidates,
            aggregation: context.aggregation ?? HomeCandidateAggregationResult(
                finalCandidateIDs: context.selectedCandidateIDs,
                needsClarification: false,
                confidence: 0
            ),
            capabilityDecision: context.capabilityDecision
        )
    }

    internal static func fallbackState(for text: String) -> HomeResolutionState {
        AgentTextParser.deterministicState(for: text, confidence: 0.42, riskReason: "Orchestrator fallback state")
    }

    internal static func selectedDevice(from context: ResolutionContext) -> HomeCandidateRecord? {
        guard let id = context.draft?.targetDeviceID ?? context.aggregation?.finalCandidateIDs.first ?? context.selectedCandidateIDs.first else {
            return nil
        }
        return context.hydratedCandidates.first { $0.id == id } ??
            context.retrievedCandidates.first { $0.id == id }
    }

    internal static func memoryContributedTarget(deviceID: String, context: ResolutionContext) -> Bool {
        context.memoryHints.contains { $0.deviceID == deviceID }
    }

    internal static func deviceNames(from context: ResolutionContext) -> [String] {
        let names = (context.hydratedCandidates + context.retrievedCandidates).map(\.displayName)
        if !names.isEmpty {
            return names
        }

        let slots = context.slots ?? context.resolutionState?.slots
        let deviceTypes = context.deviceType?.deviceTypes ?? context.resolutionState?.deviceType.deviceTypes ?? []
        let rooms = slots?.rooms ?? []
        let inferred = rooms.flatMap { room in
            deviceTypes.map { "\(room) \(Self.displayName(forDeviceType: $0))" }
        } + deviceTypes.map(Self.displayName(forDeviceType:))
        return inferred.isEmpty ? ["device"] : stableUnique(inferred)
    }

    internal static func displayName(forDeviceType deviceType: String) -> String {
        deviceType
            .agentNormalizedHomeTokenString
            .split(separator: " ")
            .joined(separator: " ")
    }

    internal static func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let key = value.agentNormalizedHomeTokenString
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(value)
        }
        return result
    }

    internal static func capabilityHints(from context: ResolutionContext) -> [String] {
        var values = Set(context.hydratedCandidates.flatMap(\.capabilities) + context.retrievedCandidates.flatMap(\.capabilities))
        let families = context.intent?.topFamilies ?? context.resolutionState?.intent.topFamilies ?? []
        for family in families {
            switch family {
            case .createAutomation:
                break
            case .power:
                values.insert("switch")
            case .temperature:
                values.insert("thermostatCoolingSetpoint")
                values.insert("thermostatHeatingSetpoint")
                values.insert("thermostatMode")
            case .brightness:
                values.insert("switchLevel")
            case .lockUnlock:
                values.insert("lock")
            case .openClose:
                values.insert("garageDoorControl")
                values.insert("doorControl")
                values.insert("windowShade")
            case .routine:
                values.insert("routine")
            case .statusQuery:
                values.insert("temperatureMeasurement")
                values.insert("contactSensor")
                values.insert("battery")
            case .media:
                values.insert("mediaPlayback")
                values.insert("audioVolume")
            case .applianceCycle:
                values.insert("washerOperatingState")
                values.insert("dryerOperatingState")
            case .maintenanceQuery, .unsupported:
                break
            }
        }
        return values.sorted()
    }
}
