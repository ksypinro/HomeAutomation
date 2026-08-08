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
    case capabilityNotExplicit
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

    /// A residual condition can still be useful when it preserves the user's clause shape
    /// with unresolved operands, allowing validation to ask a targeted clarification instead
    /// of failing draft assembly. This is intentionally limited to device disambiguation
    /// residuals; semantic residuals such as unsupported units or implicit capabilities are
    /// not returned as actionable fallback conditions.
    public var isClarificationSafeFallback: Bool {
        guard condition != nil else { return false }
        guard completeness == .ambiguous || completeness == .partial else { return false }
        let allowedReasons: Set<AutomationConditionResidualReason> = [
            .deviceNotResolved,
            .deviceNotUnique
        ]
        return !residualReasons.isEmpty &&
            residualReasons.allSatisfy { allowedReasons.contains($0) }
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

        let resolvedOutput = resolveDeterministically(condition, devices: input.availableDevices)
        let resolved = resolvedOutput.condition
        let hasDevice = hasResolvedDevice(resolved)
        let confidence = hasDevice ? 0.84 : 0.72
        let records = buildRecords(
            input: input,
            original: condition,
            resolved: resolved
        )
        let residualReasons = stableReasons(
            resolvedOutput.residualReasons + validateDeterministicCondition(
                resolved,
                expectedTriggerPolicy: input.triggerPolicy
            )
        )

        if !residualReasons.isEmpty {
            return AutomationConditionDeterministicAssessment(
                condition: resolved,
                records: records,
                completeness: completeness(for: residualReasons),
                confidence: confidence,
                residualReasons: residualReasons
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

    private struct ConditionResolutionOutput {
        let condition: HomeAutomationCondition
        let residualReasons: [AutomationConditionResidualReason]
    }

    private struct OperandResolutionOutput {
        let operand: HomeAutomationConditionOperand
        let residualReasons: [AutomationConditionResidualReason]
    }

    private struct DeviceSelection {
        let device: HomeCandidateRecord?
        let reason: AutomationConditionResidualReason?
    }

    private func resolveDeterministically(
        _ condition: HomeAutomationCondition,
        devices: [HomeCandidateRecord]
    ) -> ConditionResolutionOutput {
        switch condition {
        case .comparison(let comparison):
            let left = resolveDeterministicOperand(
                comparison.left,
                comparison: comparison,
                devices: devices
            )
            let right = resolveDeterministicOperand(
                comparison.right,
                comparison: comparison,
                devices: devices
            )
            return ConditionResolutionOutput(
                condition: .comparison(
                    HomeAutomationComparisonCondition(
                        left: left.operand,
                        operatorName: comparison.operatorName,
                        right: right.operand,
                        triggerPolicy: comparison.triggerPolicy
                    )
                ),
                residualReasons: left.residualReasons + right.residualReasons
            )
        case .and(let children):
            let outputs = children.map { resolveDeterministically($0, devices: devices) }
            return ConditionResolutionOutput(
                condition: .and(outputs.map(\.condition)),
                residualReasons: outputs.flatMap(\.residualReasons)
            )
        case .or(let children):
            let outputs = children.map { resolveDeterministically($0, devices: devices) }
            return ConditionResolutionOutput(
                condition: .or(outputs.map(\.condition)),
                residualReasons: outputs.flatMap(\.residualReasons)
            )
        case .not(let child):
            let output = resolveDeterministically(child, devices: devices)
            return ConditionResolutionOutput(
                condition: .not(output.condition),
                residualReasons: output.residualReasons
            )
        case .changes(let child):
            let output = resolveDeterministically(child, devices: devices)
            return ConditionResolutionOutput(
                condition: .changes(output.condition),
                residualReasons: output.residualReasons
            )
        }
    }

    private func resolveDeterministicOperand(
        _ operand: HomeAutomationConditionOperand,
        comparison: HomeAutomationComparisonCondition,
        devices: [HomeCandidateRecord]
    ) -> OperandResolutionOutput {
        guard case .deviceAttribute(let description, let deviceID, let capability, let attribute) = operand else {
            return OperandResolutionOutput(operand: operand, residualReasons: [])
        }
        guard isEmpty(deviceID) || isEmpty(capability) || isEmpty(attribute) else {
            return OperandResolutionOutput(operand: operand, residualReasons: [])
        }

        var reasons: [AutomationConditionResidualReason] = []
        let capabilityCandidates = explicitCapabilityCandidates(
            for: description,
            comparison: comparison
        )
        if capabilityCandidates.isEmpty {
            reasons.append(.capabilityNotExplicit)
        }

        let candidateDevices = capabilityCandidates.isEmpty
            ? devices
            : devices.filter { device in
                capabilityCandidates.contains { device.capabilities.contains($0) }
            }
        let selected = bestDevice(for: description, devices: candidateDevices)
        guard let device = selected.device else {
            reasons.append(selected.reason ?? .deviceNotResolved)
            return OperandResolutionOutput(operand: operand, residualReasons: stableReasons(reasons))
        }

        let resolvedCapability = capabilityCandidates.first { device.capabilities.contains($0) }
        guard let resolvedCapability else {
            reasons.append(.capabilityNotAdvertised)
            return OperandResolutionOutput(operand: operand, residualReasons: stableReasons(reasons))
        }
        let resolvedAttribute = validAttribute(nil, capability: resolvedCapability)
        return OperandResolutionOutput(
            operand: .deviceAttribute(
                description: description,
                deviceID: device.id,
                capability: resolvedCapability,
                attribute: resolvedAttribute
            ),
            residualReasons: stableReasons(reasons)
        )
    }

    private func bestDevice(for description: String, devices: [HomeCandidateRecord]) -> DeviceSelection {
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
        guard let best = sorted.first else {
            return DeviceSelection(device: nil, reason: .deviceNotResolved)
        }
        guard best.score >= 6 else {
            return DeviceSelection(device: nil, reason: .deviceNotResolved)
        }
        if let second = sorted.dropFirst().first, best.score - second.score < 2 {
            return DeviceSelection(device: nil, reason: .deviceNotUnique)
        }
        return DeviceSelection(device: best.device, reason: nil)
    }

    private func score(_ device: HomeCandidateRecord, query: String) -> Int {
        var total = 0
        let query = meaningfulQuery(query)
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
        if (query.contains("presence") || query.contains("home")),
           device.capabilities.contains("presenceSensor") {
            total += 6
        }
        return total
    }

    private func explicitCapabilityCandidates(
        for description: String,
        comparison: HomeAutomationComparisonCondition
    ) -> [String] {
        let query = normalize(description)
        var candidates: [String] = []
        func append(_ capability: String) {
            if !candidates.contains(capability) {
                candidates.append(capability)
            }
        }
        if query.contains("brightness") || query.contains("level") || query.contains("dim") {
            append("switchLevel")
        }
        if query.contains("color temperature") || query.contains("colour temperature") {
            append("colorTemperature")
        }
        if query.contains("motion") { append("motionSensor") }
        if query.contains("temperature") { append("temperatureMeasurement") }
        if query.contains("humidity") { append("relativeHumidityMeasurement") }
        if query.contains("contact") { append("contactSensor") }
        if query.contains("presence") || query.contains("someone is home") || query.contains("home") {
            append("presenceSensor")
        }
        if query.contains("battery") { append("battery") }
        if query.contains("power") { append("powerMeter") }
        if query.contains("energy") { append("energyMeter") }
        if case .literalString(let value) = comparison.right {
            switch value {
            case "locked", "unlocked":
                append("lock")
            case "open", "closed":
                append("contactSensor")
                append("garageDoorControl")
                append("doorControl")
                append("windowShade")
            case "on", "off":
                append("switch")
            case "active", "inactive":
                append("motionSensor")
            case "present", "not present":
                append("presenceSensor")
            default:
                break
            }
        }
        return candidates
    }

    private func validAttribute(_ attribute: String?, capability: String) -> String {
        Self.validAttribute(attribute, capability: capability)
    }

    /// Shared attribute validation: keeps a caller-supplied attribute when the catalog lists it,
    /// otherwise falls back to the capability's first attribute. Reused by the single and batch
    /// resolvers so the deterministic condition logic has one source of truth.
    static func validAttribute(_ attribute: String?, capability: String) -> String {
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

    // MARK: - Semantic Validation

    private func validateDeterministicCondition(
        _ condition: HomeAutomationCondition,
        expectedTriggerPolicy: HomeAutomationConditionTriggerPolicy
    ) -> [AutomationConditionResidualReason] {
        switch condition {
        case .comparison(let comparison):
            return validateComparison(comparison, expectedTriggerPolicy: expectedTriggerPolicy)
        case .and(let children), .or(let children):
            return children.flatMap {
                validateDeterministicCondition($0, expectedTriggerPolicy: expectedTriggerPolicy)
            }
        case .not(let child), .changes(let child):
            return validateDeterministicCondition(child, expectedTriggerPolicy: expectedTriggerPolicy)
        }
    }

    private func validateComparison(
        _ comparison: HomeAutomationComparisonCondition,
        expectedTriggerPolicy: HomeAutomationConditionTriggerPolicy
    ) -> [AutomationConditionResidualReason] {
        var reasons: [AutomationConditionResidualReason] = []
        if comparison.triggerPolicy != expectedTriggerPolicy {
            reasons.append(.triggerPolicyNotPreserved)
        }

        guard case .deviceAttribute(_, let deviceID, let capability, let attribute) = comparison.left,
              deviceID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              let capability,
              !capability.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let attribute,
              !attribute.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            reasons.append(.deviceNotResolved)
            return stableReasons(reasons)
        }

        guard let definition = HomeCapabilityRegistry.definitions[capability] else {
            reasons.append(.capabilityNotAdvertised)
            return stableReasons(reasons)
        }
        if !definition.attributeNames.contains(attribute) {
            reasons.append(.attributeNotValid)
        }
        reasons.append(contentsOf: validateOperatorAndValue(comparison, definition: definition))
        return stableReasons(reasons)
    }

    private func validateOperatorAndValue(
        _ comparison: HomeAutomationComparisonCondition,
        definition: HomeCapabilityDefinition
    ) -> [AutomationConditionResidualReason] {
        switch comparison.operatorName {
        case .between:
            guard case .literalRange(let start, let end, let unit) = comparison.right else {
                return [.operatorNotValid]
            }
            guard start <= end else { return [.valueTypeInvalid] }
            return validateNumericValues([start, end], unit: unit, definition: definition)

        case .greaterThan, .lessThan, .greaterThanOrEquals, .lessThanOrEquals:
            guard case .literalNumber(let value, let unit) = comparison.right else {
                return [.operatorNotValid]
            }
            return validateNumericValues([value], unit: unit, definition: definition)

        case .equals:
            switch comparison.right {
            case .literalString(let value):
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return [.valueTypeInvalid]
                }
                if !definition.enumValues.isEmpty && !definition.enumValues.contains(value) {
                    return [.enumValueNotFound]
                }
                return []
            case .literalNumber(let value, let unit):
                return validateNumericValues([value], unit: unit, definition: definition)
            case .locationMode:
                return []
            default:
                return [.valueTypeInvalid]
            }

        case .changes:
            return [.operatorNotValid]
        }
    }

    private func validateNumericValues(
        _ values: [Double],
        unit: String?,
        definition: HomeCapabilityDefinition
    ) -> [AutomationConditionResidualReason] {
        if values.contains(where: { !$0.isFinite }) {
            return [.valueTypeInvalid]
        }
        if let range = definition.numericRange,
           values.contains(where: { !range.contains($0) }) {
            return [.numberOutOfRange]
        }
        if let unit,
           !isUnit(unit, compatibleWith: definition.id) {
            return [.unitMismatch]
        }
        return []
    }

    private func isUnit(_ unit: String, compatibleWith capability: String) -> Bool {
        let normalized = normalize(unit)
        guard !normalized.isEmpty else { return true }
        switch capability {
        case "temperatureMeasurement",
             "thermostatCoolingSetpoint",
             "thermostatHeatingSetpoint",
             "ovenSetpoint":
            return ["celsius", "fahrenheit", "degree", "degrees"].contains(normalized)
        case "switchLevel",
             "windowShadeLevel",
             "battery",
             "audioVolume",
             "colorControl":
            return ["percent", "percentage"].contains(normalized)
        case "colorTemperature":
            return ["k", "kelvin"].contains(normalized)
        default:
            return false
        }
    }

    private func completeness(
        for reasons: [AutomationConditionResidualReason]
    ) -> AutomationConditionCompleteness {
        if reasons.contains(.deviceNotUnique) { return .ambiguous }
        if reasons.contains(.parseFailure) ||
            reasons.contains(.unsupportedTreeForm) ||
            reasons.contains(.unsupportedClauseForm) {
            return .unsupported
        }
        return .partial
    }

    private func stableReasons(
        _ reasons: [AutomationConditionResidualReason]
    ) -> [AutomationConditionResidualReason] {
        Array(Set(reasons)).sorted { $0.rawValue < $1.rawValue }
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

    private func meaningfulQuery(_ value: String) -> String {
        let stopWords: Set<String> = ["a", "an", "the", "it", "its", "is"]
        return value
            .split(separator: " ")
            .map(String.init)
            .filter { !stopWords.contains($0) }
            .joined(separator: " ")
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
