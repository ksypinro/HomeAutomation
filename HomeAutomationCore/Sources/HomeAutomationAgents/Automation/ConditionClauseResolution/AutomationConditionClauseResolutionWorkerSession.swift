import Foundation
import FoundationModels
import HomeAutomationCore
import os

public struct AutomationConditionClauseResolutionWorkerSession: Sendable {
    public static let sessionInstructions = AutomationConditionClauseResolutionPromptBuilder.instructions
    private let foundationModelAvailability: @Sendable () -> Bool
    private let resolve: (@Sendable (AutomationConditionClauseResolutionInput) async throws -> AutomationConditionClauseFMOutput)?
    private let deterministicAcceptThreshold: Double
    private let sessionPool: FoundationModelSessionPool?
    private let timeoutConfiguration: FoundationModelTimeoutConfiguration
    private let deterministicResolver = AutomationConditionDeterministicResolver()
    private let roundTripTarget: AutomationConditionGraphTarget
    private let logger = Logger(subsystem: "HomeAutomation", category: "Automation.ConditionClauseResolution")

    public init(
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        resolve: (@Sendable (AutomationConditionClauseResolutionInput) async throws -> AutomationConditionClauseFMOutput)? = nil,
        deterministicAcceptThreshold: Double = 0.8,
        sessionPool: FoundationModelSessionPool? = nil,
        timeoutConfiguration: FoundationModelTimeoutConfiguration = .default
    ) {
        self.foundationModelAvailability = foundationModelAvailability
        self.resolve = resolve
        self.deterministicAcceptThreshold = deterministicAcceptThreshold
        self.sessionPool = sessionPool
        self.timeoutConfiguration = timeoutConfiguration
        self.roundTripTarget = AutomationConditionGraphTarget()
    }

    private var serviceTimeoutNanoseconds: UInt64 {
        UInt64(max(0, timeoutConfiguration.serviceTimeoutMs) * 1_000_000)
    }

    public func resolve(
        _ input: AutomationConditionClauseResolutionInput
    ) async throws -> AutomationConditionClauseResolutionResult {
        let assessment = deterministicResolver.assess(input: input)

        if assessment.isSafeToAccept(for: roundTripTarget), assessment.confidence >= deterministicAcceptThreshold {
            logger.debug("[τ-gate] Deterministic condition confidence \(assessment.confidence) ≥ \(self.deterministicAcceptThreshold); skipping FM.")
            return AutomationConditionClauseResolutionResult(
                id: input.component.id,
                rawText: input.component.rawText,
                condition: assessment.condition,
                records: assessment.records,
                confidence: assessment.confidence
            )
        }

        if let resolve {
            return try result(from: try await resolve(input), input: input, fallback: assessment.condition)
        }

        guard foundationModelAvailability() else {
            return AutomationConditionClauseResolutionResult(
                id: input.component.id,
                rawText: input.component.rawText,
                condition: assessment.condition,
                records: assessment.records,
                confidence: assessment.confidence
            )
        }

        let prompt = AutomationConditionClauseResolutionPromptBuilder.prompt(input: input, fallback: assessment.condition)
        logger.debug("[FoundationModelInput] \(prompt, privacy: .public)")
        var pooledSession: LanguageModelSession?
        do {
            let session: LanguageModelSession
            if let sessionPool {
                session = await sessionPool.acquire(kind: .conditionClause)
                pooledSession = session
            } else {
                session = LanguageModelSession(
                    instructions: Instructions(AutomationConditionClauseResolutionPromptBuilder.instructions)
                )
            }
            let fmOutput = try await FoundationModelCallRecorder.record(
                agentID: AgentID.automationConditionClauseResolution.rawValue,
                policyMode: "model-first-with-fallback",
                modelAvailability: "available",
                promptCharacterCount: AutomationConditionClauseResolutionPromptBuilder.instructions.count + prompt.count,
                selectedToolNames: ["availableConditionDevices", "capabilityAttributeCatalog"],
                serviceTimeoutNanoseconds: serviceTimeoutNanoseconds
            ) {
                try await session.respond(
                    to: Prompt(prompt),
                    generating: AutomationConditionClauseFMOutput.self
                ).content
            }
            if let sessionPool {
                await sessionPool.release(kind: .conditionClause, session: session)
                pooledSession = nil
            }
            let output = try result(from: fmOutput, input: input, fallback: assessment.condition)
            logger.debug("[FoundationModelOutput] \(String(describing: output), privacy: .public)")
            return output
        } catch {
            if let sessionPool, let pooledSession {
                await sessionPool.discard(kind: .conditionClause, session: pooledSession, reason: .failed)
            }
            logger.error("[FoundationModelError] \(error.localizedDescription, privacy: .public); using deterministic condition fallback.")
            return AutomationConditionClauseResolutionResult(
                id: input.component.id,
                rawText: input.component.rawText,
                condition: assessment.condition,
                records: assessment.records,
                confidence: assessment.confidence
            )
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

    private func validAttribute(_ attribute: String?, capability: String) -> String {
        guard let definition = HomeCapabilityRegistry.definitions[capability] else {
            return attribute ?? capability
        }
        if let attribute, definition.attributeNames.contains(attribute) {
            return attribute
        }
        return definition.attributeNames.first ?? attribute ?? capability
    }

    private func isEmpty(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
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
}
