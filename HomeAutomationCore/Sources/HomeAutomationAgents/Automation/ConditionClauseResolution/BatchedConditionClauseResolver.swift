import Foundation
import FoundationModels
import HomeAutomationCore
import os

public struct BatchedConditionClauseResolver: Sendable {
    private let singleResolver: AutomationConditionClauseResolutionWorkerSession
    private let foundationModelAvailability: @Sendable () -> Bool
    private let resolveBatchOutput: (@Sendable ([AutomationConditionClauseResolutionInput]) async throws -> BatchedConditionClauseFMOutput)?
    private let deterministicAcceptThreshold: Double
    private let timeoutConfiguration: FoundationModelTimeoutConfiguration
    private let deterministicResolver = AutomationConditionDeterministicResolver()
    private let roundTripTarget: AutomationConditionGraphTarget
    private let logger = Logger(subsystem: "HomeAutomation", category: "Automation.BatchedConditionClause")

    public init(
        singleResolver: AutomationConditionClauseResolutionWorkerSession,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        resolveBatchOutput: (@Sendable ([AutomationConditionClauseResolutionInput]) async throws -> BatchedConditionClauseFMOutput)? = nil,
        deterministicAcceptThreshold: Double = 0.8,
        timeoutConfiguration: FoundationModelTimeoutConfiguration = .default
    ) {
        self.singleResolver = singleResolver
        self.foundationModelAvailability = foundationModelAvailability
        self.resolveBatchOutput = resolveBatchOutput
        self.deterministicAcceptThreshold = deterministicAcceptThreshold
        self.timeoutConfiguration = timeoutConfiguration
        self.roundTripTarget = AutomationConditionGraphTarget()
    }

    private var serviceTimeoutNanoseconds: UInt64 {
        UInt64(max(0, timeoutConfiguration.serviceTimeoutMs) * 1_000_000)
    }

    public func resolveAll(
        _ inputs: [AutomationConditionClauseResolutionInput]
    ) async -> [AutomationConditionClauseResolutionResult] {
        guard !inputs.isEmpty else { return [] }
        if inputs.count == 1 {
            return [await resolveSingle(inputs[0])]
        }

        var results = [String: AutomationConditionClauseResolutionResult]()
        var residuals = [(index: Int, input: AutomationConditionClauseResolutionInput)]()

        for (index, input) in inputs.enumerated() {
            let assessment = deterministicResolver.assess(input: input)
            if assessment.isSafeToAccept(for: roundTripTarget), assessment.confidence >= deterministicAcceptThreshold {
                logger.debug("[τ-gate] Batched condition \(input.component.id) accepted deterministically (\(assessment.confidence)).")
                results[input.component.id] = AutomationConditionClauseResolutionResult(
                    id: input.component.id,
                    rawText: input.component.rawText,
                    condition: assessment.condition,
                    records: assessment.records,
                    confidence: assessment.confidence
                )
                continue
            }
            residuals.append((index, input))
        }

        if !residuals.isEmpty {
            let batchedResults = await resolveBatch(residuals.map(\.input))
            for (i, result) in batchedResults.enumerated() where i < residuals.count {
                results[residuals[i].input.component.id] = result
            }
        }

        return inputs.map { input in
            results[input.component.id] ?? makeResult(condition: nil, input: input, confidence: 0)
        }
    }

    private func resolveSingle(
        _ input: AutomationConditionClauseResolutionInput
    ) async -> AutomationConditionClauseResolutionResult {
        do {
            return try await singleResolver.resolve(input)
        } catch {
            return makeResult(condition: nil, input: input, confidence: 0)
        }
    }

    private func resolveBatch(
        _ inputs: [AutomationConditionClauseResolutionInput]
    ) async -> [AutomationConditionClauseResolutionResult] {
        guard foundationModelAvailability() else {
            logger.debug("[BatchedCondition] FM unavailable; returning deterministic fallbacks for \(inputs.count) residuals.")
            return inputs.map { input in
                let assessment = deterministicResolver.assess(input: input)
                return makeResult(condition: assessment.condition, input: input, confidence: assessment.confidence)
            }
        }

        let prompt = batchedPrompt(for: inputs)
        logger.debug("[BatchedConditionInput] \(prompt, privacy: .public)")

        let compatibility = FoundationModelBatchCompatibilityKey(
            runID: HomeAutomationTelemetryScope.current?.runID,
            instructionDigest: FoundationModelBatchCompatibilityKey.stableDigest(batchedInstructions),
            responseSchemaDigest: FoundationModelBatchCompatibilityKey.stableDigest("BatchedConditionClauseFMOutput.v2.itemID"),
            toolSetDigest: FoundationModelBatchCompatibilityKey.stableDigest("availableConditionDevices|capabilityAttributeCatalog"),
            privacyClass: .privateUserData,
            workflowScopeID: FMAdmissionContextScope.current?.workflowScopeID
        )
        let batchContext = FoundationModelBatchContext(
            batchID: "condition-\(UUID().uuidString)",
            itemCount: inputs.count,
            compatibilityDigest: compatibility.digest
        )

        do {
            let fmOutput = try await FoundationModelBatchContextScope.$current.withValue(batchContext) {
                if let resolveBatchOutput {
                    return try await resolveBatchOutput(inputs)
                }
                let session = LanguageModelSession(
                    instructions: Instructions(batchedInstructions)
                )
                return try await FoundationModelCallRecorder.record(
                    agentID: AgentID.automationConditionClauseResolution.rawValue + ".batched",
                    policyMode: "batched-model-first-with-fallback",
                    modelAvailability: "available",
                    promptCharacterCount: batchedInstructions.count + prompt.count,
                    selectedToolNames: ["availableConditionDevices", "capabilityAttributeCatalog"],
                    serviceTimeoutNanoseconds: serviceTimeoutNanoseconds
                ) {
                    try await session.respond(
                        to: Prompt(prompt),
                        generating: BatchedConditionClauseFMOutput.self
                    ).content
                }
            }
            logger.debug("[BatchedConditionOutput] \(fmOutput.items.count) items returned.")

            let outputsByID = validOutputsByItemID(fmOutput.items, expectedIDs: Set(inputs.map(\.component.id)))
            return inputs.map { input in
                let itemOutput = outputsByID[input.component.id]
                let assessment = deterministicResolver.assess(input: input)
                if let itemOutput, itemOutput.confidence >= 0.5 {
                    return makeResult(
                        from: itemOutput,
                        input: input,
                        fallback: assessment.condition
                    )
                }
                return makeResult(condition: assessment.condition, input: input, confidence: assessment.confidence)
            }
        } catch {
            logger.error("[BatchedConditionError] \(error.localizedDescription, privacy: .public); returning deterministic fallbacks.")
            return inputs.map { input in
                let assessment = deterministicResolver.assess(input: input)
                return makeResult(condition: assessment.condition, input: input, confidence: assessment.confidence)
            }
        }
    }


    // MARK: - Result Construction

    private func makeResult(
        condition: HomeAutomationCondition?,
        input: AutomationConditionClauseResolutionInput,
        confidence: Double
    ) -> AutomationConditionClauseResolutionResult {
        AutomationConditionClauseResolutionResult(
            id: input.component.id,
            rawText: input.component.rawText,
            condition: condition,
            records: buildRecords(input: input, original: nil, resolved: condition),
            confidence: confidence
        )
    }

    private func makeResult(
        from fmOutput: BatchedConditionClauseItemOutput,
        input: AutomationConditionClauseResolutionInput,
        fallback: HomeAutomationCondition?
    ) -> AutomationConditionClauseResolutionResult {
        let baseCondition = (try? fmOutput.condition?.makeHomeCondition(
            defaultTriggerPolicy: input.triggerPolicy
        )) ?? fallback

        let resolved = baseCondition.map { condition in
            applyFMResolution(
                deviceID: fmOutput.deviceID,
                capability: fmOutput.capability,
                attribute: fmOutput.attribute,
                to: condition,
                devices: input.availableDevices
            )
        }

        return AutomationConditionClauseResolutionResult(
            id: input.component.id,
            rawText: input.component.rawText,
            condition: resolved,
            records: buildRecords(input: input, original: baseCondition, resolved: resolved),
            confidence: fmOutput.confidence
        )
    }

    private func buildRecords(
        input: AutomationConditionClauseResolutionInput,
        original: HomeAutomationCondition?,
        resolved: HomeAutomationCondition?
    ) -> [AutomationConditionOperandResolutionRecord] {
        guard let resolvedOperand = firstDeviceOperand(in: resolved) else {
            return []
        }
        let inputOperand = firstDeviceOperand(in: original) ?? resolvedOperand
        return [
            AutomationConditionOperandResolutionRecord(
                id: input.component.id,
                order: input.component.order,
                path: "condition.\(input.component.id).left",
                description: input.component.rawText,
                input: inputOperand,
                output: resolvedOperand
            )
        ]
    }

    private func firstDeviceOperand(in condition: HomeAutomationCondition?) -> HomeAutomationConditionOperand? {
        guard let condition else { return nil }
        switch condition {
        case .comparison(let comparison):
            if case .deviceAttribute = comparison.left { return comparison.left }
            if case .deviceAttribute = comparison.right { return comparison.right }
            return nil
        case .and(let children), .or(let children):
            return children.compactMap { firstDeviceOperand(in: $0) }.first
        case .not(let child), .changes(let child):
            return firstDeviceOperand(in: child)
        }
    }

    // MARK: - FM Resolution Application

    private func applyFMResolution(
        deviceID: String?,
        capability: String?,
        attribute: String?,
        to condition: HomeAutomationCondition,
        devices: [HomeCandidateRecord]
    ) -> HomeAutomationCondition {
        guard let deviceID, let capability,
              let matchedDevice = devices.first(where: { $0.id == deviceID }),
              matchedDevice.capabilities.contains(capability) else {
            return condition
        }
        let resolvedAttribute = validAttribute(attribute, capability: capability)
        return replaceFirstUnresolvedDeviceOperand(
            in: condition,
            deviceID: deviceID,
            capability: capability,
            attribute: resolvedAttribute
        )
    }

    // MARK: - Prompt Construction

    private var batchedInstructions: String {
        """
        Resolve multiple automation condition clauses into structured conditions in one pass.

        For each clause, decide the condition operator and operands. Choose deviceID, capability, and attribute from the provided device and capability lists.
        Return one result per clause. Each result must echo the clause itemID exactly.
        Use the requested triggerPolicy for each clause.
        Do not resolve actions or SmartThings JSON.
        """
    }

    private func batchedPrompt(for inputs: [AutomationConditionClauseResolutionInput]) -> String {
        let uniqueDevices = stableUniqueDevices(inputs.flatMap(\.availableDevices))
        // Hard prompt budget: a large registry must not inflate the batch prompt. Keep only
        // clause-relevant devices, then stable-fill up to the cap.
        let allDevices = budgetedDevices(uniqueDevices, for: inputs)
        let allCapabilities = Array(Set(allDevices.flatMap(\.capabilities))).sorted()

        var clauses = ""
        for (index, input) in inputs.enumerated() {
            let assessment = deterministicResolver.assess(input: input)
            clauses += """

            --- Clause \(index + 1) ---
            itemID: \(input.component.id)
            rawText: \(input.component.rawText)
            triggerPolicy: \(input.triggerPolicy.rawValue)
            deterministicHint: \(String(describing: assessment.condition))

            """
        }

        return """
        Full user command:
        \(inputs.first?.fullUserText ?? "")

        Number of condition clauses to resolve: \(inputs.count)
        \(clauses)
        Available devices:
        \(AvailableConditionDevicesTool.promptList(from: allDevices))

        Capability attributes:
        \(CapabilityAttributeCatalogTool.promptList(for: allCapabilities))

        Return exactly \(inputs.count) items. Each item must include itemID copied from a clause above. Order does not matter; itemID is authoritative.
        """
    }

    private func validOutputsByItemID(
        _ outputs: [BatchedConditionClauseItemOutput],
        expectedIDs: Set<String>
    ) -> [String: BatchedConditionClauseItemOutput] {
        let grouped = Dictionary(grouping: outputs) { $0.itemID }
        var valid: [String: BatchedConditionClauseItemOutput] = [:]
        for (itemID, matches) in grouped {
            guard expectedIDs.contains(itemID), matches.count == 1 else {
                logger.debug("[BatchedCondition] Ignoring invalid itemID \(itemID, privacy: .public), count=\(matches.count).")
                continue
            }
            valid[itemID] = matches[0]
        }
        return valid
    }

    // MARK: - Prompt budgeting

    /// Hard cap on devices listed in a batch condition prompt. Sized so the device
    /// section stays well within the ~8k-character condition prompt budget.
    public static let maxBatchPromptDevices = 48

    /// Selects a bounded device subset for the batch prompt: clause-relevant devices
    /// first (token overlap with any clause text), then stable-fill up to the cap.
    func budgetedDevices(
        _ devices: [HomeCandidateRecord],
        for inputs: [AutomationConditionClauseResolutionInput]
    ) -> [HomeCandidateRecord] {
        guard devices.count > Self.maxBatchPromptDevices else { return devices }

        let clauseTokenSets = inputs.map { promptTokens($0.component.rawText) }
        func isRelevant(_ device: HomeCandidateRecord) -> Bool {
            let deviceTokens = promptTokens(device.displayName).union(promptTokens(device.deviceType))
            guard !deviceTokens.isEmpty else { return false }
            return clauseTokenSets.contains { !$0.isDisjoint(with: deviceTokens) }
        }

        var selected: [HomeCandidateRecord] = []
        var seen = Set<String>()
        for device in devices where isRelevant(device) {
            if seen.insert(device.id).inserted { selected.append(device) }
            if selected.count >= Self.maxBatchPromptDevices { return selected }
        }
        for device in devices {
            if selected.count >= Self.maxBatchPromptDevices { break }
            if seen.insert(device.id).inserted { selected.append(device) }
        }
        return selected
    }

    private func promptTokens(_ value: String) -> Set<String> {
        let normalized = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\s]+"#, with: " ", options: .regularExpression)
        return Set(normalized.split(separator: " ").map(String.init).filter { $0.count >= 3 })
    }

    // MARK: - Helpers

    private func stableUniqueDevices(_ devices: [HomeCandidateRecord]) -> [HomeCandidateRecord] {
        var seen = Set<String>()
        return devices.filter { device in
            guard !seen.contains(device.id) else { return false }
            seen.insert(device.id)
            return true
        }
    }

    private func replaceFirstUnresolvedDeviceOperand(
        in condition: HomeAutomationCondition,
        deviceID: String,
        capability: String,
        attribute: String
    ) -> HomeAutomationCondition {
        switch condition {
        case .comparison(let comparison):
            return .comparison(
                HomeAutomationComparisonCondition(
                    left: resolvedOperand(comparison.left, deviceID: deviceID, capability: capability, attribute: attribute),
                    operatorName: comparison.operatorName,
                    right: comparison.right,
                    triggerPolicy: comparison.triggerPolicy
                )
            )
        case .changes(let child):
            return .changes(replaceFirstUnresolvedDeviceOperand(in: child, deviceID: deviceID, capability: capability, attribute: attribute))
        case .and(let children):
            return .and(children.map { replaceFirstUnresolvedDeviceOperand(in: $0, deviceID: deviceID, capability: capability, attribute: attribute) })
        case .or(let children):
            return .or(children.map { replaceFirstUnresolvedDeviceOperand(in: $0, deviceID: deviceID, capability: capability, attribute: attribute) })
        case .not(let child):
            return .not(replaceFirstUnresolvedDeviceOperand(in: child, deviceID: deviceID, capability: capability, attribute: attribute))
        }
    }

    private func resolvedOperand(
        _ operand: HomeAutomationConditionOperand,
        deviceID: String,
        capability: String,
        attribute: String
    ) -> HomeAutomationConditionOperand {
        guard case .deviceAttribute(let description, let existingDeviceID, let existingCapability, let existingAttribute) = operand,
              isEmpty(existingDeviceID) || isEmpty(existingCapability) || isEmpty(existingAttribute) else {
            return operand
        }
        return .deviceAttribute(
            description: description,
            deviceID: deviceID,
            capability: capability,
            attribute: attribute
        )
    }

    private func validAttribute(_ attribute: String?, capability: String) -> String {
        AutomationConditionDeterministicResolver.validAttribute(attribute, capability: capability)
    }

    private func isEmpty(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }
}
