import Foundation
import HomeAutomationCore
import os

/// Completeness classification for deterministic condition assessment.
public enum AutomationConditionCompleteness: String, Sendable, Codable {
    case complete
    case partial
    case ambiguous
    case unsupported
}

/// Reasons why a condition cannot be deterministically accepted (consumer-independent or target-specific).
public enum AutomationConditionResidualReason: String, Sendable, Codable, Hashable {
    case parseFailure
    case unsupportedTreeForm
    case unsupportedClauseForm
    case deviceNotResolved
    case deviceNotUnique
    case capabilityNotAdvertised
    case attributeNotValid
    case operatorNotValid
    case valueTypeInvalid
    case enumValueNotFound
    case numberOutOfRange
    case unitMismatch
    case triggerPolicyNotPreserved
    case notRoundTripSafe
}

/// Protocol for consuming conditions with consumer-specific round-trip safety evaluation.
public protocol AutomationConditionRoundTripTarget: Sendable {
    /// Returns nil if the condition round-trips losslessly for this consumer; otherwise the reason.
    func roundTripResidual(for condition: HomeAutomationCondition) -> AutomationConditionResidualReason?
}

/// Result of deterministic condition assessment.
public struct AutomationConditionDeterministicAssessment: Sendable {
    /// Resolved condition candidate, or nil if assessment failed early.
    public let condition: HomeAutomationCondition?
    /// Resolution records (device operand tracking).
    public let records: [AutomationConditionOperandResolutionRecord]
    /// Completeness classification.
    public let completeness: AutomationConditionCompleteness
    /// Deterministic confidence score (0.72 or 0.84).
    public let confidence: Double
    /// Consumer-independent residual reasons (excluding round-trip residuals).
    public let residualReasons: [AutomationConditionResidualReason]

    /// Evaluate whether this assessment is safe to accept for a given consumer.
    public func isSafeToAccept(for target: some AutomationConditionRoundTripTarget) -> Bool {
        guard completeness == .complete, let condition else { return false }
        return target.roundTripResidual(for: condition) == nil
    }
}

/// Shared deterministic condition assessor used by both single and batch resolvers.
public struct AutomationConditionDeterministicResolver: Sendable {
    private let logger = Logger(subsystem: "HomeAutomation", category: "Automation.DeterministicCondition")

    public init() {}

    /// Assess a condition clause deterministically without FM.
    public func assess(
        input: AutomationConditionClauseResolutionInput
    ) -> AutomationConditionDeterministicAssessment {
        guard let output = AutomationPatternParser.condition(
            from: input.component.rawText,
            triggerPolicy: triggerPolicyOutput(input.triggerPolicy)
        ) else {
            return AutomationConditionDeterministicAssessment(
                condition: nil,
                records: [],
                completeness: .unsupported,
                confidence: 0,
                residualReasons: [.parseFailure]
            )
        }

        guard let condition = try? output.makeHomeCondition(defaultTriggerPolicy: input.triggerPolicy) else {
            return AutomationConditionDeterministicAssessment(
                condition: nil,
                records: [],
                completeness: .unsupported,
                confidence: 0,
                residualReasons: [.parseFailure]
            )
        }

        let resolved = resolveDeterministically(condition, devices: input.availableDevices)
        let hasDevice = hasResolvedDevice(resolved)
        let confidence = hasDevice ? 0.84 : 0.72
        let records = buildRecords(
            input: input,
            original: condition,
            resolved: resolved
        )

        // A device operand that is still unresolved (empty deviceID) means the
        // condition is only partially resolved deterministically and must go to FM.
        // Modeling this as `.complete` would make `isSafeToAccept` and any residual
        // classification incorrect; the confidence gate alone previously masked it.
        if hasUnresolvedDeviceOperand(resolved) {
            return AutomationConditionDeterministicAssessment(
                condition: resolved,
                records: records,
                completeness: .partial,
                confidence: confidence,
                residualReasons: [.deviceNotResolved]
            )
        }

        return AutomationConditionDeterministicAssessment(
            condition: resolved,
            records: records,
            completeness: .complete,
            confidence: confidence,
            residualReasons: []
        )
    }

    // MARK: - Device Resolution

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

    // MARK: - Completion Detection

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

    /// Detects a `.deviceAttribute` operand that still lacks a resolved deviceID.
    private func hasUnresolvedDeviceOperand(_ condition: HomeAutomationCondition) -> Bool {
        switch condition {
        case .comparison(let comparison):
            return operandIsUnresolvedDevice(comparison.left) || operandIsUnresolvedDevice(comparison.right)
        case .and(let children), .or(let children):
            return children.contains { hasUnresolvedDeviceOperand($0) }
        case .not(let child), .changes(let child):
            return hasUnresolvedDeviceOperand(child)
        }
    }

    private func operandIsUnresolvedDevice(_ operand: HomeAutomationConditionOperand) -> Bool {
        if case .deviceAttribute(_, let deviceID, _, _) = operand {
            return deviceID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        }
        return false
    }

    // MARK: - Record Building

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

    // MARK: - Helpers

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
