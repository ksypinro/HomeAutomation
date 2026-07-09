import Foundation
import FoundationModels
import HomeAutomationCore
import os

public struct BatchedConditionClauseResolver: Sendable {
    private let singleResolver: AutomationConditionClauseResolutionWorkerSession
    private let foundationModelAvailability: @Sendable () -> Bool
    private let deterministicAcceptThreshold: Double
    private let logger = Logger(subsystem: "HomeAutomation", category: "Automation.BatchedConditionClause")

    public init(
        singleResolver: AutomationConditionClauseResolutionWorkerSession,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        deterministicAcceptThreshold: Double = 0.8
    ) {
        self.singleResolver = singleResolver
        self.foundationModelAvailability = foundationModelAvailability
        self.deterministicAcceptThreshold = deterministicAcceptThreshold
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
            let deterministic = deterministicCondition(for: input)
            if let deterministic {
                let confidence = deterministicConfidence(deterministic, input: input)
                if confidence >= deterministicAcceptThreshold {
                    logger.debug("[τ-gate] Batched condition \(input.component.id) accepted deterministically (\(confidence)).")
                    results[input.component.id] = makeResult(
                        condition: deterministic,
                        input: input,
                        confidence: confidence
                    )
                    continue
                }
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
                let fallback = deterministicCondition(for: input)
                return makeResult(condition: fallback, input: input, confidence: 0.72)
            }
        }

        let prompt = batchedPrompt(for: inputs)
        logger.debug("[BatchedConditionInput] \(prompt, privacy: .public)")

        do {
            let session = LanguageModelSession(
                instructions: Instructions(batchedInstructions)
            )
            let fmOutput = try await FoundationModelCallRecorder.record(
                agentID: AgentID.automationConditionClauseResolution.rawValue + ".batched",
                policyMode: "batched-model-first-with-fallback",
                modelAvailability: "available",
                promptCharacterCount: batchedInstructions.count + prompt.count,
                selectedToolNames: ["availableConditionDevices", "capabilityAttributeCatalog"]
            ) {
                try await session.respond(
                    to: Prompt(prompt),
                    generating: BatchedConditionClauseFMOutput.self
                ).content
            }

            logger.debug("[BatchedConditionOutput] \(fmOutput.items.count) items returned.")

            return inputs.enumerated().map { index, input in
                let itemOutput = index < fmOutput.items.count ? fmOutput.items[index] : nil
                let fallback = deterministicCondition(for: input)
                if let itemOutput, itemOutput.confidence >= 0.5 {
                    return makeResult(
                        from: itemOutput,
                        input: input,
                        fallback: fallback
                    )
                }
                return makeResult(condition: fallback, input: input, confidence: 0.72)
            }
        } catch {
            logger.error("[BatchedConditionError] \(error.localizedDescription, privacy: .public); returning deterministic fallbacks.")
            return inputs.map { input in
                let fallback = deterministicCondition(for: input)
                return makeResult(condition: fallback, input: input, confidence: 0.72)
            }
        }
    }

    // MARK: - Deterministic

    private func deterministicCondition(
        for input: AutomationConditionClauseResolutionInput
    ) -> HomeAutomationCondition? {
        guard let output = AutomationPatternParser.condition(
            from: input.component.rawText,
            triggerPolicy: triggerPolicyOutput(input.triggerPolicy)
        ),
        let condition = try? output.makeHomeCondition(defaultTriggerPolicy: input.triggerPolicy) else {
            return nil
        }
        return resolveDeterministically(condition, devices: input.availableDevices)
    }

    private func deterministicConfidence(
        _ condition: HomeAutomationCondition,
        input: AutomationConditionClauseResolutionInput
    ) -> Double {
        let hasDevice = hasResolvedDevice(condition)
        return hasDevice ? 0.84 : 0.72
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
        Return one result per clause, in the same order as the input.
        Use the requested triggerPolicy for each clause.
        Do not resolve actions or SmartThings JSON.
        """
    }

    private func batchedPrompt(for inputs: [AutomationConditionClauseResolutionInput]) -> String {
        let allDevices = stableUniqueDevices(inputs.flatMap(\.availableDevices))
        let allCapabilities = Array(Set(allDevices.flatMap(\.capabilities))).sorted()

        var clauses = ""
        for (index, input) in inputs.enumerated() {
            let fallback = deterministicCondition(for: input)
            clauses += """

            --- Clause \(index + 1) ---
            id: \(input.component.id)
            rawText: \(input.component.rawText)
            triggerPolicy: \(input.triggerPolicy.rawValue)
            deterministicHint: \(String(describing: fallback))

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

        Return exactly \(inputs.count) items in the same order as the clauses above.
        """
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

    private func hasResolvedDevice(_ condition: HomeAutomationCondition) -> Bool {
        switch condition {
        case .comparison(let comparison):
            return operandHasDevice(comparison.left) || operandHasDevice(comparison.right)
        case .and(let children), .or(let children):
            return children.contains { hasResolvedDevice($0) }
        case .not(let child), .changes(let child):
            return hasResolvedDevice(child)
        }
    }

    private func operandHasDevice(_ operand: HomeAutomationConditionOperand) -> Bool {
        if case .deviceAttribute(_, let deviceID, _, _) = operand {
            return deviceID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        return false
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

    private func resolveDeterministically(
        _ condition: HomeAutomationCondition,
        devices: [HomeCandidateRecord]
    ) -> HomeAutomationCondition {
        switch condition {
        case .comparison(let comparison):
            return .comparison(
                HomeAutomationComparisonCondition(
                    left: resolveDeterministicOperand(comparison.left, comparison: comparison, devices: devices),
                    operatorName: comparison.operatorName,
                    right: resolveDeterministicOperand(comparison.right, comparison: comparison, devices: devices),
                    triggerPolicy: comparison.triggerPolicy
                )
            )
        case .and(let children):
            return .and(children.map { resolveDeterministically($0, devices: devices) })
        case .or(let children):
            return .or(children.map { resolveDeterministically($0, devices: devices) })
        case .not(let child):
            return .not(resolveDeterministically(child, devices: devices))
        case .changes(let child):
            return .changes(resolveDeterministically(child, devices: devices))
        }
    }

    private func resolveDeterministicOperand(
        _ operand: HomeAutomationConditionOperand,
        comparison: HomeAutomationComparisonCondition,
        devices: [HomeCandidateRecord]
    ) -> HomeAutomationConditionOperand {
        guard case .deviceAttribute(let description, let deviceID, let capability, let attribute) = operand,
              isEmpty(deviceID) || isEmpty(capability) || isEmpty(attribute),
              let device = bestDevice(for: description, devices: devices),
              let resolvedCapability = bestCapability(for: description, device: device, comparison: comparison) else {
            return operand
        }
        let resolvedAttribute = validAttribute(nil, capability: resolvedCapability)
        return .deviceAttribute(
            description: description,
            deviceID: device.id,
            capability: resolvedCapability,
            attribute: resolvedAttribute
        )
    }

    private func bestDevice(for description: String, devices: [HomeCandidateRecord]) -> HomeCandidateRecord? {
        let query = normalize(description)
        let scored: [(device: HomeCandidateRecord, score: Int)] = devices.map { device in
            (device: device, score: score(device, query: query))
        }
        let sorted = scored
            .filter { $0.score > 0 }
            .sorted {
                $0.score == $1.score
                    ? $0.device.displayName < $1.device.displayName
                    : $0.score > $1.score
            }
        guard let best = sorted.first else { return nil }
        if sorted.dropFirst().contains(where: { $0.score == best.score }) {
            return nil
        }
        return best.device
    }

    private func score(_ device: HomeCandidateRecord, query: String) -> Int {
        var total = 0
        let name = normalize(device.displayName)
        let type = normalize(device.deviceType)
        let room = device.room.map(normalize)
        if query.contains(name) { total += 12 }
        if name.contains(query) { total += 10 }
        if query.contains(type) { total += 8 }
        if let room, query.contains(room) { total += 5 }
        total += Set(query.split(separator: " ").map(String.init))
            .intersection(Set(name.split(separator: " ").map(String.init)))
            .count * 2
        if (query.contains("locked") || query.contains("unlocked") || query.contains("lock")),
           device.capabilities.contains("lock") {
            total += 8
        }
        if query.contains("motion"), device.capabilities.contains("motionSensor") { total += 6 }
        if query.contains("temperature"), device.capabilities.contains("temperatureMeasurement") { total += 6 }
        if query.contains("contact"), device.capabilities.contains("contactSensor") { total += 6 }
        return total
    }

    private func bestCapability(
        for description: String,
        device: HomeCandidateRecord,
        comparison: HomeAutomationComparisonCondition
    ) -> String? {
        let query = normalize(description)
        if query.contains("brightness") || query.contains("level") || query.contains("dim") {
            if device.capabilities.contains("switchLevel") { return "switchLevel" }
        }
        if query.contains("color temperature") || query.contains("colour temperature") {
            if device.capabilities.contains("colorTemperature") { return "colorTemperature" }
        }
        if query.contains("motion"), device.capabilities.contains("motionSensor") { return "motionSensor" }
        if query.contains("temperature"), device.capabilities.contains("temperatureMeasurement") { return "temperatureMeasurement" }
        if query.contains("contact"), device.capabilities.contains("contactSensor") { return "contactSensor" }
        if case .literalString(let value) = comparison.right {
            switch value {
            case "locked", "unlocked":
                if device.capabilities.contains("lock") { return "lock" }
            case "open", "closed":
                if device.capabilities.contains("contactSensor") { return "contactSensor" }
                if device.capabilities.contains("garageDoorControl") { return "garageDoorControl" }
                if device.capabilities.contains("doorControl") { return "doorControl" }
                if device.capabilities.contains("windowShade") { return "windowShade" }
            case "on", "off":
                if device.capabilities.contains("switch") { return "switch" }
            case "active", "inactive":
                if device.capabilities.contains("motionSensor") { return "motionSensor" }
            default:
                break
            }
        }
        return device.capabilities.first { capability in
            HomeCapabilityRegistry.definitions[capability]?.attributeNames.isEmpty == false
        }
    }

    private func validAttribute(_ attribute: String?, capability: String) -> String {
        guard let definition = HomeCapabilityRegistry.definitions[capability] else {
            return attribute ?? capability
        }
        if let attribute, definition.attributeNames.contains(attribute) {
            return attribute
        }
        return definition.attributeNames.first ?? attribute ?? capability
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\s]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isEmpty(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    private func triggerPolicyOutput(
        _ policy: HomeAutomationConditionTriggerPolicy
    ) -> AutomationConditionTriggerPolicyOutput {
        switch policy {
        case .always: return .always
        case .never: return .never
        }
    }
}
