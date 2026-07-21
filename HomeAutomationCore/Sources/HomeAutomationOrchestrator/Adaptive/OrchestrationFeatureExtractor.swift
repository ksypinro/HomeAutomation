import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public struct OrchestrationFeatureExtractor: Sendable {
    public struct Input: Sendable {
        public let request: CommandRequest
        public let memoryHints: [MemoryHint]
        public let foundationModelAvailability: PortfolioFeatureAvailability
        public let ragAvailability: PortfolioFeatureAvailability
        public let gateDepth: PortfolioGateDepthBucket
        public let warmStateHint: PortfolioWarmStateHint

        public init(
            request: CommandRequest,
            memoryHints: [MemoryHint] = [],
            foundationModelAvailability: PortfolioFeatureAvailability = .unknown,
            ragAvailability: PortfolioFeatureAvailability = .unknown,
            gateDepth: PortfolioGateDepthBucket = .unknown,
            warmStateHint: PortfolioWarmStateHint = .unknown
        ) {
            self.request = request
            self.memoryHints = memoryHints
            self.foundationModelAvailability = foundationModelAvailability
            self.ragAvailability = ragAvailability
            self.gateDepth = gateDepth
            self.warmStateHint = warmStateHint
        }
    }

    private let registry: any DeviceRegistryProtocol
    private let clock: any FoundationModelMonotonicClock

    public init(
        registry: any DeviceRegistryProtocol,
        clock: any FoundationModelMonotonicClock = SystemFoundationModelMonotonicClock()
    ) {
        self.registry = registry
        self.clock = clock
    }

    public func prepare(_ input: Input) async -> PreparedOrchestrationRequest {
        let started = clock.nowNanoseconds()
        do {
            return try await buildPrepared(input, started: started)
        } catch is CancellationError {
            return failedPreparation(
                input,
                started: started,
                code: .cancelled,
                detail: "deterministic preparation cancelled before completion"
            )
        } catch {
            return failedPreparation(
                input,
                started: started,
                code: .extractionFailed,
                detail: "deterministic preparation failed before completion"
            )
        }
    }

    private func buildPrepared(
        _ input: Input,
        started: UInt64
    ) async throws -> PreparedOrchestrationRequest {
        try Task.checkCancellation()
        let text = input.request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = AgentTextParser.deterministicState(
            for: text,
            riskReason: "Adaptive deterministic preparation"
        )
        let operation = HomeOperationDetectionService().analyzeSemantics(text)
        try Task.checkCancellation()
        let devices = await registry.allDevices()
        try Task.checkCancellation()
        let deviceSnapshot = PreparedDeviceSnapshot(devices: devices)
        let deterministicEnvelope = await makeEnvelope(text: text, operation: operation, memoryHints: input.memoryHints)
        try Task.checkCancellation()
        let candidateIDs = await registry
            .retrieveCandidates(text: text, hints: state, limit: 80)
            .map(\.id)
        try Task.checkCancellation()
        let memoryReference = ConversationMemoryReferenceDetector.containsMemoryReference(text)
        let candidateMargin = candidateTopTwoMargin(text: text, candidates: devices, state: state)
        let confidences = deterministicEnvelope.fieldConfidence.values.sorted()
        let durationMs = Self.milliseconds(from: started, to: clock.nowNanoseconds())

        let snapshot = PortfolioFeatureSnapshot(
            operation: .present(operation.operation, source: .deterministicParser),
            operationConfidence: .present(clamp(operation.confidence), source: .deterministicParser),
            languageOODSignal: .present(oodSignal(from: state), source: .deterministicParser),
            textSizeBucket: .present(
                PortfolioTextSizeBucket(characterCount: text.count),
                source: .deterministicParser
            ),
            actionCount: .present(actionCount(in: deterministicEnvelope), source: .deterministicDraftPipeline),
            conditionCount: .present(conditionCount(in: deterministicEnvelope), source: .deterministicDraftPipeline),
            minimumFieldConfidence: confidenceFeature(confidences, selector: { $0.first }),
            p50FieldConfidence: confidenceFeature(confidences, selector: { quantile($0, q: 0.50) }),
            p90FieldConfidence: confidenceFeature(confidences, selector: { quantile($0, q: 0.90) }),
            candidateCount: .present(candidateIDs.count, source: .registrySnapshot),
            candidateTopTwoMargin: .present(candidateMargin, source: .registrySnapshot),
            unsupportedFragmentCount: .present(
                deterministicEnvelope.automation?.unsupportedFragments.count ?? 0,
                source: .deterministicDraftPipeline
            ),
            precedenceAmbiguity: .present(
                deterministicEnvelope.automation?.precedenceAmbiguous ?? false,
                source: .deterministicDraftPipeline
            ),
            riskFloor: .present(deterministicEnvelope.risk.level, source: .deterministicDraftPipeline),
            memoryReference: .present(memoryReference, source: .memoryDetector),
            exactTemplateMatch: .present(
                exactTemplateMatch(envelope: deterministicEnvelope),
                source: .deterministicDraftPipeline
            ),
            foundationModelAvailability: .present(
                input.foundationModelAvailability,
                source: .runtimeAvailability
            ),
            ragAvailability: .present(input.ragAvailability, source: .runtimeAvailability),
            gateDepth: .present(input.gateDepth, source: .runtimeAvailability),
            warmStateHint: .present(input.warmStateHint, source: .runtimeAvailability),
            extractionDurationMs: durationMs
        )

        return PreparedOrchestrationRequest(
            request: PreparedCommandRequestMetadata(request: input.request),
            featureSnapshot: snapshot,
            deterministicEnvelope: deterministicEnvelope,
            deviceSnapshot: deviceSnapshot,
            memoryReferenceDetected: memoryReference,
            memoryHints: input.memoryHints,
            resolutionState: state,
            candidateIDs: candidateIDs
        )
    }

    private func failedPreparation(
        _ input: Input,
        started: UInt64,
        code: PreparedOrchestrationDiagnosticCode,
        detail: String
    ) -> PreparedOrchestrationRequest {
        let text = input.request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let operation = HomeOperationDetectionResult(
            domain: .unsupported,
            operation: .unsupported,
            confidence: 0,
            reason: detail
        )
        let state = HomeResolutionState.forOperation(text: text, operation: operation)
        let deviceSnapshot = PreparedDeviceSnapshot(devices: [])
        let durationMs = Self.milliseconds(from: started, to: clock.nowNanoseconds())
        let snapshot = PortfolioFeatureSnapshot(
            operation: .missing(.extractionFailed, source: .unavailable),
            operationConfidence: .missing(.extractionFailed, source: .unavailable),
            languageOODSignal: .missing(.extractionFailed, source: .unavailable),
            textSizeBucket: .present(
                PortfolioTextSizeBucket(characterCount: text.count),
                source: .deterministicParser
            ),
            actionCount: .missing(.extractionFailed, source: .unavailable),
            conditionCount: .missing(.extractionFailed, source: .unavailable),
            minimumFieldConfidence: .missing(.extractionFailed, source: .unavailable),
            p50FieldConfidence: .missing(.extractionFailed, source: .unavailable),
            p90FieldConfidence: .missing(.extractionFailed, source: .unavailable),
            candidateCount: .missing(.extractionFailed, source: .unavailable),
            candidateTopTwoMargin: .missing(.extractionFailed, source: .unavailable),
            unsupportedFragmentCount: .missing(.extractionFailed, source: .unavailable),
            precedenceAmbiguity: .missing(.extractionFailed, source: .unavailable),
            riskFloor: .missing(.extractionFailed, source: .unavailable),
            memoryReference: .missing(.extractionFailed, source: .unavailable),
            exactTemplateMatch: .missing(.extractionFailed, source: .unavailable),
            foundationModelAvailability: .present(
                input.foundationModelAvailability,
                source: .runtimeAvailability
            ),
            ragAvailability: .present(input.ragAvailability, source: .runtimeAvailability),
            gateDepth: .present(input.gateDepth, source: .runtimeAvailability),
            warmStateHint: .present(input.warmStateHint, source: .runtimeAvailability),
            extractionDurationMs: durationMs
        )
        let envelope = DraftEnvelope(
            userText: text,
            operation: .unsupported,
            operationConfidence: 0,
            risk: RiskSection(level: .medium, floorReason: detail),
            clarification: ClarificationSection(
                question: "I could not prepare this request safely. Please try again.",
                ambiguousFieldIDs: [.operation]
            ),
            provenance: [.operation: .rules],
            fieldConfidence: [.operation: 0]
        )
        return PreparedOrchestrationRequest(
            request: PreparedCommandRequestMetadata(request: input.request),
            featureSnapshot: snapshot,
            deterministicEnvelope: envelope,
            deviceSnapshot: deviceSnapshot,
            memoryReferenceDetected: false,
            memoryHints: input.memoryHints,
            resolutionState: state,
            candidateIDs: [],
            diagnostics: [
                PreparedOrchestrationDiagnostic(
                    code: code,
                    source: .unavailable,
                    detail: detail
                )
            ]
        )
    }

    public func currentDeviceSnapshot() async -> PreparedDeviceSnapshot {
        PreparedDeviceSnapshot(devices: await registry.allDevices())
    }

    private func makeEnvelope(
        text: String,
        operation: HomeOperationDetectionResult,
        memoryHints: [MemoryHint]
    ) async -> DraftEnvelope {
        let pipeline = DeterministicDraftPipeline(registry: registry)
        if operation.operation == .automationCreation {
            return await pipeline.makeAutomationEnvelope(text: text)
        }
        return await pipeline.makeCommandEnvelope(text: text, memoryHints: memoryHints)
    }

    private func oodSignal(from state: HomeResolutionState) -> PortfolioOODSignal {
        if state.language.unsupportedLanguageLikely {
            return .unsupportedLanguage
        }
        if state.language.isMixedLanguage {
            return .mixedLanguage
        }
        if state.domain.domain == .unsupported {
            return .unsupportedDomain
        }
        if min(state.language.confidence, state.domain.confidence, state.intent.confidence) < 0.45 {
            return .lowConfidence
        }
        return .inDomain
    }

    private func actionCount(in envelope: DraftEnvelope) -> Int {
        if let automation = envelope.automation {
            return automation.actions.count
        }
        return envelope.command == nil ? 0 : 1
    }

    private func conditionCount(in envelope: DraftEnvelope) -> Int {
        guard let automation = envelope.automation else { return 0 }
        var total = automation.conditionLeaves.count
        if automation.trigger?.type == .device {
            total += 1
        }
        return total
    }

    private func exactTemplateMatch(envelope: DraftEnvelope) -> Bool {
        if let command = envelope.command {
            return command.targetDeviceID != nil &&
                command.capability != nil &&
                command.commandName != nil &&
                envelope.clarification == nil &&
                envelope.operationConfidence >= 0.80
        }

        if let automation = envelope.automation {
            return automation.trigger != nil &&
                !automation.actions.isEmpty &&
                automation.unsupportedFragments.isEmpty &&
                !automation.precedenceAmbiguous &&
                envelope.operationConfidence >= 0.80
        }

        return false
    }

    private func confidenceFeature(
        _ confidences: [Double],
        selector: ([Double]) -> Double?
    ) -> PortfolioFeatureValue<Double> {
        guard let value = selector(confidences) else {
            return .missing(.notApplicable, source: .deterministicDraftPipeline)
        }
        return .present(clamp(value), source: .deterministicDraftPipeline)
    }

    private func candidateTopTwoMargin(
        text: String,
        candidates: [HomeCandidateRecord],
        state: HomeResolutionState
    ) -> Double {
        let normalized = normalize(text)
        let hintedTypes = Set(state.deviceType.deviceTypes.map(normalize))
        let scores = candidates
            .map { score($0, normalized: normalized, hintedTypes: hintedTypes) }
            .filter { $0 > 0 }
            .sorted(by: >)
        guard let first = scores.first else { return 0 }
        let second = scores.dropFirst().first ?? 0
        return clamp(Double(first - second) / max(Double(first), 1.0))
    }

    private func score(
        _ candidate: HomeCandidateRecord,
        normalized: String,
        hintedTypes: Set<String>
    ) -> Int {
        var value = 0
        let displayName = normalize(candidate.displayName)
        let deviceType = normalize(candidate.deviceType)
        if normalized.contains(displayName) { value += 8 }
        if normalized.contains(deviceType) { value += 5 }
        if let room = candidate.room.map(normalize), normalized.contains(room) {
            value += 4
        }
        if hintedTypes.contains(deviceType) {
            value += 4
        }
        for capability in candidate.capabilities.map(normalize)
            where normalized.contains(capability) {
            value += 2
        }
        return value
    }

    private func quantile(_ sortedValues: [Double], q: Double) -> Double? {
        guard !sortedValues.isEmpty else { return nil }
        let clampedQ = clamp(q)
        let index = Int((Double(sortedValues.count - 1) * clampedQ).rounded())
        return sortedValues[max(0, min(sortedValues.count - 1, index))]
    }

    private func clamp(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9:\s]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func milliseconds(from start: UInt64, to end: UInt64) -> Double {
        guard end >= start else { return 0 }
        return Double(end - start) / 1_000_000.0
    }
}
