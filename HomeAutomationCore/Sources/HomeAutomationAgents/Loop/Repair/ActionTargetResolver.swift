import Foundation
import HomeAutomationCore

public struct ActionTargetResolver: Sendable {
    private let registry: any DeviceRegistryProtocol

    public init(registry: any DeviceRegistryProtocol) {
        self.registry = registry
    }

    public func resolve(
        fragmentText: String,
        candidates: [CompactCandidate],
        hint: String?
    ) async -> ActionTargetResult {
        let normalized = fragmentText.agentNormalizedHomeTokenString
        let devices = await registry.allDevices()

        let scopedDevices: [HomeCandidateRecord]
        if !candidates.isEmpty {
            let candidateIDs = Set(candidates.map(\.id))
            scopedDevices = devices.filter { candidateIDs.contains($0.id) }
        } else {
            scopedDevices = devices
        }

        guard let ruleIntent = AgentRuleIntent(normalized: normalized) else {
            return ActionTargetResult(
                selectedDeviceID: hint,
                candidateTable: candidates,
                confidence: 0.0,
                isAmbiguous: true
            )
        }

        let semanticHints: AgentSemanticHints
        if let hint {
            semanticHints = AgentSemanticHints(
                preferredDeviceIDs: Set([hint]),
                preferredCapabilityIDs: Set()
            )
        } else {
            semanticHints = AgentSemanticHints()
        }

        let ranking = RuleCandidateScorer.rank(
            devices: scopedDevices,
            intent: ruleIntent,
            normalized: normalized,
            semanticHints: semanticHints
        )

        guard let selected = ranking.selected else {
            return ActionTargetResult(
                selectedDeviceID: hint,
                candidateTable: ranking.scored.prefix(8).map { CompactCandidate(from: $0.device) },
                confidence: 0.0,
                isAmbiguous: true
            )
        }

        return ActionTargetResult(
            selectedDeviceID: selected.device.id,
            candidateTable: ranking.scored.prefix(8).map { CompactCandidate(from: $0.device) },
            confidence: ranking.confidence,
            isAmbiguous: ranking.isAmbiguous
        )
    }
}

public struct ActionTargetResult: Sendable, Hashable {
    public let selectedDeviceID: String?
    public let candidateTable: [CompactCandidate]
    public let confidence: Double
    public let isAmbiguous: Bool

    public init(
        selectedDeviceID: String?,
        candidateTable: [CompactCandidate],
        confidence: Double,
        isAmbiguous: Bool
    ) {
        self.selectedDeviceID = selectedDeviceID
        self.candidateTable = candidateTable
        self.confidence = confidence
        self.isAmbiguous = isAmbiguous
    }
}
