import Foundation
import FoundationModels
import HomeAutomationAgents
import HomeAutomationCore
import os

/// FM output model for condition operand resolution.
@Generable
struct ConditionOperandFMResult: Sendable, Hashable, Codable {
    @Guide(description: "The device ID from the provided device list.")
    let deviceID: String
    @Guide(description: "The SmartThings capability name (e.g. temperatureMeasurement, motionSensor, switch).")
    let capability: String
    @Guide(description: "The attribute name for the capability (e.g. temperature, motion, switch).")
    let attribute: String
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    let confidence: Double
}

public struct AutomationConditionOperandResolver: Sendable {
    private let registry: MockHomeDeviceRegistry
    private let foundationModelAvailability: @Sendable () -> Bool
    private let logger = Logger(subsystem: "HomeAutomation", category: "Automation.ConditionOperandResolver")

    public init(
        registry: MockHomeDeviceRegistry,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        }
    ) {
        self.registry = registry
        self.foundationModelAvailability = foundationModelAvailability
    }

    public func resolve(_ condition: HomeAutomationCondition?) async -> HomeAutomationCondition? {
        guard let condition else { return nil }
        let devices = await registry.allDevices()
        let (resolvedRoots, _) = await resolveRoots(
            [ConditionRoot(path: "condition", condition: condition)],
            devices: devices
        )
        return resolvedRoots["condition"]
    }

    public func resolveDraft(_ draft: HomeAutomationRuleDraft) async -> AutomationConditionResolutionOutput {
        let devices = await registry.allDevices()
        var roots: [ConditionRoot] = []
        if let condition = draft.condition {
            roots.append(ConditionRoot(path: "condition", condition: condition))
        }
        if case .device(let trigger) = draft.trigger {
            roots.append(ConditionRoot(path: "trigger.condition", condition: trigger.condition))
        }

        let (resolvedRoots, records) = await resolveRoots(roots, devices: devices)
        let resolvedTrigger = resolvedTrigger(
            draft.trigger,
            resolvedTriggerCondition: resolvedRoots["trigger.condition"]
        )
        let resolvedDraft = HomeAutomationRuleDraft(
            name: draft.name,
            domain: draft.domain,
            operation: draft.operation,
            intent: draft.intent,
            trigger: resolvedTrigger,
            condition: resolvedRoots["condition"] ?? draft.condition,
            actionDescriptions: draft.actionDescriptions,
            confidence: draft.confidence
        )
        return AutomationConditionResolutionOutput(
            ruleDraft: resolvedDraft,
            records: records
        )
    }

    private func resolveRoots(
        _ roots: [ConditionRoot],
        devices: [HomeCandidateRecord]
    ) async -> ([String: HomeAutomationCondition], [AutomationConditionOperandResolutionRecord]) {
        var workItems: [ConditionOperandWorkItem] = []
        for root in roots {
            collectWorkItems(
                from: root.condition,
                path: root.path,
                workItems: &workItems
            )
        }

        let records = await resolve(workItems: workItems, devices: devices)
        let replacements = Dictionary(uniqueKeysWithValues: records.map { ($0.path, $0.output) })
        let resolvedRoots = roots.reduce(into: [String: HomeAutomationCondition]()) { partial, root in
            partial[root.path] = apply(replacements, to: root.condition, path: root.path)
        }
        return (resolvedRoots, records)
    }

    private func collectWorkItems(
        from condition: HomeAutomationCondition,
        path: String,
        workItems: inout [ConditionOperandWorkItem]
    ) {
        switch condition {
        case .and(let children), .or(let children):
            for (index, child) in children.enumerated() {
                collectWorkItems(
                    from: child,
                    path: "\(path).\(index)",
                    workItems: &workItems
                )
            }
        case .not(let child):
            collectWorkItems(
                from: child,
                path: "\(path).not",
                workItems: &workItems
            )
        case .changes(let child):
            collectWorkItems(
                from: child,
                path: "\(path).changes",
                workItems: &workItems
            )
        case .comparison(let comparison):
            collectWorkItem(
                operand: comparison.left,
                comparison: comparison,
                path: "\(path).left",
                workItems: &workItems
            )
            collectWorkItem(
                operand: comparison.right,
                comparison: comparison,
                path: "\(path).right",
                workItems: &workItems
            )
        }
    }

    private func collectWorkItem(
        operand: HomeAutomationConditionOperand,
        comparison: HomeAutomationComparisonCondition,
        path: String,
        workItems: inout [ConditionOperandWorkItem]
    ) {
        guard needsDeviceOperandResolution(operand) else { return }
        let order = workItems.count
        workItems.append(
            ConditionOperandWorkItem(
                id: "c\(order + 1)",
                order: order,
                path: path,
                operand: operand,
                comparison: comparison
            )
        )
    }

    private func resolve(
        workItems: [ConditionOperandWorkItem],
        devices: [HomeCandidateRecord]
    ) async -> [AutomationConditionOperandResolutionRecord] {
        guard !workItems.isEmpty else { return [] }

        let records = await withTaskGroup(of: AutomationConditionOperandResolutionRecord.self) { group in
            for item in workItems {
                group.addTask {
                    let output = await self.resolveOperand(
                        item.operand,
                        devices: devices,
                        comparison: item.comparison
                    )
                    return AutomationConditionOperandResolutionRecord(
                        id: item.id,
                        order: item.order,
                        path: item.path,
                        description: item.description,
                        input: item.operand,
                        output: output
                    )
                }
            }

            var records: [AutomationConditionOperandResolutionRecord] = []
            for await record in group {
                records.append(record)
            }
            return records
        }

        return records.sorted { $0.order < $1.order }
    }

    private func apply(
        _ replacements: [String: HomeAutomationConditionOperand],
        to condition: HomeAutomationCondition,
        path: String
    ) -> HomeAutomationCondition {
        switch condition {
        case .and(let children):
            return .and(children.enumerated().map { index, child in
                apply(replacements, to: child, path: "\(path).\(index)")
            })
        case .or(let children):
            return .or(children.enumerated().map { index, child in
                apply(replacements, to: child, path: "\(path).\(index)")
            })
        case .not(let child):
            return .not(apply(replacements, to: child, path: "\(path).not"))
        case .changes(let child):
            return .changes(apply(replacements, to: child, path: "\(path).changes"))
        case .comparison(let comparison):
            return .comparison(
                HomeAutomationComparisonCondition(
                    left: replacements["\(path).left"] ?? comparison.left,
                    operatorName: comparison.operatorName,
                    right: replacements["\(path).right"] ?? comparison.right,
                    triggerPolicy: comparison.triggerPolicy
                )
            )
        }
    }

    private func resolvedTrigger(
        _ trigger: HomeAutomationTrigger?,
        resolvedTriggerCondition: HomeAutomationCondition?
    ) -> HomeAutomationTrigger? {
        guard let trigger else { return nil }
        switch trigger {
        case .schedule:
            return trigger
        case .device(let deviceTrigger):
            return .device(
                HomeAutomationDeviceTrigger(
                    description: deviceTrigger.description,
                    condition: resolvedTriggerCondition ?? deviceTrigger.condition
                )
            )
        }
    }

    private func needsDeviceOperandResolution(_ operand: HomeAutomationConditionOperand) -> Bool {
        guard case .deviceAttribute(_, let deviceID, let capability, let attribute) = operand else {
            return false
        }
        return isEmpty(deviceID) || isEmpty(capability) || isEmpty(attribute)
    }

    // MARK: - Model-First Resolution

    /// Resolves an operand using FM when available, with deterministic scoring as hint and fallback.
    private func resolveOperand(
        _ operand: HomeAutomationConditionOperand,
        devices: [HomeCandidateRecord],
        comparison: HomeAutomationComparisonCondition
    ) async -> HomeAutomationConditionOperand {
        guard case .deviceAttribute(let description, let deviceID, let capability, let attribute) = operand,
              deviceID == nil || capability == nil || attribute == nil else {
            return operand
        }

        // Compute deterministic result for hint and fallback
        let deterministicResult = resolveDeterministic(
            operand,
            devices: devices,
            comparison: comparison
        )
        logger.debug("[Deterministic] description=\(description, privacy: .public) result=\(String(describing: deterministicResult), privacy: .public)")

        // If FM unavailable, use deterministic
        guard foundationModelAvailability() else {
            logger.info("[Availability] Foundation model unavailable, using deterministic result.")
            return deterministicResult
        }

        // Build FM prompt
        let deviceList = devices.map { device in
            let caps = device.capabilities.joined(separator: ", ")
            let room = device.room ?? "unknown"
            return "- id=\(device.id), name=\(device.displayName), type=\(device.deviceType), room=\(room), capabilities=[\(caps)]"
        }.joined(separator: "\n")

        let comparisonContext: String
        switch comparison.right {
        case .literalString(let value):
            comparisonContext = "The right-hand value is '\(value)' (string)."
        case .literalNumber(let value, let unit):
            comparisonContext = "The right-hand value is \(value)\(unit.map { " \($0)" } ?? "") (number)."
        case .literalRange(let start, let end, let unit):
            comparisonContext = "The right-hand value is between \(start) and \(end)\(unit.map { " \($0)" } ?? "") (range)."
        default:
            comparisonContext = ""
        }

        var hintText = ""
        if case .deviceAttribute(_, let hintDeviceID, let hintCapability, let hintAttribute) = deterministicResult,
           hintDeviceID != nil {
            hintText = """

            Deterministic scoring suggests: deviceID=\(hintDeviceID ?? "nil"), \
            capability=\(hintCapability ?? "nil"), attribute=\(hintAttribute ?? "nil"). \
            Verify or correct.
            """
        }

        let instructionsText = """
        Resolve a condition operand description to a specific device, capability, and attribute.
        You MUST select a deviceID from the provided device list.
        Select the capability that best matches the operand description and comparison context.
        Select the attribute name for that capability.
        """

        let prompt = """
        Operand description: "\(description)"
        Operator: \(comparison.operatorName.rawValue)
        \(comparisonContext)

        Available devices:
        \(deviceList)
        \(hintText)
        """

        logger.debug("[FoundationModelInput] prompt: \(prompt.prefix(300), privacy: .public)...")

        do {
            let session = LanguageModelSession(instructions: Instructions(instructionsText))
            let fmResult = try await session.respond(
                to: Prompt(prompt),
                generating: ConditionOperandFMResult.self
            ).content
            logger.debug("[FoundationModelOutput] result: \(String(describing: fmResult), privacy: .public)")

            // Validate FM output against device registry
            guard let matchedDevice = devices.first(where: { $0.id == fmResult.deviceID }),
                  matchedDevice.capabilities.contains(fmResult.capability) else {
                logger.warning("[Validation] FM result deviceID or capability not found in registry, using deterministic fallback.")
                return deterministicResult
            }

            // Validate attribute exists for the capability
            let validAttribute: String
            if let definition = HomeCapabilityRegistry.definitions[fmResult.capability],
               definition.attributeNames.contains(fmResult.attribute) {
                validAttribute = fmResult.attribute
            } else if let definition = HomeCapabilityRegistry.definitions[fmResult.capability],
                      let firstAttr = definition.attributeNames.first {
                validAttribute = firstAttr
                logger.info("[Validation] FM attribute '\(fmResult.attribute, privacy: .public)' not found, using '\(firstAttr, privacy: .public)'.")
            } else {
                logger.warning("[Validation] No valid attribute for capability, using deterministic fallback.")
                return deterministicResult
            }

            return .deviceAttribute(
                description: description,
                deviceID: fmResult.deviceID,
                capability: fmResult.capability,
                attribute: validAttribute
            )
        } catch {
            logger.error("[FoundationModelError] error: \(error.localizedDescription, privacy: .public), using deterministic fallback.")
            return deterministicResult
        }
    }

    // MARK: - Deterministic Resolution (preserved as fallback/hint)

    private func resolveDeterministic(
        _ operand: HomeAutomationConditionOperand,
        devices: [HomeCandidateRecord],
        comparison: HomeAutomationComparisonCondition
    ) -> HomeAutomationConditionOperand {
        guard case .deviceAttribute(let description, let deviceID, let capability, let attribute) = operand,
              deviceID == nil || capability == nil || attribute == nil else {
            return operand
        }

        guard let device = bestDevice(for: description, devices: devices),
              let resolvedCapability = bestCapability(
                for: description,
                device: device,
                comparison: comparison
              ),
              let resolvedAttribute = HomeCapabilityRegistry.definitions[resolvedCapability]?.attributeNames.first else {
            return operand
        }

        return .deviceAttribute(
            description: description,
            deviceID: device.id,
            capability: resolvedCapability,
            attribute: resolvedAttribute
        )
    }

    private func bestDevice(
        for description: String,
        devices: [HomeCandidateRecord]
    ) -> HomeCandidateRecord? {
        let query = normalize(description)
        let scored = devices.map { device in
            (device, score(device, query: query))
        }
        .filter { $0.1 > 0 }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.0.displayName < rhs.0.displayName
            }
            return lhs.1 > rhs.1
        }
        guard let first = scored.first else { return nil }
        if scored.dropFirst().first?.1 == first.1 {
            return nil
        }
        return first.0
    }

    private func score(_ device: HomeCandidateRecord, query: String) -> Int {
        var total = 0
        let name = normalize(device.displayName)
        let type = normalize(device.deviceType)
        let room = device.room.map(normalize)
        let aliases = device.metadata["aliases"]?
            .split(separator: ",")
            .map { normalize(String($0)) } ?? []
        if query.contains(name) { total += 12 }
        if query.contains(type) { total += 8 }
        if let room, query.contains(room) { total += 5 }
        for alias in aliases where query.contains(alias) {
            total += 6
        }
        if query.contains("window") || query.contains("door") {
            if device.capabilities.contains("contactSensor") { total += 4 }
            if device.capabilities.contains("garageDoorControl") { total += 4 }
            if device.capabilities.contains("doorControl") { total += 4 }
            if device.capabilities.contains("windowShade") { total += 4 }
        }
        if query.contains("motion"), device.capabilities.contains("motionSensor") {
            total += 6
        }
        if query.contains("temperature"), device.capabilities.contains("temperatureMeasurement") {
            total += 6
        }
        return total
    }

    private func bestCapability(
        for description: String,
        device: HomeCandidateRecord,
        comparison: HomeAutomationComparisonCondition
    ) -> String? {
        let query = normalize(description)
        if query.contains("motion"), device.capabilities.contains("motionSensor") {
            return "motionSensor"
        }
        if query.contains("temperature"), device.capabilities.contains("temperatureMeasurement") {
            return "temperatureMeasurement"
        }
        if (query.contains("level") || query.contains("brightness")),
           device.capabilities.contains("switchLevel") {
            return "switchLevel"
        }
        if case .literalString(let value) = comparison.right {
            switch value {
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
            guard let definition = HomeCapabilityRegistry.definitions[capability] else { return false }
            return definition.commands.isEmpty && !definition.attributeNames.isEmpty
        }
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
}

private struct ConditionRoot: Sendable {
    let path: String
    let condition: HomeAutomationCondition
}

private struct ConditionOperandWorkItem: Sendable {
    let id: String
    let order: Int
    let path: String
    let operand: HomeAutomationConditionOperand
    let comparison: HomeAutomationComparisonCondition

    var description: String {
        switch operand {
        case .deviceAttribute(let description, _, _, _):
            return description
        case .literalString(let value), .locationMode(let value), .unsupported(let value):
            return value
        case .literalNumber(let value, let unit):
            return unit.map { "\(value) \($0)" } ?? "\(value)"
        case .literalRange(let start, let end, let unit):
            let range = "\(start)-\(end)"
            return unit.map { "\(range) \($0)" } ?? range
        }
    }
}
