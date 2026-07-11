import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import os

public struct AutomationActionMiniPipeline: Sendable {
    private let pipeline: DeterministicDraftPipeline
    private let registry: any DeviceRegistryProtocol
    private let validator: AgentCommandValidator
    private let fragmentNLU: FragmentNLUWorkerSession
    private let capabilityWorker: CapabilityResolutionWorker
    private let deterministicConfidenceThreshold: Double
    private let logger = Logger(subsystem: "HomeAutomation", category: "Automation.MiniPipeline")

    public init(
        registry: any DeviceRegistryProtocol,
        validator: AgentCommandValidator,
        fragmentNLU: FragmentNLUWorkerSession,
        capabilityWorker: CapabilityResolutionWorker,
        deterministicConfidenceThreshold: Double = 0.78
    ) {
        self.pipeline = DeterministicDraftPipeline(registry: registry)
        self.registry = registry
        self.validator = validator
        self.fragmentNLU = fragmentNLU
        self.capabilityWorker = capabilityWorker
        self.deterministicConfidenceThreshold = deterministicConfidenceThreshold
    }

    public func resolve(
        _ actionText: String,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> AutomationActionResolutionResult {
        logger.info("Mini-pipeline resolving: '\(actionText, privacy: .private)'")

        let envelope = await pipeline.makeCommandEnvelope(text: actionText)
        let candidates = await candidateRecords(from: envelope)
        let state = AgentTextParser.deterministicState(for: actionText)

        var capDecision: HomeCapabilityDecision?
        let minFieldConf = envelope.fieldConfidence.values.min() ?? 0.0
        if minFieldConf < deterministicConfidenceThreshold {
            let capInput = CapabilityResolutionInput(
                rawText: actionText,
                resolutionState: state,
                hydratedCandidates: candidates,
                aggregation: HomeCandidateAggregationResult(
                    finalCandidateIDs: envelope.command?.targetDeviceID.map { [$0] } ?? [],
                    needsClarification: false,
                    confidence: envelope.command.map { cmd in cmd.targetDeviceID != nil ? 0.9 : 0.3 } ?? 0.5
                ),
                knowledgeSnippets: []
            )
            capDecision = try? await capabilityWorker.resolve(capInput)
        }

        let draft = StructuralDraftBuilder.commandDraft(
            from: envelope.command,
            risk: envelope.risk,
            capabilityOverride: capDecision
        )

        let aggregation = HomeCandidateAggregationResult(
            finalCandidateIDs: envelope.command?.targetDeviceID.map { [$0] } ?? [],
            needsClarification: envelope.clarification != nil,
            clarificationQuestion: envelope.clarification?.question,
            confidence: envelope.command.map { cmd in cmd.targetDeviceID != nil ? 0.9 : 0.3 } ?? 0.5
        )

        let resolution: HomeCommandResolution
        if let draft {
            let validationInput = HomeFinalResolutionInput(
                rawText: actionText,
                resolutionState: state,
                hydratedCandidates: candidates,
                aggregation: aggregation,
                capabilityDecision: capDecision
            )
            resolution = validator.validate(draft, input: validationInput)
        } else if let question = envelope.clarification?.question {
            resolution = .needsClarification(question)
        } else {
            resolution = .unsupported("Could not resolve action deterministically.")
        }

        let resolvedAction: HomeAutomationResolvedAction?
        if let draft {
            let device = envelope.command?.targetDeviceID.flatMap { id in
                candidates.first { $0.id == id }
            }
            resolvedAction = HomeAutomationResolvedAction(
                originalText: actionText,
                draft: draft,
                device: device,
                confidence: draft.confidence
            )
        } else {
            resolvedAction = nil
        }

        logger.info("Mini-pipeline result: draft=\(draft != nil), device=\(resolvedAction?.device?.displayName ?? "none", privacy: .public)")

        return AutomationActionResolutionResult(
            resolvedAction: resolvedAction,
            retrievedCandidates: candidates,
            hydratedCandidates: candidates,
            selectedCandidateIDs: aggregation.finalCandidateIDs,
            draft: draft,
            resolution: resolution,
            aggregation: aggregation
        )
    }

    /// Hydrates the envelope's compact candidate table from the device
    /// registry. The compact records carry no capability data, and
    /// `AgentCommandValidator` rejects any draft whose target device does not
    /// list the chosen capability — so validating against unhydrated records
    /// silently fails every action as "capability not supported".
    private func candidateRecords(from envelope: DraftEnvelope) async -> [HomeCandidateRecord] {
        let compactCandidates = envelope.command?.candidateTable ?? []
        guard !compactCandidates.isEmpty else { return [] }
        let devicesByID = Dictionary(
            uniqueKeysWithValues: await registry.allDevices().map { ($0.id, $0) }
        )
        var seen = Set<String>()
        return compactCandidates.compactMap { compact -> HomeCandidateRecord? in
            guard !seen.contains(compact.id) else { return nil }
            seen.insert(compact.id)
            if let device = devicesByID[compact.id] {
                return device
            }
            return HomeCandidateRecord(
                id: compact.id,
                displayName: compact.name,
                deviceType: compact.deviceType,
                room: compact.room,
                capabilities: [],
                supportedCommands: [:]
            )
        }
    }
}
