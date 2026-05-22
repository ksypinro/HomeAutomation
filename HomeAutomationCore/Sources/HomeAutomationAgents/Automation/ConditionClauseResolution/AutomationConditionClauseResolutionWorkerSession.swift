import Foundation
import FoundationModels
import HomeAutomationCore
import os

public struct AutomationConditionClauseResolutionWorkerSession: Sendable {
    private let foundationModelAvailability: @Sendable () -> Bool
    private let resolve: (@Sendable (AutomationConditionClauseResolutionInput) async throws -> AutomationConditionClauseFMOutput)?
    private let logger = Logger(subsystem: "HomeAutomation", category: "Automation.ConditionClauseResolution")

    public init(
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        resolve: (@Sendable (AutomationConditionClauseResolutionInput) async throws -> AutomationConditionClauseFMOutput)? = nil
    ) {
        self.foundationModelAvailability = foundationModelAvailability
        self.resolve = resolve
    }

    public func resolve(
        _ input: AutomationConditionClauseResolutionInput
    ) async throws -> AutomationConditionClauseResolutionResult {
        let fallback = deterministicCondition(for: input)
        if let resolve {
            return try result(from: try await resolve(input), input: input, fallback: fallback)
        }

        guard foundationModelAvailability() else {
            return try result(from: nil, input: input, fallback: fallback, confidence: 0.72)
        }

        let prompt = AutomationConditionClauseResolutionPromptBuilder.prompt(input: input, fallback: fallback)
        logger.debug("[FoundationModelInput] \(prompt, privacy: .public)")
        do {
            let session = LanguageModelSession(
                instructions: Instructions(AutomationConditionClauseResolutionPromptBuilder.instructions)
            )
            let fmOutput = try await session.respond(
                to: Prompt(prompt),
                generating: AutomationConditionClauseFMOutput.self
            ).content
            let output = try result(from: fmOutput, input: input, fallback: fallback)
            logger.debug("[FoundationModelOutput] \(String(describing: output), privacy: .public)")
            return output
        } catch {
            logger.error("[FoundationModelError] \(error.localizedDescription, privacy: .public); using deterministic condition fallback.")
            return try result(from: nil, input: input, fallback: fallback, confidence: 0.72)
        }
    }

    private func result(
        from fmOutput: AutomationConditionClauseFMOutput?,
        input: AutomationConditionClauseResolutionInput,
        fallback: HomeAutomationCondition?,
        confidence: Double? = nil
    ) throws -> AutomationConditionClauseResolutionResult {
        let baseCondition = try fmOutput?.condition?.makeHomeCondition(defaultTriggerPolicy: input.triggerPolicy) ?? fallback
        let resolvedCondition = baseCondition.map {
            applyFMResolution(
                fmOutput,
                to: $0,
                devices: input.availableDevices
            )
        }
        let records = records(
            input: input,
            original: baseCondition,
            resolved: resolvedCondition
        )
        return AutomationConditionClauseResolutionResult(
            id: input.component.id,
            rawText: input.component.rawText,
            condition: resolvedCondition,
            records: records,
            confidence: confidence ?? fmOutput?.confidence ?? (fallback == nil ? 0 : 0.72)
        )
    }

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

    private func applyFMResolution(
        _ fmOutput: AutomationConditionClauseFMOutput?,
        to condition: HomeAutomationCondition,
        devices: [HomeCandidateRecord]
    ) -> HomeAutomationCondition {
        guard let fmOutput,
              let deviceID = fmOutput.deviceID,
              let capability = fmOutput.capability,
              let matchedDevice = devices.first(where: { $0.id == deviceID }),
              matchedDevice.capabilities.contains(capability) else {
            return condition
        }
        let attribute = validAttribute(fmOutput.attribute, capability: capability)
        return replaceFirstUnresolvedDeviceOperand(
            in: condition,
            deviceID: deviceID,
            capability: capability,
            attribute: attribute
        )
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
                    left: resolvedOperand(
                        comparison.left,
                        deviceID: deviceID,
                        capability: capability,
                        attribute: attribute
                    ),
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

    private func records(
        input: AutomationConditionClauseResolutionInput,
        original: HomeAutomationCondition?,
        resolved: HomeAutomationCondition?
    ) -> [AutomationConditionOperandResolutionRecord] {
        guard let originalOperand = firstDeviceOperand(in: original),
              let resolvedOperand = firstDeviceOperand(in: resolved) else {
            return []
        }
        return [
            AutomationConditionOperandResolutionRecord(
                id: input.component.id,
                order: input.component.order,
                path: "condition.\(input.component.id).left",
                description: input.component.rawText,
                input: originalOperand,
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
        case .always:
            return .always
        case .never:
            return .never
        }
    }
}
